// Real acoustic-event fan-out and independent endpoint consumers; no audio/network.
#define main PresenterApplicationMain
#import "../Sources/main.m"
#undef main

@interface LaneTestText : NSObject
@property NSString *string;
@property NSColor *textColor;
@end
@implementation LaneTestText
@end

@interface IndependentSpeechTestApp : AppDelegate
@property NSMutableArray<NSString *> *committedQuestions;
@property NSMutableArray<NSString *> *autoCandidates;
@property NSUInteger recognitionStarts;
@property NSUInteger recognitionRestarts;
@property BOOL forceEnhancedAuto;
@end
@implementation IndependentSpeechTestApp
- (instancetype)init {
    if ((self=[super init])) {
        self.timeline=[SCSpeechTimeline new]; self.manualUntimedBuffer=[SCUntimedTranscriptBuffer new];
        self.autoDetector=[SCAutoQuestionDetector new];
        self.committedQuestions=[NSMutableArray array]; self.autoCandidates=[NSMutableArray array];
        LaneTestText *manual=[LaneTestText new]; manual.string=@"";
        LaneTestText *automatic=[LaneTestText new]; automatic.string=@"";
        self.transcriptView=(NSTextView *)manual; self.autoTranscriptView=(NSTextView *)automatic;
        self.listening=YES;
        self.autoTimer=[NSTimer timerWithTimeInterval:.1 target:self selector:@selector(tickAutoRecognition:) userInfo:nil repeats:YES];
    }
    return self;
}
- (void)appendOfflineAnswerForQuestion:(NSString *)question { [self.committedQuestions addObject:question ?: @""]; }
- (void)autoRecogniseQuestionText:(NSString *)question fast:(BOOL)fast { [self.autoCandidates addObject:question ?: @""]; }
- (void)refreshManualAnswerPanel {}
- (void)refreshAutoAnswerPanel {}
- (void)setStatus:(NSString *)text color:(NSColor *)color {}
- (void)beginSpeechTask { self.recognitionStarts++; }
- (void)restartSpeechTaskOnly { self.recognitionRestarts++; [super restartSpeechTaskOnly]; }
- (BOOL)enhancedAutoTranscriptionEnabled { return self.forceEnhancedAuto || [super enhancedAutoTranscriptionEnabled]; }
@end

static NSUInteger checks=0, failures=0;
static NSDictionary *Word(NSString *text, double start, double end) { return @{@"text":text,@"start":@(start),@"end":@(end)}; }
static NSString *Joined(NSArray<NSDictionary *> *segments) { return [[segments valueForKey:@"text"] componentsJoinedByString:@" "]; }
static void Receive(IndependentSpeechTestApp *app, NSArray<NSDictionary *> *segments, double audioTime, BOOL final) {
    app.audioTime=audioTime; [app receiveSpeechSegments:segments text:Joined(segments) final:final];
}
static void Check(BOOL value, NSString *message) { checks++; if(!value) { failures++; fprintf(stderr,"FAIL: %s\n",message.UTF8String); } }
static void Equal(NSString *actual, NSString *expected, NSString *message) {
    Check([actual isEqualToString:expected],[NSString stringWithFormat:@"%@ — expected <%@>, actual <%@>",message,expected,actual]);
}
static void DrainAuto(IndependentSpeechTestApp *app) {
    NSArray *ready=[app.autoDetector tickWithAudioTime:app.audioTime now:NSProcessInfo.processInfo.systemUptime+2];
    [app consumeAutoCandidates:ready]; [app flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime+2 force:YES]; [app refreshAutoLiveTranscript];
}
static void CleanUp(IndependentSpeechTestApp *app) {
    [app.autoTimer invalidate]; [app.silenceTimer invalidate]; [app.spaceSettleTimer invalidate]; [app.spaceDeadlineTimer invalidate]; app.listening=NO;
}

int main(void) {
    @autoreleasepool {
        NSArray *partial=@[Word(@"What",.1,.3),Word(@"is",.4,.6),Word(@"cleaning",.7,1.0)];
        NSArray *complete=@[Word(@"What",.1,.3),Word(@"is",.4,.6),Word(@"cleaning",.7,1.0),Word(@"and",1.2,1.4),Word(@"sanitising?",1.5,2.0)];
        NSArray *following=@[Word(@"Which",2.4,2.6),Word(@"knife",2.7,2.9),Word(@"is",3,3.1),Word(@"best?",3.2,3.5)];
        NSString *first=Joined(complete), *second=Joined(following);
        NSArray *lateWithNext=[complete arrayByAddingObjectsFromArray:following];
        IndependentSpeechTestApp *app=[IndependentSpeechTestApp new];
        Receive(app,partial,2.2,NO);
        NSTimer *autoTimer=app.autoTimer; SCAutoQuestionDetector *detector=app.autoDetector;
        Equal(app.transcriptView.string,@"What is cleaning",@"SPACE live display reflects current partial");
        Equal(app.autoTranscriptView.string,@"What is cleaning",@"AUTO has its own live display");
        [app commitCurrentQuestionFromSpace];
        Check(app.spaceCommitPending && app.committedQuestions.count==0,@"Timed Space retains bounded interval for late words");
        Check(app.manualCursor==2.2,@"Space advances only its own audio cursor");
        Check(app.autoTimer==autoTimer && app.autoTimer.isValid,@"Space cannot cancel or replace AUTO timer");
        Check(app.autoDetector==detector,@"Space does not reset AUTO detector");
        Equal(app.autoTranscript,@"What is cleaning",@"Space does not clear AUTO pending words");
        Check(app.recognitionRestarts==0 && app.recognitionStarts==0,@"Space does not restart acoustic recognition");
        Receive(app,lateWithNext,3.7,NO);
        Equal(app.spaceTranscriptSnapshot,first,@"Late words selected from pre-Space audio interval");
        Equal(app.latestTranscript,second,@"Words after Space belong to next manual interval");
        [app finishSpaceCommit];
        Equal(app.committedQuestions.firstObject,first,@"Manual includes late tail and excludes next question");
        [app finishSpaceCommit]; Check(app.committedQuestions.count==1,@"Repeated finish cannot submit twice");
        Equal(app.autoTranscript,Joined(lateWithNext),@"SPACE completion preserves unconsumed AUTO questions");
        DrainAuto(app);
        Check(app.autoCandidates.count==1,@"AUTO keeps one clean record for one speaking turn instead of spamming separate answer cards");
        if(app.autoCandidates.count==1) {
          Check([app.autoCandidates.firstObject containsString:first] && [app.autoCandidates.firstObject containsString:second],@"The single AUTO request still preserves both heard questions");
        }
        Equal(app.latestTranscript,second,@"AUTO consumption leaves SPACE live words intact");
        [app commitCurrentQuestionFromSpace]; [app finishSpaceCommit];
        Equal(app.committedQuestions.lastObject,second,@"Second Space submits only next manual question");
        Receive(app,lateWithNext,3.9,NO); DrainAuto(app);
        Check(app.autoCandidates.count==1,@"Cumulative callbacks do not replay the combined AUTO turn");
        Check(app.committedQuestions.count==2,@"AUTO does not create manual answers"); CleanUp(app);

        IndependentSpeechTestApp *finalSame=[IndependentSpeechTestApp new];
        Receive(finalSame,complete,2.2,NO); [finalSame commitCurrentQuestionFromSpace]; Receive(finalSame,complete,2.3,YES);
        Check(finalSame.spaceSettleTimer!=nil && finalSame.spaceSettleTimer.isValid,@"Identical final text schedules manual settle");
        [finalSame finishSpaceCommit]; Equal(finalSame.committedQuestions.firstObject,first,@"Unchanged final retains visible question"); CleanUp(finalSame);

        IndependentSpeechTestApp *autoFirst=[IndependentSpeechTestApp new];
        Receive(autoFirst,complete,2.2,YES); [autoFirst commitCurrentQuestionFromSpace];
        NSTimeInterval pendingFrom=autoFirst.pendingSpaceFrom, pendingTo=autoFirst.pendingSpaceTo;
        DrainAuto(autoFirst); Check(autoFirst.autoCandidates.count==1,@"AUTO can answer while Space waits");
        Check(autoFirst.spaceCommitPending && autoFirst.pendingSpaceFrom==pendingFrom && autoFirst.pendingSpaceTo==pendingTo,@"AUTO cannot alter pending Space boundaries");
        [autoFirst finishSpaceCommit]; Equal(autoFirst.committedQuestions.firstObject,first,@"AUTO cannot delete pending Space words"); CleanUp(autoFirst);

        IndependentSpeechTestApp *enhancedFast=[IndependentSpeechTestApp new];
        enhancedFast.forceEnhancedAuto=YES; enhancedFast.audioTime=10; enhancedFast.lastVoiceAudioTime=10; enhancedFast.autoTranscriptionInFlight=YES;
        Receive(enhancedFast,complete,10,YES);
        NSArray *quickReady=[enhancedFast.autoDetector tickWithAudioTime:enhancedFast.audioTime now:NSProcessInfo.processInfo.systemUptime+1];
        [enhancedFast consumeAutoCandidates:quickReady];
        enhancedFast.autoTurnChangedAt=NSProcessInfo.processInfo.systemUptime-1;
        [enhancedFast flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime force:NO];
        Check(enhancedFast.autoCandidates.count==0,@"Enhanced AUTO must not submit while audio is still active");
        enhancedFast.lastVoiceAudioTime=8.9;
        [enhancedFast flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime force:NO];
        Equal(enhancedFast.autoCandidates.firstObject,first,@"Enhanced AUTO submits detector-ready questions after a short silence without waiting for transcription"); CleanUp(enhancedFast);

        IndependentSpeechTestApp *rapid=[IndependentSpeechTestApp new];
        NSArray *fifo=@[Word(@"What",.1,.3),Word(@"is",.4,.5),Word(@"FIFO?",.6,.9)];
        NSArray *haccp=@[Word(@"What",1.1,1.4),Word(@"is",1.5,1.6),Word(@"HACCP?",1.7,1.9)];
        Receive(rapid,fifo,1,NO); [rapid commitCurrentQuestionFromSpace];
        Receive(rapid,[fifo arrayByAddingObjectsFromArray:haccp],2,NO); [rapid commitCurrentQuestionFromSpace];
        Check(rapid.committedQuestions.count==1 && rapid.spaceCommitPending,@"Rapid second Space completes first and opens next interval");
        Equal(rapid.committedQuestions.firstObject,@"What is FIFO?",@"Rapid Space preserves first question");
        [rapid finishSpaceCommit]; Equal(rapid.committedQuestions.lastObject,@"What is HACCP?",@"Rapid Space preserves following question");
        Check(rapid.recognitionRestarts==0,@"Rapid Space never restarts recognizer"); CleanUp(rapid);

        IndependentSpeechTestApp *untimed=[IndependentSpeechTestApp new];
        NSArray *zeroFirst=@[Word(@"What",0,0),Word(@"is",0,0),Word(@"mise",0,0),Word(@"en",0,0),Word(@"place?",0,0)];
        NSArray *zeroNext=@[Word(@"What",0,0),Word(@"is",0,0),Word(@"FIFO?",0,0)];
        Receive(untimed,zeroFirst,3,NO); Check(untimed.manualUsesUntimed,@"Zero timestamps select text fallback");
        Equal(untimed.latestTranscript,@"What is mise en place?",@"Missing timing cannot blank visible question");
        NSTimer *untimedTimer=untimed.autoTimer; [untimed commitCurrentQuestionFromSpace];
        Check(!untimed.spaceCommitPending,@"Untimed Space immediately snapshots visible text");
        Equal(untimed.committedQuestions.firstObject,@"What is mise en place?",@"Untimed Space keeps exact visible question");
        Check(untimed.autoTimer==untimedTimer && untimed.autoTimer.isValid,@"Untimed Space leaves AUTO running");
        Receive(untimed,[zeroFirst arrayByAddingObjectsFromArray:zeroNext],5,NO);
        Equal(untimed.latestTranscript,@"What is FIFO?",@"Zero-timestamp next question remains available");
        DrainAuto(untimed); Check(untimed.autoCandidates.count==1 && [untimed.autoCandidates.firstObject containsString:@"What is mise en place?"] && [untimed.autoCandidates.firstObject containsString:@"What is FIFO?"],@"AUTO keeps all-zero questions in one readable answer record");
        [untimed commitCurrentQuestionFromSpace]; Equal(untimed.committedQuestions.lastObject,@"What is FIFO?",@"Second untimed Space does not repeat first");
        Receive(untimed,[zeroFirst arrayByAddingObjectsFromArray:zeroNext],5.2,YES); DrainAuto(untimed);
        Check(untimed.autoCandidates.count==1 && untimed.committedQuestions.count==2,@"Untimed identical final duplicates neither lane"); CleanUp(untimed);

        IndependentSpeechTestApp *mixed=[IndependentSpeechTestApp new];
        Receive(mixed,fifo,1,NO); [mixed commitCurrentQuestionFromSpace]; [mixed finishSpaceCommit];
        NSArray *mixedZero=@[Word(@"What",0,0),Word(@"is",0,0),Word(@"FIFO?",0,0),Word(@"What",0,0),Word(@"is",0,0),Word(@"HACCP?",0,0)];
        Receive(mixed,mixedZero,2,NO); Equal(mixed.latestTranscript,@"What is HACCP?",@"Metadata loss cannot replay timed consumed words");
        [mixed commitCurrentQuestionFromSpace]; Receive(mixed,[fifo arrayByAddingObjectsFromArray:haccp],2.2,YES);
        Equal(mixed.latestTranscript,@"",@"Timed final cannot restore fallback-consumed words");
        Check(mixed.committedQuestions.count==2,@"Metadata changes preserve two manual questions once"); CleanUp(mixed);

        IndependentSpeechTestApp *rollover=[IndependentSpeechTestApp new];
        Receive(rollover,zeroFirst,3,NO); [rollover restartSpeechTaskOnly];
        Check(rollover.recognitionRestarts==1 && rollover.recognitionStarts==1,@"Real rollover prepares next acoustic request");
        Receive(rollover,zeroNext,5,NO);
        Equal(rollover.latestTranscript,@"What is mise en place? What is FIFO?",@"Rollover carries SPACE's unconsumed question into next task");
        DrainAuto(rollover); Check(rollover.autoCandidates.count==1 && [rollover.autoCandidates.firstObject containsString:@"What is mise en place?"] && [rollover.autoCandidates.firstObject containsString:@"What is FIFO?"],@"AUTO rollover keeps unconsumed questions in one readable answer record");
        [rollover commitCurrentQuestionFromSpace];
        Equal(rollover.committedQuestions.firstObject,@"What is mise en place? What is FIFO?",@"Space after rollover preserves all words since last press");
        Check(rollover.autoCandidates.count==1,@"Space after rollover does not duplicate AUTO results"); CleanUp(rollover);

        IndependentSpeechTestApp *manualRefresh=[IndependentSpeechTestApp new];
        Receive(manualRefresh,complete,2.3,YES); NSString *pending=manualRefresh.autoDetector.pendingText;
        [manualRefresh refreshManualTranscriptFinal:NO]; Equal(manualRefresh.autoDetector.pendingText,pending,@"Manual UI refresh cannot change AUTO state");
        DrainAuto(manualRefresh); Equal(manualRefresh.autoCandidates.firstObject,first,@"AUTO still emits after manual-only refresh"); CleanUp(manualRefresh);

        IndependentSpeechTestApp *fallback=[IndependentSpeechTestApp new];
        NSArray *natural=@[Word(@"I'm",.1,.3),Word(@"curious",.4,.7),Word(@"about",.8,1.0),Word(@"your",1.1,1.3),Word(@"mise",1.4,1.6),Word(@"en",1.7,1.8),Word(@"place?",1.9,2.2)];
        Receive(fallback,natural,2.4,NO);
        fallback.autoPendingChangedAt=NSProcessInfo.processInfo.systemUptime-1;
        [fallback tickAutoRecognition:nil];
        [fallback flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime+2 force:YES];
        Equal(fallback.autoCandidates.firstObject,Joined(natural),@"AUTO safety net commits stable natural question phrasing missed by the grammar starter");
        Check(fallback.autoDetector.pendingText.length==0,@"AUTO safety net consumes its question exactly once"); CleanUp(fallback);

        IndependentSpeechTestApp *stockFix=[IndependentSpeechTestApp new];
        NSArray *misheardStock=@[Word(@"What",.1,.3),Word(@"is",.4,.5),Word(@"stuff",.6,.9),Word(@"in",1.0,1.1),Word(@"cooking?",1.2,1.6)];
        Receive(stockFix,misheardStock,1.8,YES);
        Equal(stockFix.latestTranscript,@"What is stock in cooking?",@"Live SPACE transcript repairs the culinary stock/stuff confusion");
        [stockFix commitCurrentQuestionFromSpace]; [stockFix finishSpaceCommit];
        Equal(stockFix.committedQuestions.firstObject,@"What is stock in cooking?",@"SPACE submits the corrected stock question");
        DrainAuto(stockFix);
        Equal(stockFix.autoCandidates.firstObject,@"What is stock in cooking?",@"AUTO submits the same corrected stock question"); CleanUp(stockFix);

        IndependentSpeechTestApp *grillFix=[IndependentSpeechTestApp new];
        NSArray *misheardGrill=@[Word(@"How",.1,.3),Word(@"do",.4,.5),Word(@"you",.6,.7),Word(@"gorilla",.8,1.1),Word(@"chicken?",1.2,1.6)];
        Receive(grillFix,misheardGrill,1.8,YES);
        Equal(grillFix.latestTranscript,@"How do you grill chicken?",@"Live SPACE transcript repairs the culinary grill/gorilla confusion");
        [grillFix commitCurrentQuestionFromSpace]; [grillFix finishSpaceCommit];
        Equal(grillFix.committedQuestions.firstObject,@"How do you grill chicken?",@"SPACE submits the corrected grill question");
        DrainAuto(grillFix);
        Equal(grillFix.autoCandidates.firstObject,@"How do you grill chicken?",@"AUTO submits the same corrected grill question"); CleanUp(grillFix);

        IndependentSpeechTestApp *stuffVerb=[IndependentSpeechTestApp new];
        NSArray *realStuff=@[Word(@"What",.1,.3),Word(@"do",.4,.5),Word(@"you",.6,.7),Word(@"stuff",.8,1.0),Word(@"inside",1.1,1.3),Word(@"a",1.4,1.5),Word(@"chicken?",1.6,1.9)];
        Receive(stuffVerb,realStuff,2.1,YES); [stuffVerb commitCurrentQuestionFromSpace]; [stuffVerb finishSpaceCommit]; DrainAuto(stuffVerb);
        Equal(stuffVerb.committedQuestions.firstObject,@"What do you stuff inside a chicken?",@"SPACE preserves stuff when it is a real cooking verb");
        Equal(stuffVerb.autoCandidates.firstObject,@"What do you stuff inside a chicken?",@"AUTO preserves stuff when it is a real cooking verb"); CleanUp(stuffVerb);

        IndependentSpeechTestApp *linkedTurn=[IndependentSpeechTestApp new];
        [linkedTurn stageAutoQuestionTurnText:@"What are the ingredients?"];
        [linkedTurn stageAutoQuestionTurnText:@"So what do you have in that?\nWhat are the ingredients?"];
        Check(linkedTurn.autoCandidates.count==0,@"AUTO does not answer the first fragment before the speaking turn ends");
        [linkedTurn flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime+2 force:YES];
        Check(linkedTurn.autoCandidates.count==1,@"Linked fragments produce only one AUTO answer request");
        Check([linkedTurn.autoCandidates.firstObject containsString:@"What are the ingredients?"] && [linkedTurn.autoCandidates.firstObject containsString:@"what do you have in that?"],@"One AUTO request retains both the original and linked clarification");
        CleanUp(linkedTurn);

        IndependentSpeechTestApp *independentTurn=[IndependentSpeechTestApp new];
        [independentTurn stageAutoQuestionTurnText:@"Which knife is most versatile?"];
        [independentTurn stageAutoQuestionTurnText:@"What is the temperature danger zone?"];
        [independentTurn flushAutoQuestionTurnIfReadyAt:NSProcessInfo.processInfo.systemUptime+2 force:YES];
        Check(independentTurn.autoCandidates.count==1,@"Independent AUTO questions from one speaking turn stay in one answer request");
        Check([independentTurn.autoCandidates.firstObject containsString:@"Which knife is most versatile?"] && [independentTurn.autoCandidates.firstObject containsString:@"What is the temperature danger zone?"],@"AUTO keeps both independent questions without creating multiple cards");
        CleanUp(independentTurn);

        IndependentSpeechTestApp *stopped=[IndependentSpeechTestApp new]; stopped.listening=NO; stopped.audioTime=2;
        [stopped commitCurrentQuestionFromSpace]; Check(!stopped.spaceCommitPending && stopped.manualCursor==0,@"Space while stopped creates no boundary"); CleanUp(stopped);
        fprintf(stdout,"%lu independent speech integration checks, %lu failures\n",(unsigned long)checks,(unsigned long)failures);
        return failures?1:0;
    }
}
