// Exercise the production answer coordinator with deterministic fake requests.
// This executable never loads a real API key or contacts an external service.
#define main PresenterApplicationMain
#import "../Sources/main.m"
#undef main

@interface QueueTestField : NSObject
@property NSString *stringValue;
@end
@implementation QueueTestField
@end

@interface AnswerQueueTestApp : AppDelegate
@property NSMutableArray<NSString *> *sentQuestions;
@property NSMutableDictionary<NSString *,NSMutableArray *> *completions;
@property NSString *shownManualQuestion;
@property NSString *shownManualAnswer;
@property NSString *shownAutoQuestion;
@property NSString *shownAutoAnswer;
@property NSUInteger cachePersistenceCalls;
@property NSUInteger manualPaints;
@property NSUInteger autoPaints;
- (void)finishQuestion:(NSString *)question answer:(NSString *)answer success:(BOOL)success;
@end

@implementation AnswerQueueTestApp
- (instancetype)init {
    if ((self=[super init])) {
        self.sentQuestions=[NSMutableArray array]; self.completions=[NSMutableDictionary dictionary];
        QueueTestField *key=[QueueTestField new]; key.stringValue=@"sk-test-placeholder-not-a-real-key";
        self.keyField=(NSSecureTextField *)key;
        [self ensureAnswerState];
        self.manualAnswerLane.cache=[NSMutableDictionary dictionary];
        self.autoAnswerLane.cache=[NSMutableDictionary dictionary];
    }
    return self;
}
- (void)performAnswerRequest:(NSString *)question completion:(void (^)(NSString *,BOOL))completion {
    [self.sentQuestions addObject:question];
    if(!self.completions[question]) self.completions[question]=[NSMutableArray array];
    [self.completions[question] addObject:[completion copy]];
}
- (void)finishQuestion:(NSString *)question answer:(NSString *)answer success:(BOOL)success {
    NSMutableArray *pending=self.completions[question];
    void (^completion)(NSString *,BOOL)=pending.firstObject;
    if(pending.count) [pending removeObjectAtIndex:0];
    if(!pending.count) [self.completions removeObjectForKey:question];
    if (completion) completion(answer,success);
}
- (NSString *)bestLocalAnswerForQuestion:(NSString *)question {
    self.lastMatchedQuestion=nil; self.lastMatchConfidence=0;
    return @"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data.";
}
- (void)persistAnswerCache { self.cachePersistenceCalls++; }
- (void)setStatus:(NSString *)text color:(NSColor *)color {}
- (void)refreshAnswerPanels {
    [self refreshManualAnswerPanel]; [self refreshAutoAnswerPanel];
}
- (void)refreshManualAnswerPanel {
    self.manualPaints++;
    NSDictionary *manual=self.manualRecords.lastObject;
    self.shownManualQuestion=manual[@"question"]; self.shownManualAnswer=manual[@"answer"];
}
- (void)refreshAutoAnswerPanel {
    self.autoPaints++;
    NSDictionary *automatic=self.autoRecords.lastObject;
    self.shownAutoQuestion=automatic[@"question"]; self.shownAutoAnswer=automatic[@"answer"];
}
@end

static NSUInteger assertions=0,failures=0;
static void Check(BOOL condition,NSString *message) {
    assertions++;
    if(!condition) { failures++; fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}
static void Equal(id actual,id expected,NSString *message) {
    Check([actual isEqual:expected],[NSString stringWithFormat:@"%@ — expected %@; got %@",message,expected,actual]);
}
static NSMutableDictionary *Submit(AnswerQueueTestApp *app,NSString *question,NSString *lane) {
    NSMutableDictionary *record=[@{@"question":question,@"answer":@"Preparing…",@"state":@"queued",@"lane":lane} mutableCopy];
    if([lane isEqualToString:@"auto"]) [app.autoRecords addObject:record];
    else [app.manualRecords addObject:record];
    [app startAnswerForRecord:record];
    if([lane isEqualToString:@"auto"]) [app refreshAutoAnswerPanel];
    else [app refreshManualAnswerPanel];
    return record;
}
static NSData *JSON(id value) { return [NSJSONSerialization dataWithJSONObject:value options:0 error:nil]; }
static NSDictionary *TextBlock(NSString *text) { return @{@"type":@"output_text",@"text":text}; }
static NSDictionary *Message(NSArray *parts) { return @{@"type":@"message",@"status":@"completed",@"content":parts}; }
static NSUInteger WordCount(NSString *text) {
    NSUInteger count=0;
    for(NSString *word in [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if(word.length) count++;
    return count;
}
static NSUInteger NumberedItemCount(NSString *text) {
    NSRegularExpression *number=[NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)\\d+[.)](?=\\s)" options:0 error:nil];
    return [number numberOfMatchesInString:text options:0 range:NSMakeRange(0,text.length)];
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        AnswerQueueTestApp *app=[AnswerQueueTestApp new];
        NSString *q1=@"How do you prepare the first station?", *q2=@"How do you prepare the second station?", *q3=@"How do you prepare the third station?", *q4=@"How do you prepare the fourth station?";
        NSMutableDictionary *r1=Submit(app,q1,@"manual"), *r2=Submit(app,q2,@"manual"), *r3=Submit(app,q3,@"manual");
        Equal(@(app.sentQuestions.count),@2,@"Two SPACE requests start concurrently");
        Equal(@(app.manualAnswerLane.activeCount),@2,@"SPACE tracks its own active requests");
        Equal(@(app.manualAnswerLane.pendingCount),@1,@"SPACE third question waits without being dropped");
        NSMutableDictionary *r4=Submit(app,q4,@"auto");
        Equal(@(app.sentQuestions.count),@3,@"AUTO starts immediately despite saturated SPACE queue");
        Equal(@(app.autoAnswerLane.activeCount),@1,@"AUTO has its own request slot");
        Check(![app.sentQuestions containsObject:q3],@"AUTO does not dispatch the pending SPACE question");
        NSUInteger autoPaintsBeforeManual=app.autoPaints;
        [app finishQuestion:q1 answer:@"Answer one" success:YES];
        Equal(@(app.sentQuestions.count),@4,@"SPACE completion starts the retained SPACE question");
        Equal(@(app.autoPaints),@(autoPaintsBeforeManual),@"SPACE completion never refreshes AUTO panel");
        Equal(app.sentQuestions.lastObject,q3,@"FIFO queue dispatches the third question");
        Equal(r1[@"answer"],@"Answer one",@"First response attaches to its original record");
        Equal(app.shownManualQuestion,q3,@"An older response cannot replace the newest manual question");
        Check(![app.shownManualAnswer isEqualToString:@"Answer one"],@"An older response cannot overwrite the newest manual answer");
        [app finishQuestion:q3 answer:@"Answer three" success:YES];
        NSUInteger manualPaintsBeforeAuto=app.manualPaints;
        [app finishQuestion:q4 answer:@"Answer four" success:YES];
        Equal(@(app.manualPaints),@(manualPaintsBeforeAuto),@"AUTO completion never refreshes SPACE panel");
        [app finishQuestion:q2 answer:@"Answer two" success:YES];
        Equal(r2[@"answer"],@"Answer two",@"Older SPACE row gets its own answer despite out-of-order completion");
        Equal(r3[@"answer"],@"Answer three",@"SPACE gets its own answer despite out-of-order completion");
        Equal(r4[@"answer"],@"Answer four",@"AUTO gets its own answer despite out-of-order completion");
        Equal(app.shownManualAnswer,@"Answer three",@"Latest SPACE panel remains correct");
        Equal(app.shownAutoAnswer,@"Answer four",@"Latest AUTO panel remains correct");
        Equal(@(app.manualAnswerLane.activeCount),@0,@"All SPACE request slots released");
        Equal(@(app.autoAnswerLane.activeCount),@0,@"All AUTO request slots released");
        Equal(@(app.manualAnswerLane.pendingCount),@0,@"Completed SPACE queue is empty");
        Equal(@(app.autoAnswerLane.pendingCount),@0,@"Completed AUTO queue is empty");

        AnswerQueueTestApp *contextual=[AnswerQueueTestApp new];
        NSString *visibleFollowUp=@"What are the ingredients?";
        NSString *requestWithContext=[contextual contextualRequestForQuestion:visibleFollowUp recentQuestions:@"Tell me about a Spanish tortilla."];
        NSMutableDictionary *contextualRecord=[@{@"question":visibleFollowUp,@"requestQuestion":requestWithContext,@"answer":@"Preparing…",@"state":@"waiting",@"lane":@"auto"} mutableCopy];
        [contextual.autoRecords addObject:contextualRecord];
        [contextual startAnswerForRecord:contextualRecord];
        Equal(contextual.sentQuestions.lastObject,requestWithContext,@"Answer lane sends conversational context to synthesis");
        Equal(contextualRecord[@"question"],visibleFollowUp,@"Answer lane keeps the displayed follow-up free of hidden context");
        [contextual finishQuestion:requestWithContext answer:@"Eggs, potatoes, onion and oil." success:YES];
        Equal(contextualRecord[@"answer"],@"Eggs, potatoes, onion and oil.",@"Contextual result attaches to the visible follow-up record");

        AnswerQueueTestApp *shared=[AnswerQueueTestApp new];
        NSString *question=@"What is mise en place?", *variant=@"what is mise en place";
        NSMutableDictionary *automatic=Submit(shared,question,@"auto"), *manual=Submit(shared,variant,@"manual");
        Equal(@(shared.sentQuestions.count),@2,@"AUTO and SPACE independently request the same normalized question");
        [shared finishQuestion:question answer:@"AUTO: Everything prepared before cooking." success:YES];
        Equal(manual[@"answer"],@"Preparing…",@"AUTO result leaves SPACE record pending");
        Equal(@(shared.manualAnswerLane.cache.count),@0,@"AUTO result does not seed SPACE cache");
        [shared finishQuestion:variant answer:@"SPACE: Prepare ingredients and equipment." success:YES];
        Equal(automatic[@"answer"],@"AUTO: Everything prepared before cooking.",@"AUTO retains its independent answer");
        Equal(manual[@"answer"],@"SPACE: Prepare ingredients and equipment.",@"SPACE receives its independent answer");
        Equal(automatic[@"question"],question,@"AUTO retains its own heard wording");
        Equal(manual[@"question"],variant,@"SPACE retains its own heard wording");
        NSMutableDictionary *cached=Submit(shared,@"What is mise en place",@"manual");
        Equal(@(shared.sentQuestions.count),@2,@"SPACE repeat uses its cached success without another request");
        Equal(cached[@"answer"],@"SPACE: Prepare ingredients and equipment.",@"SPACE cache attaches only the SPACE answer");
        NSMutableDictionary *autoCached=Submit(shared,@"What is mise en place",@"auto");
        Equal(autoCached[@"answer"],@"AUTO: Everything prepared before cooking.",@"AUTO cache attaches only the AUTO answer");

        AnswerQueueTestApp *identical=[AnswerQueueTestApp new];
        NSMutableDictionary *exactManual=Submit(identical,question,@"manual"), *exactAuto=Submit(identical,question,@"auto");
        Equal(@(identical.sentQuestions.count),@2,@"Even exactly identical text issues a separate request in each lane");
        [identical finishQuestion:question answer:@"Manual exact answer" success:YES];
        Equal(exactAuto[@"answer"],@"Preparing…",@"Exact-text AUTO request remains independently pending");
        [identical finishQuestion:question answer:@"Auto exact answer" success:YES];
        Equal(exactManual[@"answer"],@"Manual exact answer",@"Manual exact-text result stays attached to manual row");
        Equal(exactAuto[@"answer"],@"Auto exact answer",@"Auto exact-text result stays attached to auto row");

        AnswerQueueTestApp *failure=[AnswerQueueTestApp new];
        NSMutableDictionary *failed=Submit(failure,q1,@"auto");
        [failure finishQuestion:q1 answer:@"OpenAI API error: timeout" success:NO];
        Equal(@(failure.autoAnswerLane.cache.count),@0,@"Failed responses are never cached as answers");
        Equal(@(failure.cachePersistenceCalls),@0,@"Failures do not persist cache");
        Equal(@(failure.autoAnswerLane.activeCount),@0,@"A failed request releases its AUTO slot");
        Equal(failed[@"state"],@"failed",@"Failed question does not remain permanently waiting");
        Submit(failure,q1,@"auto");
        Equal(@(failure.sentQuestions.count),@2,@"The same question can retry after a failure");
        [failure finishQuestion:q1 answer:@"Recovered answer" success:YES];
        Equal(failure.autoAnswerLane.cache[[failure normalisedQuestion:q1]],@"Recovered answer",@"Successful retry enters only AUTO cache");
        Check(failure.manualAnswerLane.cache[[failure normalisedQuestion:q1]]==nil,@"AUTO retry success leaves SPACE cache untouched");

        AnswerQueueTestApp *parser=[AnswerQueueTestApp new];
        NSDictionary *valid=@{@"status":@"completed",@"output":@[
            @{@"type":@"reasoning",@"summary":@[]},
            Message(@[TextBlock(@"Clean first."),TextBlock(@"Then sanitise.")]),
            Message(@[TextBlock(@"Allow contact time.")])
        ]};
        NSDictionary *parsed=[parser parsedAnswerData:JSON(valid) status:200 error:nil];
        Check([parsed[@"success"] boolValue],@"HTTP 200 completed output is accepted");
        for(NSString *part in @[@"Clean first.",@"Then sanitise.",@"Allow contact time."])
            Check([parsed[@"answer"] containsString:part],@"Parser joins all output text blocks rather than truncating after the first");
        NSDictionary *webOutput=@{@"status":@"completed",@"output":@[
            @{@"type":@"web_search_call",@"status":@"completed"},
            Message(@[@{@"type":@"output_text",@"text":@"Versatility means being able to adapt to different tasks.",@"annotations":@[@{@"type":@"url_citation",@"url":@"https://example.com/versatility",@"title":@"Versatility reference"}]}])
        ]};
        NSDictionary *parsedWeb=[parser parsedAnswerData:JSON(webOutput) status:200 error:nil];
        Check([parsedWeb[@"success"] boolValue],@"A response containing a web-search call and a message is accepted");
        Check(![parsedWeb[@"answer"] containsString:@"https://example.com/versatility"],@"Web-derived answers omit source URLs from the presenter's spoken answer");
        NSAttributedString *linked=[parser linkedText:parsedWeb[@"answer"] attributes:@{}];
        __block BOOL hasLink=NO;
        [linked enumerateAttribute:NSLinkAttributeName inRange:NSMakeRange(0,linked.length) options:0 usingBlock:^(id value,NSRange range,BOOL *stop){
            (void)range;
            if(value){ hasLink=YES; *stop=YES; }
        }];
        Check(!hasLink,@"Displayed spoken answer contains no source-link annotation");
        NSString *fallbackPolicy=@"Use clear, natural CEFR B2 English with varied vocabulary and useful detail. Keep the answer easy to say aloud and focused on the exact question. Keep necessary cooking, food-safety, workplace, legal, and French culinary terms; explain uncommon technical words briefly when helpful. Use I, my, we, or our for actions, choices, experience, and opinions; state factual definitions directly. Provide two versions when the app asks for them: Short is normally under 28 words, and Full is normally under 85 words with the useful details. Do not invent past experience; when no real example is supplied, say what I would do.";
        Equal([parser effectiveAnswerPolicy],fallbackPolicy,@"The macOS fallback exactly matches the shared B2 policy");
        NSDictionary *webBody=[parser answerRequestBodyForQuestion:@"What is versatility?" includeWebSearch:YES];
        Equal(webBody[@"tools"],@[@{@"type":@"web_search",@"search_context_size":@"low"}],@"Fallback request enables the current Responses API web-search tool with low-latency context");
        Equal(webBody[@"tool_choice"],@"auto",@"The model decides whether a web search is needed");
        Check([webBody[@"instructions"] containsString:@"general culinary"],@"Fallback can answer from general knowledge when local study data is absent");
        Check([webBody[@"instructions"] containsString:@"words the presenter can say aloud"],@"AI output is written as the presenter's ready-to-speak answer");
        Check([webBody[@"instructions"] containsString:@"Short must be one direct answer"],@"Single-question AI answers include an immediate answer");
        Check([webBody[@"instructions"] containsString:@"Full must be a fuller answer"],@"Single-question AI answers include a fuller version with detail");
        Check([webBody[@"instructions"] containsString:@"situation, task, action, and result"],@"Behavioral answers are shaped into a concise STAR response");
        Check([webBody[@"instructions"] containsString:@"tradeoff only when the question asks"],@"Technical answers avoid unrequested tradeoff padding");
        Check([webBody[@"instructions"] containsString:@"infer the competency or signal"],@"Vague questions target the interview signal being evaluated");
        Check([webBody[@"instructions"] containsString:@"one short clarifying question"],@"A stuck answer can recover with one concise clarification");
        Check([webBody[@"instructions"] containsString:@"role, team, success criteria, product, or company"],@"The assistant can propose thoughtful questions for the interviewer");
        Check([webBody[@"instructions"] containsString:@"clear, natural CEFR B2 English"],@"Both answer lanes receive the B2 fallback when a resource is not loaded in a unit test");
        Check([webBody[@"instructions"] containsString:@"varied vocabulary and useful detail"],@"The fallback asks for richer but focused B2 answers");
        parser.answerPolicy=@"SHARED POLICY TEST: use clear B2 English.";
        NSDictionary *sharedPolicyBody=[parser answerRequestBodyForQuestion:@"What is cleaning?" includeWebSearch:NO];
        Check([sharedPolicyBody[@"instructions"] containsString:parser.answerPolicy],@"The bundled shared policy is appended to the common AUTO and SPACE AI request builder");
        NSString *simple=[parser presenterReadyB1Answer:@"I subsequently utilise approximately two additional containers prior to service."];
        Equal(simple,@"I then use approximately two additional containers before service.",@"The no-latency pass keeps useful B2 vocabulary while removing overly formal wording");
        NSString *technical=[parser presenterReadyB1Answer:@"I prepare mise en place, cut julienne vegetables, and cook medium rare beef to 55-57°C; I never guess the temperature."];
        Check([technical containsString:@"mise en place"] && [technical containsString:@"julienne"] && [technical containsString:@"55-57°C"] && [technical containsString:@"never"],@"B2 processing preserves French culinary terms, temperatures, and negation");
        NSString *longAnswer=[parser presenterReadyB1Answer:@"I check every item carefully before service and keep the station clean, safe, ready, calm, neat, well stocked, clearly labelled, and easy for my team to use during a busy shift without delay at 75°C."];
        Check(WordCount(longAnswer)<=45,@"A single presenter answer is capped at 45 words");
        Check([longAnswer containsString:@"without"] && [longAnswer containsString:@"75°C"],@"The word cap keeps late negation and temperature facts");
        Check(![longAnswer containsString:@"during without"],@"The word cap removes whole phrases instead of splicing non-adjacent word fragments");
        NSString *multipart=[parser presenterReadyB1Answer:@"1. I subsequently utilise clean tongs. 2. I never serve chicken below 75°C."];
        Equal(multipart,@"1. I then use clean tongs.\n2. I never serve chicken below 75°C.",@"Numbered multipart answers keep numbering, order, negation, and temperature");
        NSString *fish=[parser presenterReadyB1Answer:@"Eyes: clear, bright, slightly protruding (cloudy/sunken = not fresh). Gills: bright red or pink and moist (brown/grey = deteriorating). Flesh: firm, springs back when pressed; skin with natural sheen and tight scales. Smell: mild, clean ocean scent. Temperature: 0–4°C on arrival." forQuestion:@"Give three indicators for quality fresh whole fish when it arrives at the kitchen from the seafood supplier."];
        Equal(@(NumberedItemCount(fish)),@3,@"A requested three-item fish answer returns exactly three indicators");
        Check(WordCount(fish)<=45 && [fish containsString:@"Firm flesh that springs back"],@"Fresh-fish indicators stay concise and form complete phrases");
        Check(![fish containsString:@"skin with natural Temperature"],@"Fresh-fish output never joins unrelated non-adjacent fragments");
        NSString *fishFive=[parser presenterReadyB1Answer:@"Eyes: clear and bright. Gills: bright red or pink. Flesh: firm and springs back. Smell: mild and clean. Temperature: 0–4°C on arrival." forQuestion:@"Briefly describe five quality indicators for fresh whole fish."];
        Check(NumberedItemCount(fishFive)==5 && WordCount(fishFive)<=45 && [fishFive containsString:@"0–4°C"],[NSString stringWithFormat:@"A five-item fish answer keeps its requested count and safe temperature within 45 words: %@",fishFive]);
        NSString *cost=[parser presenterReadyB1Answer:@"Food Cost % = ($5545 ÷ $18912) × 100 = approximately 29.3%." forQuestion:@"Over one week, a restaurant spent $5545 on food and had $18912 in food sales. What is the Food Cost %?"];
        Check([cost containsString:@"approximately"] && [cost containsString:@"29.3%"] && WordCount(cost)<=45,@"The B2 pass preserves precise wording and a decimal percentage");
        NSString *culturalWhy=[parser presenterReadyB1Answer:@"Demonstrates respect for human dignity and fosters an inclusive environment. Prevents misunderstandings, offence, and loss of business." forQuestion:@"Why is it important to be sensitive to the needs and attitudes of different cultural groups?"];
        Equal(culturalWhy,@"It respects each person's dignity, creates an inclusive workplace, reduces misunderstandings, and supports anti-discrimination law.",@"Cultural-sensitivity wording is clear, respectful, and ready to say");
        NSString *culturalAvoid=[parser presenterReadyB1Answer:@"Participate in cultural awareness training. Use open, non-judgmental communication — ask politely instead of assuming. Promote anti-discrimination policies." forQuestion:@"In what ways can problems or misunderstandings with customers or colleagues from different cultural backgrounds be avoided?"];
        Check([culturalAvoid hasPrefix:@"I communicate openly"] && [culturalAvoid containsString:@"adapt my approach"] && WordCount(culturalAvoid)<=45,@"Cultural misunderstanding advice is a richer direct first-person answer");
        NSString *identity=[parser presenterReadyB1Answer:@"People may define their cultural identity through their ethnicity or nationality, their language and traditions, and their religion or beliefs." forQuestion:@"List three ways people may define their cultural identity."];
        Equal(identity,@"1. Ethnicity or nationality; 2. Language and traditions; 3. Religion or beliefs.",@"The common cultural-identity question returns three short, direct items");
        NSString *staff=[parser presenterReadyB1Answer:@"Provide clear instructions and demonstrations on safe work practices, use checklists and SOPs for hygiene and safety, monitor and give feedback during shifts, encourage open communication and reporting of hazards." forQuestion:@"How do you train your staff regarding work safety and hygiene?"];
        Check([staff hasPrefix:@"I explain and demonstrate"] && [staff containsString:@"constructive feedback"] && WordCount(staff)<=45,@"Staff safety and hygiene guidance uses natural B2 first-person language");
        NSString *haccp=[parser presenterReadyB1Answer:@"Conduct a hazard analysis, identify critical control points, establish critical limits, establish monitoring procedures, establish corrective actions, establish record keeping, and establish verification procedures." forQuestion:@"What are the seven principles of HACCP?"];
        Check(NumberedItemCount(haccp)==7 && WordCount(haccp)<=45,@"All seven requested HACCP principles fit inside one concise answer");
        Check([haccp containsString:@"Monitoring procedures"] && [haccp containsString:@"Verification procedures"],@"Official HACCP monitoring and verification terms are preserved");
        NSString *numberedList=[parser presenterReadyB1Answer:@"1. Communicate very clearly and respectfully with every customer. 2. Listen carefully and ask polite questions before making assumptions. 3. Learn about cultural practices and always treat each person fairly." forQuestion:@"List three ways to show cultural sensitivity."];
        Check(NumberedItemCount(numberedList)==3 && WordCount(numberedList)<=45,@"An already-numbered single-question list keeps every requested item under 45 total words");
        NSString *sds=[parser presenterReadyB1Answer:@"An SDS explains chemical hazards, storage, first aid, and disposal, and is used to ensure safe use of chemicals in the workplace." forQuestion:@"What is a Safety Data Sheet and what is it used for?"];
        Check([sds containsString:@"ensure safe use"] && ![sds containsString:@"make sure safe use"],@"B2 processing preserves precise, grammatical safety wording");
        NSString *richer=[parser presenterReadyB1Answer:@"I maintain an organised mise en place, communicate priorities clearly, monitor food safety throughout service, and adapt quickly when orders change. This helps the team work efficiently while protecting consistency, timing, and presentation quality." forQuestion:@"How do you stay effective during a busy service?"];
        Check(WordCount(richer)>30 && WordCount(richer)<=45,@"B2 answers can retain useful detail beyond the former 30-word limit");
        Check([richer containsString:@"maintain"] && [richer containsString:@"priorities"] && [richer containsString:@"efficiently"] && [richer containsString:@"consistency"],@"B2 vocabulary is preserved when it improves the answer");
        Check([parser questionNeedsInterviewSynthesis:@"Tell me about a time you handled a customer complaint."],@"Behavioral prompts request AI synthesis instead of returning a generic memorised line");
        Check(![parser questionNeedsInterviewSynthesis:@"What is the difference between cleaning and sanitising?"],@"Direct technical definitions retain the fast local-answer path");
        Equal(webBody[@"max_output_tokens"],@150,@"Single-question output token budget is tuned for fast Short and Full answers");
        NSDictionary *multipartBody=[parser answerRequestBodyForQuestion:@"What is cleaning?\nWhat is sanitising?" includeWebSearch:YES];
        Check([multipartBody[@"instructions"] containsString:@"Short: and Full:"],@"Multipart answers retain both answer variants");
        Equal(multipartBody[@"max_output_tokens"],@300,@"Multipart output retains enough tokens for two fast dual answers");
        NSDictionary *threePartBody=[parser answerRequestBodyForQuestion:@"What is cleaning?\nWhat is sanitising?\nWhat is hygiene?" includeWebSearch:NO];
        Equal(threePartBody[@"max_output_tokens"],@450,@"Multipart output budget scales so every detected question can be answered");
        Check([threePartBody[@"instructions"] containsString:@"Answer EVERY line"],@"Three-part turns explicitly preserve every question");
        NSDictionary *linkedBody=[parser answerRequestBodyForQuestion:@"What are the ingredients?\nSo what do you have in that?\nWhat are the ingredients?" includeWebSearch:NO];
        Check([linkedBody[@"instructions"] containsString:@"single underlying request"],@"Repeated and referential follow-ups are treated as one linked request");
        Check([linkedBody[@"instructions"] containsString:@"without numbering"],@"Linked question fragments produce one spoken answer instead of several unrelated answers");
        Equal(linkedBody[@"max_output_tokens"],@170,@"Linked fragments use one fast dual-answer token budget");
        Check([parser questionPartsAreLinked:[parser questionPartsForSynthesis:@"What are the ingredients?\nWhat do you have in that?"]],@"A referential follow-up is linked to its preceding question");
        Check(![parser questionPartsAreLinked:[parser questionPartsForSynthesis:@"Which knife is most versatile?\nWhat is the temperature danger zone?"]],@"Independent technical questions stay separate");
        NSDictionary *localOnlyBody=[parser answerRequestBodyForQuestion:@"What is versatility?" includeWebSearch:NO];
        Check(localOnlyBody[@"tools"]==nil,@"A request can be constructed without web search for graceful fallback");
        NSArray<NSDictionary *> *badBodies=@[
            @{@"status":@"completed",@"output":@[]},
            @{@"status":@"completed",@"output":@[Message(@[TextBlock(@"  \n ")])]},
            @{@"status":@"incomplete",@"incomplete_details":@{@"reason":@"max_output_tokens"},@"output":@[Message(@[TextBlock(@"Only half an answer")])]},
            @{@"status":@"failed",@"error":@{@"message":@"Model failed"},@"output":@[Message(@[TextBlock(@"Unusable partial text")])]},
            @{@"error":@{@"message":@"Invalid API key"}},
            @{@"status":@"completed",@"output":@[Message(@[@{@"type":@"refusal",@"refusal":@"Unable to answer"}])]},
            @{@"status":@"completed",@"output":@"malformed"},
            @{@"status":@"completed",@"output":@[NSNull.null,@{@"content":NSNull.null}]}
        ];
        for(NSDictionary *body in badBodies) {
            NSDictionary *result=[parser parsedAnswerData:JSON(body) status:200 error:nil];
            Check(![result[@"success"] boolValue],[NSString stringWithFormat:@"Empty, failed, or incomplete output cannot be cached: %@",body]);
            Check([result[@"answer"] isKindOfClass:NSString.class],@"Unsuccessful response includes a readable error");
        }
        NSDictionary *httpError=[parser parsedAnswerData:JSON(valid) status:429 error:nil];
        Check(![httpError[@"success"] boolValue],@"HTTP error cannot be accepted even when body contains text");
        NSDictionary *malformed=[parser parsedAnswerData:[@"not-json" dataUsingEncoding:NSUTF8StringEncoding] status:200 error:nil];
        Check(![malformed[@"success"] boolValue],@"Malformed JSON fails cleanly");
        NSError *network=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
        NSDictionary *timedOut=[parser parsedAnswerData:nil status:0 error:network];
        Check(![timedOut[@"success"] boolValue],@"Network timeout fails cleanly");
        Check([timedOut[@"answer"] length]>0,@"Network timeout gives a readable error");

        NSDictionary *release=@{@"assets":@[
          @{@"name":@"SA-Cook-Assistant-Windows-x64-v5.44.0.zip",@"browser_download_url":@"https://example.com/windows.zip"},
          @{@"name":@"anything.zip",@"browser_download_url":@"https://example.com/anything.zip"},
          @{@"name":@"SA-Cook-Assistant-v5.44.0.zip",@"browser_download_url":@"https://example.com/legacy.zip"},
          @{@"name":@"SA-Cook-Assistant-macOS-v5.44.0.zip",@"browser_download_url":@"https://example.com/mac.zip"}
        ]};
        Equal([parser macOSAssetInRelease:release version:@"v5.44.0"][@"browser_download_url"],@"https://example.com/mac.zip",@"Updater selects the exact macOS asset even when another ZIP appears first");
        NSDictionary *legacyRelease=@{@"assets":@[@{@"name":@"SA-Cook-Assistant-v5.44.zip",@"browser_download_url":@"https://example.com/legacy.zip"}]};
        Equal([parser macOSAssetInRelease:legacyRelease version:@"v5.44"][@"browser_download_url"],@"https://example.com/legacy.zip",@"Updater permits the exact legacy macOS asset name");
        NSDictionary *unsafeRelease=@{@"assets":@[@{@"name":@"anything.zip",@"browser_download_url":@"https://example.com/anything.zip"}]};
        Check([parser macOSAssetInRelease:unsafeRelease version:@"v5.44.0"]==nil,@"Updater never accepts an arbitrary first ZIP");
        Check([parser compareSemanticVersion:@"5.43" to:@"5.43.0"]==NSOrderedSame,@"Semantic comparison treats an omitted patch zero as the same version");
        fprintf(stdout,"Answer queue/parser: %lu assertions; %lu failures\n",(unsigned long)assertions,(unsigned long)failures);
        return failures ? 1 : 0;
    }
}
