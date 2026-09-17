// Offline regressions against the actual application methods and bundled data.
// No audio permission, API key, network request, or saved settings are required.
#define main PresenterApplicationMain
#import "../Sources/main.m"
#undef main

@interface TestText : NSObject
@property NSString *string;
@property NSString *stringValue;
@property NSColor *textColor;
@end
@implementation TestText
@end

@interface RecognitionTestApp : AppDelegate
@property NSString *resourceRoot;
@property NSMutableArray<NSString *> *submittedQuestions;
@property NSMutableArray<NSString *> *manualAIQuestions;
@property NSMutableArray<NSString *> *autoAIQuestions;
@property BOOL captureOnly;
@end

@implementation RecognitionTestApp
- (instancetype)init {
    if ((self=[super init])) {
        self.submittedQuestions=[NSMutableArray array];
        self.manualAIQuestions=[NSMutableArray array];
        self.autoAIQuestions=[NSMutableArray array];
        TestText *transcript=[TestText new]; transcript.string=@"";
        self.transcriptView=(NSTextView *)transcript;
        TestText *key=[TestText new]; key.stringValue=@"";
        self.keyField=(NSSecureTextField *)key;
        self.answerCache=[NSMutableDictionary dictionary];
    }
    return self;
}
- (NSString *)knowledgeResourcePath:(NSString *)name extension:(NSString *)extension {
    return [self.resourceRoot stringByAppendingPathComponent:[name stringByAppendingPathExtension:extension]];
}
- (void)setStatus:(NSString *)text color:(NSColor *)color {}
- (void)showCurrentQuestion:(NSString *)question answer:(NSString *)answer {}
- (void)showAutoQuestion:(NSString *)question answer:(NSString *)answer {}
- (void)appendHistoryQuestion:(NSString *)question answer:(NSString *)answer toTextView:(NSTextView *)view {}
- (void)askAIFallback:(NSString *)question { [self.manualAIQuestions addObject:question ?: @""]; }
- (void)askAutoAIFallback:(NSString *)question heard:(NSString *)heard { [self.autoAIQuestions addObject:heard ?: question ?: @""]; }
- (void)appendOfflineAnswerForQuestion:(NSString *)question {
    [self.submittedQuestions addObject:question ?: @""];
    if (!self.captureOnly) [super appendOfflineAnswerForQuestion:question];
}
@end

static NSUInteger assertions=0, failures=0;
static void Check(BOOL condition, NSString *message) {
    assertions++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Equal(NSString *actual, NSString *expected, NSString *message) {
    Check([actual isEqualToString:expected], [NSString stringWithFormat:@"%@\n  expected: %@\n  actual: %@",message,expected,actual]);
}
static void Has(NSString *actual, NSString *needle, NSString *message) {
    Check([actual rangeOfString:needle options:NSCaseInsensitiveSearch].location!=NSNotFound,
          [NSString stringWithFormat:@"%@ — expected '%@' in '%@'",message,needle,actual]);
}
static NSUInteger WordCount(NSString *text) {
    __block NSUInteger count=0;
    [text enumerateSubstringsInRange:NSMakeRange(0,text.length) options:NSStringEnumerationByWords usingBlock:^(NSString *substring,NSRange substringRange,NSRange enclosingRange,BOOL *stop) { count++; }];
    return count;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        RecognitionTestApp *app=[RecognitionTestApp new];
        app.resourceRoot=argc>1 ? [NSString stringWithUTF8String:argv[1]] :
          @"PresenterAI/dist/Presenter AI.app/Contents/Resources";
        [app loadBundledKnowledge];
        // Never use cached answers from another process or a previous release.
        app.answerCache=[NSMutableDictionary dictionary];
        Check(app.qaEntries.count>1000,@"Load the complete bundled Q&A dataset through the resource hook");
        Check(app.speechHints.count>0,@"Load bundled speech vocabulary");
        Check([app.speechHints containsObject:@"stock"],@"Bundled speech vocabulary includes the standalone culinary word stock");

        NSArray *canonicalTerms=@[@"julienne",@"à la carte",@"a la carte",@"mise en place",@"sous-vide",@"béchamel",@"velouté",@"consommé",@"béarnaise",@"demi-glace",@"mirepoix",@"bouquet garni",@"bain-marie",@"beurre blanc",@"beurre manié",@"hors d'oeuvre",@"amuse-bouche",@"crème brûlée",@"chiffonade",@"duxelles",@"en papillote",@"garde manger"];
        for (NSString *term in canonicalTerms) {
            NSString *once=[app correctCulinaryTerms:term];
            Equal([app correctCulinaryTerms:once],once,[NSString stringWithFormat:@"Culinary correction is idempotent: %@",term]);
        }
        Equal([app correctCulinaryTerms:@"julienne"],@"julienne",@"Correctly heard julienne is never corrupted");
        Has([app correctCulinaryTerms:@"What knife is best for julian cuts?"],@"julienne cuts",@"Correct a known julienne transcription variant");
        Has([app correctCulinaryTerms:@"What is missing place?"],@"mise en place",@"Correct a known mise en place transcription variant");
        Equal([app correctCulinaryTerms:@"What is Verseti?"],@"What is versatility?",@"Correct the observed versatility transcription error before retrieval");
        NSDictionary<NSString *,NSString *> *stockCorrections=@{
          @"What is stuff in cooking?":@"What is stock in cooking?",
          @"What are the four common types of stuff?":@"What are the four common types of stock?",
          @"How do you make chicken stuff?":@"How do you make chicken stock?",
          @"How long do you simmer fish stuff?":@"How long do you simmer fish stock?",
          @"Why is stuff rotation important?":@"Why is stock rotation important?",
          @"What are the main ingredients used in stuff production?":@"What are the main ingredients used in stock production?"
        };
        [stockCorrections enumerateKeysAndObjectsUsingBlock:^(NSString *heard,NSString *canonical,BOOL *stop) {
            NSString *corrected=[app correctCulinaryTerms:heard];
            Equal(corrected,canonical,[NSString stringWithFormat:@"Correct noun-shaped culinary stock transcription: %@",heard]);
            Equal([app correctCulinaryTerms:corrected],canonical,@"Stock correction remains idempotent");
        }];
        for(NSString *legitimateStuff in @[@"What do you stuff inside a chicken?",@"Can you stuff breadcrumbs inside chicken?",@"What kinds of bread would you stuff inside a turkey?",@"The chicken is stuffed with breadcrumbs.",@"How do you prepare stuffing for turkey?",@"I keep my personal stuff in a locker."])
            Equal([app correctCulinaryTerms:legitimateStuff],legitimateStuff,[NSString stringWithFormat:@"Preserve legitimate use of stuff: %@",legitimateStuff]);
        Equal([app correctCulinaryTerms:@"What is stock in cooking?"],@"What is stock in cooking?",@"Correctly heard stock is never changed");
        NSDictionary<NSString *,NSString *> *grillCorrections=@{
          @"How do you gorilla a steak?":@"How do you grill a steak?",
          @"How do you cook chicken on a gorilla?":@"How do you cook chicken on a grill?",
          @"How do you prepare guerrilla chicken?":@"How do you prepare grilled chicken?",
          @"Is the chicken gorilla or roasted?":@"Is the chicken grilled or roasted?"
        };
        [grillCorrections enumerateKeysAndObjectsUsingBlock:^(NSString *heard,NSString *canonical,BOOL *stop) {
            NSString *corrected=[app correctCulinaryTerms:heard];
            Equal(corrected,canonical,[NSString stringWithFormat:@"Correct culinary grill/gorilla transcription: %@",heard]);
            Equal([app correctCulinaryTerms:corrected],canonical,@"Grill correction remains idempotent");
        }];
        Equal([app correctCulinaryTerms:@"What does a gorilla eat in the wild?"],@"What does a gorilla eat in the wild?",@"Preserve a literal animal question containing gorilla");
        Equal([app correctCulinaryTerms:@"How do you grill chicken?"],@"How do you grill chicken?",@"Correctly heard grill is never changed");
        NSDictionary<NSString *,NSString *> *frenchCorrections=@{
          @"How do you make demi glass?":@"demi-glace",@"What is mirror paw?":@"mirepoix",@"Explain bouquet garney":@"bouquet garni",@"Use a ban marie":@"bain-marie",@"Serve with bear blank":@"beurre blanc",@"Prepare horse derv":@"hors d'oeuvre",@"Make cream brulee":@"crème brûlée",@"Cut a chiffon aid":@"chiffonade",@"What does a commie chef do?":@"commis chef",@"Cook it on pap ee oat":@"en papillote"
        };
        [frenchCorrections enumerateKeysAndObjectsUsingBlock:^(NSString *heard,NSString *canonical,BOOL *stop) {
            Has([app correctCulinaryTerms:heard],canonical,[NSString stringWithFormat:@"Correct French culinary speech variant: %@",heard]);
        }];
        NSArray *contextual=[app recognitionContextualStrings];
        Check(contextual.count<=100 && contextual.count>=80,@"Speech recognizer receives a legal, high-value set of contextual phrases");
        Check([contextual.firstObject isEqualToString:@"stock"] && [contextual indexOfObject:@"chicken stock"]<20 && [contextual indexOfObject:@"beef stock"]<20,@"Stock vocabulary is inside the recognizer's highest-priority context");
        NSArray<NSString *> *highestPriority=[contextual subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)15,contextual.count))];
        for(NSString *term in @[@"grill",@"grilled",@"grilling"])
            Check([highestPriority containsObject:term],[NSString stringWithFormat:@"%@ is inside the first 15 recognition hints",term]);
        for(NSString *term in @[@"mise en place",@"béarnaise",@"beurre manié",@"duxelles",@"en papillote",@"crème pâtissière"])
            Check([contextual containsObject:term],[NSString stringWithFormat:@"French term is prioritised for recognition: %@",term]);
        for(NSString *term in @[@"HACCP",@"cross-contamination",@"allergen",@"chef's knife",@"boning knife",@"cultural sensitivity"])
            Check([contextual containsObject:term],[NSString stringWithFormat:@"Balanced recognition vocabulary retains common assessment term: %@",term]);
        Equal([app preferredCulinaryAlternativeForPrimary:@"How do you cook chicken on a gorilla?"
                                             alternatives:@[@"How do you cook chicken on a gorilla?",@"How do you cook chicken on a grill?"]],
              @"How do you cook chicken on a grill?",@"Choose a grill alternative over the gorilla primary in culinary context");
        Equal([app preferredCulinaryAlternativeForPrimary:@"How do you grill chicken?"
                                             alternatives:@[@"How do you grill chicken?",@"How do you gorilla chicken?"]],
              @"How do you grill chicken?",@"Preserve an already-correct grill primary");
        Equal([app preferredCulinaryAlternativeForPrimary:@"What temperature should chicken reach?"
                                             alternatives:@[@"What temperature should chicken reach?",@"What temperature should turkey reach?"]],
              @"What temperature should chicken reach?",@"Unrelated recognition alternatives cannot rewrite the primary");
        NSMutableArray<NSString *> *vocabulary=[app.speechHints mutableCopy] ?: [NSMutableArray array];
        for (NSDictionary *entry in app.qaEntries) [vocabulary addObject:entry[@"question"] ?: @""];
        for (NSString *text in vocabulary) {
            NSString *once=[app correctCulinaryTerms:text];
            Equal([app correctCulinaryTerms:once],once,[NSString stringWithFormat:@"Repeated correction must preserve vocabulary: %@",text]);
            NSString *normal=[app normalisedQuestion:text];
            Equal([app normalisedQuestion:normal],normal,[NSString stringWithFormat:@"Normalization is idempotent: %@",text]);
        }

        NSArray<NSString *> *singleQuestions=@[
          @"List three ways people may define their cultural identity",
          @"Describe how you prepare a workstation before service",
          @"Explain how to store raw poultry safely",
          @"Tell me what you do before service",
          @"In what ways can problems or misunderstandings with customers or colleagues from different cultural backgrounds be avoided",
          @"Which knife is the most versatile for slicing, chopping and dicing",
          @"What is the difference between cleaning and sanitising",
          @"Give one example of preparing Mise en Place for a poultry seafood or sandwich dish"
        ];
        app.captureOnly=YES;
        for (NSString *question in singleQuestions) {
            Check([app looksLikeQuestion:question],[NSString stringWithFormat:@"Detect unpunctuated question: %@",question]);
            Equal([app primaryQuestionFromText:question],question,[NSString stringWithFormat:@"Retain embedded question words: %@",question]);
            [app.submittedQuestions removeAllObjects]; app.lastAsked=nil;
            [app processQuestionText:question];
            Check(app.submittedQuestions.count==1,[NSString stringWithFormat:@"Dispatch one complete question: %@ (got %@)",question,app.submittedQuestions]);
            if(app.submittedQuestions.count==1) Equal(app.submittedQuestions.firstObject,question,@"SPACE dispatch retains every word");
        }
        for(NSString *natural in @[@"All right, what is the difference between cleaning and sanitising?",@"I'd like to know how you prevent cross-contamination",@"Let me ask, which knife is the most versatile?"])
            Check([app looksLikeQuestion:natural],[NSString stringWithFormat:@"Natural interviewer lead-in is recognised: %@",natural]);
        Equal([app questionTurnFromTranscript:@"All right, what is the difference between cleaning and sanitising?"],@"what is the difference between cleaning and sanitising?",@"Enhanced transcription removes a natural lead-in and retains the exact question");
        Equal([app questionTurnFromTranscript:@"I'd like to know how you prevent cross-contamination"],@"how you prevent cross-contamination",@"Enhanced transcription accepts an unpunctuated natural lead-in");
        app.keyField.stringValue=@"sk-test-not-sent";
        NSMutableURLRequest *transcriptionRequest=[app autoTranscriptionRequestForWAV:[@"RIFF-test-WAVE" dataUsingEncoding:NSUTF8StringEncoding]];
        NSString *multipart=[[NSString alloc] initWithData:transcriptionRequest.HTTPBody encoding:NSUTF8StringEncoding];
        Equal(transcriptionRequest.URL.absoluteString,@"https://api.openai.com/v1/audio/transcriptions",@"Enhanced AUTO uses the supported audio transcription endpoint");
        Has(multipart,@"name=\"model\"\r\n\r\ngpt-transcribe",@"Enhanced AUTO prefers gpt-transcribe");
        Has(multipart,@"name=\"keywords[]\"",@"Enhanced AUTO sends culinary keyword hints");
        Has(multipart,@"filename=\"question.wav\"",@"Enhanced AUTO sends a named WAV file");
        app.keyField.stringValue=@"";
        NSString *two=@"Which knife is the most versatile for slicing, chopping and dicing? What knife is best for cutting julienne or vegetables?";
        Equal([app primaryQuestionFromText:two],two,@"AUTO retains both questions from one utterance");
        [app.submittedQuestions removeAllObjects]; app.lastAsked=nil;
        [app processQuestionText:two];
        NSString *all=[app.submittedQuestions componentsJoinedByString:@" "];
        Has(all,@"Which knife is the most versatile",@"SPACE retains the first knife question");
        Has(all,@"What knife is best",@"SPACE retains the second knife question");

        NSString *heard=@"What knife is best for cutting julienne or vegetables?";
        app.lastMatchedQuestion=@"How do you cook a steak to medium rare?"; app.lastMatchConfidence=0.55;
        Equal([app displayQuestionForHeardQuestion:heard],heard,@"A weak database candidate cannot rewrite the heard question");
        app.lastMatchConfidence=1;
        Equal([app displayQuestionForHeardQuestion:heard],heard,@"The question panel preserves the heard question even after matching");
        Equal([app displayQuestionForHeardQuestion:@"What is bare hand contact in food safety?"],@"What is bare hand contact in food safety?",@"Food safety keywords cannot replace a specific question with a generic one");
        Equal([app displayQuestionForHeardQuestion:@"Okay? So what do you have in that? What are the ingredients? Do you have?"],@"What are the ingredients?",@"Display removes filler and incomplete repeated fragments while retaining the precise question");
        Equal([app displayQuestionForHeardQuestion:two],two,@"Display keeps two distinct complete questions from the same turn");

        app.captureOnly=NO;
        NSString *combinedAuto=@"Which knife is the most versatile for slicing, chopping and dicing?\nWhat knife is best for cutting julienne or vegetables?";
        NSUInteger autoFallbacksBefore=app.autoAIQuestions.count;
        [app autoRecogniseQuestionText:combinedAuto fast:NO];
        Equal(app.autoQuestion,combinedAuto,@"AUTO displays both questions from one speaking turn in order");
        Check(app.autoAIQuestions.count==autoFallbacksBefore+1,@"Multipart AUTO turn uses one AI synthesis instead of two local answers");
        Equal(app.autoAIQuestions.lastObject,combinedAuto,@"Multipart synthesis receives both exact heard questions");
        NSArray *combinedParts=[app questionPartsForSynthesis:combinedAuto];
        Check(combinedParts.count==2,@"Multipart synthesis preserves two explicit parts");
        NSString *combinedContext=[app aiContextForAllQuestionParts:combinedAuto];
        Has(combinedContext,@"part_1_reference",@"Multipart synthesis builds a separate reference section for question one");
        Has(combinedContext,@"part_2_reference",@"Multipart synthesis builds a separate reference section for question two");
        Check([app questionNeedsConversationContext:@"What are the ingredients?"],@"A vague ingredients question requests recent conversational context");
        Check([app questionNeedsConversationContext:@"Okay? So what do you have in that? What are the ingredients? Do you have?"],@"Pronoun-linked multipart follow-up requests conversational context");
        Check([app questionNeedsConversationContext:@"And why?"],@"A short why follow-up inherits the preceding topic");
        Check([app questionNeedsConversationContext:@"Can you explain more?"],@"A request for more detail inherits the preceding topic");
        Check(![app questionNeedsConversationContext:@"What ingredients are used in a mirepoix?"],@"A self-contained ingredients question does not inherit an unrelated topic");
        Check(![app questionNeedsConversationContext:@"What do you have in your menu?"],@"An explicit menu subject does not inherit an unrelated topic");
        app.autoRecords=[@[
          [@{@"question":@"Tell me about a Spanish tortilla.",@"answer":@"A Spanish tortilla is made from eggs and potatoes.",@"state":@"complete",@"lane":@"auto"} mutableCopy],
          [@{@"question":@"What are the ingredients?",@"answer":@"Eggs, potatoes, onion and oil.",@"state":@"complete",@"lane":@"auto"} mutableCopy]
        ] mutableCopy];
        NSString *linkedFollowUp=@"Okay? So what do you have in that? What are the ingredients? Do you have?";
        [app autoRecogniseQuestionText:linkedFollowUp fast:NO];
        NSDictionary *linkedRecord=app.autoRecords.lastObject;
        Equal(linkedRecord[@"question"],@"What are the ingredients?",@"AUTO displays a concise precise form of the newly heard follow-up");
        Check([linkedRecord[@"usedContext"] boolValue],@"AUTO marks a referential follow-up as context-aware");
        Has(linkedRecord[@"requestQuestion"],@"Spanish tortilla",@"Context request looks beyond an immediately previous vague question to the explicit topic");
        Has(linkedRecord[@"requestQuestion"],@"Eggs, potatoes, onion and oil",@"Context request includes the previous answer to resolve what 'that' refers to");
        Equal([app heardQuestionFromRequest:linkedRecord[@"requestQuestion"]],linkedFollowUp,@"Context envelope preserves the exact current question");
        Has([app recentQuestionsFromRequest:linkedRecord[@"requestQuestion"]],@"What are the ingredients?",@"Context envelope includes the immediately previous question");
        ((TestText *)app.keyField).stringValue=@"sk-test-context-key-1234567890";
        app.manualRecords=[@[[@{@"question":@"How do you prevent cross-contamination?",@"answer":@"I separate raw and ready-to-eat food and sanitise food-contact surfaces.",@"state":@"complete",@"lane":@"manual"} mutableCopy]] mutableCopy];
        [app appendOfflineAnswerForQuestion:@"And why?"];
        NSDictionary *manualFollowUp=app.manualRecords.lastObject;
        Check([manualFollowUp[@"usedContext"] boolValue],@"SPACE follow-up uses its own conversation memory");
        Has(manualFollowUp[@"requestQuestion"],@"cross-contamination",@"SPACE context contains the preceding SPACE question");
        Has(manualFollowUp[@"requestQuestion"],@"separate raw",@"SPACE context contains the preceding answer");
        Check([manualFollowUp[@"requestQuestion"] rangeOfString:@"Spanish tortilla"].location==NSNotFound,@"SPACE context never leaks AUTO conversation history");
        NSUInteger manualAIBefore=app.manualAIQuestions.count;
        [app appendOfflineAnswerForQuestion:@"What is mise en place?"];
        Check(app.manualAIQuestions.count==manualAIBefore,@"A clear known technical question still uses the fast local path despite conversation history");
        NSArray<NSDictionary *> *answerCases=@[
          @{@"q":@"What skills do you think are important for a prep cook?",@"has":@"knife",@"not":@"medium rare"},
          @{@"q":@"How do you ensure food safety in the kitchen?",@"has":@"hygiene"},
          @{@"q":@"List three ways people may define their cultural identity.",@"has":@"language"},
          @{@"q":@"In what ways can problems or misunderstandings with customers or colleagues from different cultural backgrounds be avoided?",@"has":@"cultural"},
          @{@"q":@"What is the difference between cleaning and sanitising?",@"has":@"bacteria"},
          @{@"q":@"What is mise en place?",@"has":@"place"},
          @{@"q":@"What is missing place?",@"has":@"place"},
          @{@"q":@"Give one example of preparing 'Mise en Place' for a poultry/seafood/sandwich dish.",@"has":@"chicken"},
          @{@"q":@"Which knife is the most versatile for slicing, chopping and dicing?",@"has":@"chef"},
          @{@"q":@"What knife is best for cutting julienne or vegetables?",@"has":@"chef"},
          @{@"q":@"What is bare hand contact in food safety?",@"has":@"ready-to-eat"}
        ];
        for (NSDictionary *test in answerCases) {
            NSString *question=test[@"q"], *answer=[app bestLocalAnswerForQuestion:question];
            Has(answer,test[@"has"],[NSString stringWithFormat:@"Relevant bundled answer: %@",question]);
            Check(![answer containsString:@"No reliable match"],[NSString stringWithFormat:@"Known question resolves offline: %@",question]);
            if(test[@"not"]) Check([answer rangeOfString:test[@"not"] options:NSCaseInsensitiveSearch].location==NSNotFound,@"Prep-cook answer must not be about steak temperature");
            Equal([app displayQuestionForHeardQuestion:question],[app correctCulinaryTerms:question],@"Matching preserves the committed question apart from known culinary spelling corrections");
        }
        NSString *misheardStock=@"What is stuff in cooking?";
        NSString *stockAnswer=[app bestLocalAnswerForQuestion:misheardStock];
        Check(![stockAnswer containsString:@"No reliable match"] && ([stockAnswer rangeOfString:@"liquid" options:NSCaseInsensitiveSearch].location!=NSNotFound || [stockAnswer rangeOfString:@"flavour" options:NSCaseInsensitiveSearch].location!=NSNotFound),@"Corrected stock question retrieves a relevant bundled answer");
        Equal([app displayQuestionForHeardQuestion:misheardStock],@"What is stock in cooking?",@"Question panel shows stock rather than the recognizer's stuff error");
        NSString *prepQuestion=@"What skills do you think are important for a prep cook?";
        NSString *shortPrep=[app conciseLocalAnswerFromResult:[app bestLocalAnswerForQuestion:prepQuestion] question:prepQuestion];
        Check(WordCount(shortPrep)<=45 && [shortPrep containsString:@"knife"] && [shortPrep containsString:@"food-safety"],@"Common local interview answer retains useful detail within the B2 limit");
        NSString *definitionQuestion=@"What is mise en place?";
        NSString *shortDefinition=[app conciseLocalAnswerFromResult:[app bestLocalAnswerForQuestion:definitionQuestion] question:definitionQuestion];
        Check(WordCount(shortDefinition)<=45 && [shortDefinition rangeOfString:@"place" options:NSCaseInsensitiveSearch].location!=NSNotFound,@"A local definition stays focused while retaining useful B2 detail");
        NSString *safeProcedure=@"TRẢ LỜI EN: First cool the food from 60°C to 21°C within two hours. Then cool it to 5°C within another four hours. Record the temperature.";
        NSString *safeProcedureDisplay=[app conciseLocalAnswerFromResult:safeProcedure question:@"How do you cool cooked food safely?"];
        Has(safeProcedureDisplay,@"Short:",@"Dual-answer display labels the immediate answer");
        Has(safeProcedureDisplay,[app answerTextFromLocalResult:safeProcedure],@"Dual-answer display never cuts required ordered food-safety steps");
        NSString *multiPart=@"TRẢ LỜI EN: Cleaning removes soil. Sanitising reduces microorganisms. Both steps are required.";
        NSString *multiPartDisplay=[app conciseLocalAnswerFromResult:multiPart question:@"What is cleaning? What is sanitising?"];
        Has(multiPartDisplay,@"Short:",@"Dual-answer display labels multi-question local answers");
        Has(multiPartDisplay,[app answerTextFromLocalResult:multiPart],@"Dual-answer display never drops a part of a multi-question local answer");

        CFAbsoluteTime lookupTotal=0, lookupMax=0;
        for(NSString *shortQuestion in @[@"What is FIFO?",@"What is HACCP?",@"Define julienne",@"What is béchamel?"]) {
            app.lastAutoAsked=nil;
            [app autoRecogniseQuestionText:shortQuestion fast:NO];
            Equal(app.autoQuestion,[app displayQuestionForHeardQuestion:shortQuestion],@"AUTO accepts and concisely displays short definitions with one meaningful term");
        }
        NSString *mismatch=[app bestLocalAnswerForQuestion:@"What is the difference between cleaning and sharpening?"];
        Has(mismatch,@"No reliable match",@"A different subject must not inherit the cleaning/sanitising answer");
        for (NSDictionary *test in answerCases) {
            CFAbsoluteTime began=CFAbsoluteTimeGetCurrent();
            [app bestLocalAnswerForQuestion:test[@"q"]];
            CFAbsoluteTime elapsed=CFAbsoluteTimeGetCurrent()-began;
            lookupTotal+=elapsed; lookupMax=MAX(lookupMax,elapsed);
        }
        fprintf(stdout,"Bundled lookup timing (%lu questions): mean %.2f ms; max %.2f ms\n",
                (unsigned long)answerCases.count,lookupTotal*1000/answerCases.count,lookupMax*1000);

        // These are intentionally outside the cooking dataset. If AI is needed,
        // the request must retain the real question rather than a fuzzy match.
        NSString *unknown=@"How do you maintain the cooling system in an electric vehicle?";
        [app appendOfflineAnswerForQuestion:unknown];
        Equal(app.currentQuestion,unknown,@"SPACE fallback keeps the real question");
        if(app.manualAIQuestions.count) Equal(app.manualAIQuestions.lastObject,unknown,@"Manual AI receives the heard question");
        app.lastAutoAsked=nil;
        [app autoRecogniseQuestionText:unknown fast:NO];
        Equal(app.autoQuestion,unknown,@"AUTO fallback keeps the real question");
        if(app.autoAIQuestions.count) Equal(app.autoAIQuestions.lastObject,unknown,@"AUTO AI receives the heard question");

        [app.silenceTimer invalidate]; [app.autoTimer invalidate];
        fprintf(stdout,"%lu assertions; %lu failures; %lu bundled questions; %lu speech hints\n",
                (unsigned long)assertions,(unsigned long)failures,
                (unsigned long)app.qaEntries.count,(unsigned long)app.speechHints.count);
        return failures ? 1 : 0;
    }
}
