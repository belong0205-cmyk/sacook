#import "SCAutoQuestionDetector.h"
#import <math.h>

static NSString *SCWord(NSString *text) {
    return [[text lowercaseString] stringByTrimmingCharactersInSet:
            [[NSCharacterSet alphanumericCharacterSet] invertedSet]];
}

static BOOL SCTerminal(NSString *text) {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet characterSetWithCharactersInString:@"\"'’”)]}"]];
    if ([trimmed hasSuffix:@"?"] || [trimmed hasSuffix:@"!"]) return YES;
    if (![trimmed hasSuffix:@"."]) return NO;
    return ![@[@"e.g.", @"i.e.", @"mr.", @"mrs.", @"dr.", @"vs."] containsObject:trimmed.lowercaseString];
}

static BOOL SCIn(NSString *word, NSArray<NSString *> *words) {
    return [words containsObject:word];
}

static BOOL SCStarter(NSArray<NSDictionary *> *words, NSUInteger i, BOOL internal) {
    NSString *word = SCWord(words[i][@"text"]);
    NSString *next = i+1 < words.count ? SCWord(words[i+1][@"text"]) : @"";
    NSString *third = i+2 < words.count ? SCWord(words[i+2][@"text"]) : @"";
    if (internal) {
        // A subordinate interrogative belongs to its existing request:
        // "Tell me how...", "Explain what...", "Do you know which...".
        NSString *previous = i ? SCWord(words[i-1][@"text"]) : @"";
        if (SCIn(previous, @[@"me", @"know", @"explain", @"describe", @"understand", @"discuss", @"consider", @"ask", @"asking", @"wonder", @"about", @"of", @"on", @"and", @"or", @"determine", @"identify", @"show"])) return NO;
    }
    if ([word isEqualToString:@"in"] && [next isEqualToString:@"what"] && [third isEqualToString:@"ways"]) return YES;
    if (SCIn(word, @[@"what", @"which", @"whose"])) {
        // "What skills...", "Which knife..." need no auxiliary verb.
        return next.length > 0;
    }
    if (SCIn(word, @[@"how", @"why", @"when", @"where", @"who", @"whom"])) {
        if (!internal) return next.length > 0;
        return SCIn(next, @[@"do", @"does", @"did", @"is", @"are", @"was", @"were", @"can", @"could", @"would", @"should", @"will", @"have", @"has", @"many", @"much", @"long", @"often"]);
    }
    if (SCIn(word, @[@"can", @"could", @"do", @"does", @"did", @"are", @"is", @"was", @"were", @"would", @"will", @"have", @"has", @"should", @"may", @"might", @"must"])) {
        // "What kitchen skills do you..." and "Tell me how do you..."
        // contain auxiliaries well after the beginning of the same question.
        if (internal) return NO;
        return SCIn(next, @[@"you", @"your", @"we", @"there", @"it", @"this", @"that", @"a", @"an", @"the", @"food", @"all", @"any"]);
    }
    // Imperatives only start a request at a sentence boundary. In particular,
    // never split "List three ways people may define their cultural identity".
    BOOL guidedWalkthrough=SCIn(word,@[@"walk",@"talk",@"take"]) && SCIn(next,@[@"me",@"us"]) && [third isEqualToString:@"through"];
    return !internal && (SCIn(word, @[@"explain", @"list", @"name", @"describe", @"identify", @"give", @"outline", @"define", @"compare", @"discuss", @"provide", @"state", @"mention", @"show", @"share", @"design", @"distinguish", @"demonstrate"])
                         || ([word isEqualToString:@"tell"] && SCIn(next,@[@"me",@"us"])) || guidedWalkthrough);
}

static BOOL SCIncomplete(NSArray<NSDictionary *> *words) {
    if (words.count < 2) return YES;
    if (words.count == 2 && !SCIn(SCWord(words.firstObject[@"text"]), @[@"define", @"explain", @"describe", @"identify", @"compare", @"discuss", @"name", @"demonstrate"])) return YES;
    NSString *last = SCWord(words.lastObject[@"text"]);
    return SCIn(last, @[@"a", @"an", @"the", @"for", @"to", @"of", @"between", @"and", @"or", @"with", @"is", @"are", @"do", @"does", @"can", @"could", @"would", @"in", @"on", @"from", @"by", @"your", @"their", @"my", @"our", @"than", @"such", @"as", @"whether", @"how", @"what", @"which"]);
}

static BOOL SCAnswerTurn(NSArray<NSDictionary *> *words, NSUInteger i) {
    if (!i || i+1>=words.count) return NO;
    NSString *subject=SCWord(words[i][@"text"]);
    if (!SCIn(subject,@[@"i",@"we"])) return NO;
    NSString *previous=SCWord(words[i-1][@"text"]);
    // These words introduce an embedded subject, not an answer turn:
    // "What should I do", "How can we ensure", "Describe a time when I...".
    if (SCIn(previous,@[@"should",@"can",@"could",@"do",@"does",@"did",@"would",@"will",@"may",@"might",@"must",@"shall",@"if",@"that",@"how",@"when",@"where",@"why",@"what",@"which",@"whether",@"while",@"because",@"and",@"or",@"but",@"as",@"than",@"think",@"wish",@"believe"])) return NO;
    NSString *verb=SCWord(words[i+1][@"text"]);
    if (SCIn(verb,@[@"always",@"usually",@"normally"]) && i+2<words.count) verb=SCWord(words[i+2][@"text"]);
    // Deliberately limited to the first-person answer openings in the cook Q&A
    // material. This is a boundary hint, not a general-purpose grammar parser.
    return SCIn(verb,@[@"follow",@"ensure",@"maintain",@"keep",@"use",@"stay",@"check",@"wash",@"clean",@"store",@"label",@"work",@"communicate",@"listen",@"prioritise",@"prioritize",@"organise",@"organize",@"ask",@"report",@"separate",@"prepare",@"explain",@"wear"]);
}

// Revisions can insert or remove a word in the already-consumed prefix. Align
// that prefix to the revised hypothesis so the next question's first word is
// neither skipped nor replayed. Work is bounded to the consumed prefix plus a
// short correction window, not the entire stream.
static NSUInteger SCMappedPrefix(NSArray<NSString *> *old, NSArray<NSString *> *new, NSUInteger consumed) {
    consumed = MIN(consumed, old.count);
    if (!consumed) return 0;
    BOOL same = new.count >= consumed;
    for (NSUInteger i=0; i<consumed && same; i++) same = [SCWord(old[i]) isEqualToString:SCWord(new[i])];
    if (same) return consumed;
    NSUInteger width = MIN(new.count, consumed+24);
    NSUInteger *previous = calloc(width+1, sizeof(NSUInteger));
    NSUInteger *current = calloc(width+1, sizeof(NSUInteger));
    if (!previous || !current) { free(previous); free(current); return MIN(consumed,new.count); }
    for (NSUInteger j=0; j<=width; j++) previous[j]=j;
    for (NSUInteger i=1; i<=consumed; i++) {
        current[0]=i;
        for (NSUInteger j=1; j<=width; j++) {
            NSUInteger substitution = [SCWord(old[i-1]) isEqualToString:SCWord(new[j-1])] ? 0 : 1;
            current[j]=MIN(MIN(previous[j]+1,current[j-1]+1),previous[j-1]+substitution);
        }
        NSUInteger *swap=previous; previous=current; current=swap;
    }
    NSUInteger best=MIN(consumed,width);
    NSUInteger bestSuffix=0;
    while (bestSuffix<MIN(MIN(consumed,best),(NSUInteger)3) && [SCWord(old[consumed-1-bestSuffix]) isEqualToString:SCWord(new[best-1-bestSuffix])]) bestSuffix++;
    for (NSUInteger j=0; j<=width; j++) {
        NSUInteger suffix=0;
        while (suffix<MIN(MIN(consumed,j),(NSUInteger)3) && [SCWord(old[consumed-1-suffix]) isEqualToString:SCWord(new[j-1-suffix])]) suffix++;
        if (previous[j]<previous[best] || (previous[j]==previous[best] && (suffix>bestSuffix || (suffix==bestSuffix && labs((long)j-(long)consumed)<labs((long)best-(long)consumed))))) { best=j; bestSuffix=suffix; }
    }
    free(previous); free(current);
    return best;
}

@interface SCAutoQuestionDetector ()
@property (nonatomic, readwrite) NSTimeInterval consumedThrough;
@property (nonatomic, copy) NSArray<NSDictionary *> *segments;
@property (nonatomic, copy) NSArray<NSMutableDictionary *> *pending;
@property (nonatomic) BOOL finalSnapshot;
@property (nonatomic) BOOL textMode;
@property (nonatomic) NSUInteger textTaskBase;
@property (nonatomic, copy) NSArray<NSString *> *currentTextWords;
@property (nonatomic, copy) NSArray<NSDictionary *> *completedTextWords;
@end

@implementation SCAutoQuestionDetector

- (instancetype)init {
    self = [super init];
    if (self) [self reset];
    return self;
}

- (void)reset {
    self.consumedThrough = 0;
    self.segments = @[];
    self.pending = @[];
    self.finalSnapshot = NO;
    self.textMode = NO;
    self.textTaskBase = 0;
    self.currentTextWords = @[];
    self.completedTextWords = @[];
}

- (NSString *)pendingText {
    NSMutableArray *words = [NSMutableArray array];
    for (NSDictionary *word in self.segments) {
        if ([word[@"start"] doubleValue] >= self.consumedThrough-0.001) [words addObject:word[@"text"]];
    }
    return [words componentsJoinedByString:@" "];
}

- (NSArray<NSDictionary<NSString *, id> *> *)updateText:(NSString *)cumulativeText
                                                  now:(NSTimeInterval)now
                                                final:(BOOL)isFinal {
    if (!isfinite(now)) return @[];
    self.textMode = YES;
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSString *part in [(cumulativeText ?: @"") componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) {
        if (part.length) [tokens addObject:part.copy];
    }
    if (self.consumedThrough > self.textTaskBase && self.currentTextWords.count) {
        NSUInteger consumed = (NSUInteger)(self.consumedThrough-self.textTaskBase);
        self.consumedThrough = self.textTaskBase+SCMappedPrefix(self.currentTextWords,tokens,consumed);
    }
    self.currentTextWords = tokens;
    NSMutableArray *snapshot = [self.completedTextWords mutableCopy];
    for (NSUInteger i=0; i<tokens.count; i++) {
        [snapshot addObject:@{@"text":tokens[i], @"start":@(self.textTaskBase+i), @"end":@(self.textTaskBase+i+1), @"taskBoundary":@(i==0 && self.textTaskBase>0)}];
    }
    return [self updateWords:snapshot audioTime:0 now:now final:isFinal];
}

- (void)finishTextTask {
    if (!self.textMode || !self.currentTextWords.count) return;
    NSMutableArray *remaining = [NSMutableArray array];
    for (NSDictionary *word in self.segments) {
        if ([word[@"start"] doubleValue] >= self.consumedThrough-0.001) [remaining addObject:word];
    }
    // ASR task rollover is a reliable text boundary, even without word times.
    self.textTaskBase += self.currentTextWords.count;
    self.currentTextWords = @[];
    self.completedTextWords = remaining.count>512 ? [remaining subarrayWithRange:NSMakeRange(remaining.count-512,512)] : remaining;
    for (NSMutableDictionary *candidate in self.pending) candidate[@"final"]=@YES;
}

- (void)discardPendingText {
    if (self.segments.count) self.consumedThrough=MAX(self.consumedThrough,[self.segments.lastObject[@"end"] doubleValue]);
    self.pending=@[];
    self.completedTextWords=@[];
}

- (NSArray<NSDictionary *> *)validatedWords:(NSArray<NSDictionary *> *)segments {
    NSMutableArray *words = [NSMutableArray array];
    NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (id item in segments) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id text = item[@"text"], start = item[@"start"], end = item[@"end"];
        if (![text isKindOfClass:NSString.class] || ![start isKindOfClass:NSNumber.class] || ![end isKindOfClass:NSNumber.class]) continue;
        if (!isfinite([start doubleValue]) || !isfinite([end doubleValue]) || [end doubleValue] < [start doubleValue] || [start doubleValue] < self.consumedThrough - 0.001) continue;
        // Most Speech segments contain one word. Retain the original timestamp
        // if a recognizer groups a phrase; no synthetic audio times are invented.
        for (NSString *part in [text componentsSeparatedByCharactersInSet:whitespace]) {
            BOOL boundary = [item[@"taskBoundary"] isKindOfClass:NSNumber.class] && [item[@"taskBoundary"] boolValue];
            if (part.length) [words addObject:@{@"text":part.copy, @"start":start, @"end":end, @"taskBoundary":@(boundary)}];
        }
    }
    [words sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];
    return words;
}

- (NSArray<NSDictionary *> *)candidates {
    NSArray *words = self.segments;
    NSMutableArray *candidates = [NSMutableArray array];
    NSUInteger start = NSNotFound;
    NSUInteger boundary = 0;
    for (NSUInteger i = 0; i < words.count; i++) {
        BOOL gap = i && ([words[i][@"taskBoundary"] boolValue] || [words[i][@"start"] doubleValue] - [words[i-1][@"end"] doubleValue] >= 0.45);
        BOOL newStarter = SCStarter(words, i, start != NSNotFound);
        // A pause inside a question does not make its next noun a new sentence.
        // A following request or conversational turn can close an unpunctuated
        // question. A silent tail is handled by the stability timer below.
        BOOL newTurn = SCIn(SCWord(words[i][@"text"]), @[@"i", @"we", @"okay", @"ok", @"so", @"next", @"thanks", @"thank"]);
        BOOL gapBoundary = gap && (SCStarter(words, i, NO) || newTurn);
        BOOL answerBoundary = start!=NSNotFound && i-start>=3 && SCAnswerTurn(words,i);
        if (start != NSNotFound && i > start && (gapBoundary || answerBoundary || (i-start >= 2 && newStarter))) {
            NSArray *slice = [words subarrayWithRange:NSMakeRange(start, i-start)];
            if (!SCIncomplete(slice)) {
                [self addCandidate:slice endpoint:YES to:candidates];
                start = NSNotFound;
                boundary = i;
            }
        }
        if (start == NSNotFound) {
            BOOL atBoundary = i == boundary || gap;
            BOOL fillerPrefix = YES;
            for (NSUInteger j = boundary; j < i && fillerPrefix; j++) {
                fillerPrefix = SCIn(SCWord(words[j][@"text"]), @[@"okay", @"ok", @"so", @"please", @"and", @"now", @"next", @"question", @"right", @"well", @"all", @"alright", @"then", @"let", @"me", @"ask", @"id", @"i'd", @"i", @"would", @"like", @"want", @"to", @"know", @"im", @"i'm", @"i’m", @"curious", @"about"]);
            }
            if (SCStarter(words, i, !(atBoundary || fillerPrefix))) start = i;
        }
        if (SCTerminal(words[i][@"text"])) {
            if (start != NSNotFound) {
                NSArray *slice = [words subarrayWithRange:NSMakeRange(start, i-start+1)];
                if (!SCIncomplete(slice)) [self addCandidate:slice endpoint:YES to:candidates];
            }
            start = NSNotFound;
            boundary = i+1;
        }
    }
    if (start != NSNotFound) {
        NSArray *slice = [words subarrayWithRange:NSMakeRange(start, words.count-start)];
        if (!SCIncomplete(slice)) [self addCandidate:slice endpoint:NO to:candidates];
    }
    return candidates;
}

- (void)addCandidate:(NSArray<NSDictionary *> *)words endpoint:(BOOL)endpoint to:(NSMutableArray *)candidates {
    NSMutableArray *text = [NSMutableArray arrayWithCapacity:words.count];
    for (NSDictionary *word in words) [text addObject:word[@"text"]];
    [candidates addObject:@{@"question":[text componentsJoinedByString:@" "], @"start":words.firstObject[@"start"], @"end":words.lastObject[@"end"], @"endpoint":@(endpoint), @"taskBoundaryStart":words.firstObject[@"taskBoundary"] ?: @NO}];
}

- (NSArray<NSDictionary<NSString *, id> *> *)updateSegments:(NSArray<NSDictionary<NSString *, id> *> *)segments
                                                audioTime:(NSTimeInterval)audioTime
                                                      now:(NSTimeInterval)now
                                                    final:(BOOL)isFinal {
    self.textMode = NO;
    return [self updateWords:segments audioTime:audioTime now:now final:isFinal];
}

- (NSArray<NSDictionary *> *)updateWords:(NSArray<NSDictionary *> *)segments
                               audioTime:(NSTimeInterval)audioTime
                                     now:(NSTimeInterval)now
                                   final:(BOOL)isFinal {
    if (!isfinite(audioTime) || !isfinite(now)) return @[];
    self.segments = [self validatedWords:segments];
    self.finalSnapshot = isFinal;
    NSMutableArray *nextPending = [NSMutableArray array];
    for (NSDictionary *candidate in [self candidates]) {
        NSMutableDictionary *state = [candidate mutableCopy];
        state[@"stableSince"] = @(now);
        state[@"final"] = @(isFinal || (self.textMode && [candidate[@"end"] doubleValue] <= self.textTaskBase));
        for (NSDictionary *previous in self.pending) {
            if ([candidate[@"question"] isEqualToString:previous[@"question"]] && fabs([candidate[@"start"] doubleValue] - [previous[@"start"] doubleValue]) < 0.4) {
                state[@"stableSince"] = previous[@"stableSince"];
                state[@"final"] = @([state[@"final"] boolValue] || [previous[@"final"] boolValue]);
                break;
            }
        }
        [nextPending addObject:state];
    }
    self.pending = nextPending;
    return [self tickWithAudioTime:audioTime now:now];
}

- (NSArray<NSDictionary<NSString *, id> *> *)tickWithAudioTime:(NSTimeInterval)audioTime
                                                       now:(NSTimeInterval)now {
    if (!isfinite(audioTime) || !isfinite(now)) return @[];
    NSMutableArray *ready = [NSMutableArray array];
    NSMutableArray *remaining = [NSMutableArray array];
    BOOL earlierPending = NO;
    BOOL multipart = self.pending.count > 1;
    // Recognition-task rollover is a real turn boundary. Never delay the
    // previous task merely because a new task already contains a question.
    for (NSUInteger i=1; i<self.pending.count && multipart; i++)
        if ([self.pending[i][@"taskBoundaryStart"] boolValue]) multipart=NO;
    BOOL allMultipartPartsReady = multipart;
    if (multipart) {
        for (NSDictionary *candidate in self.pending) {
            NSTimeInterval stable = MAX(0, now-[candidate[@"stableSince"] doubleValue]);
            NSTimeInterval sinceSpeech = self.textMode ? 0 : audioTime-[candidate[@"end"] doubleValue];
            BOOL endpoint = [candidate[@"endpoint"] boolValue];
            // A second question in the same unconsumed turn is normally the
            // last, unpunctuated partial. Give it a short merge window so the
            // caller receives all parts together instead of answering part 1.
            NSTimeInterval delay = [candidate[@"final"] boolValue] ? 0.12 : endpoint ? 0.35 : sinceSpeech >= 0.45 ? 0.65 : 0.65;
            if (stable+0.000001 < delay) { allMultipartPartsReady=NO; break; }
        }
    }
    for (NSDictionary *candidate in self.pending) {
        NSTimeInterval stable = MAX(0, now-[candidate[@"stableSince"] doubleValue]);
        NSTimeInterval sinceSpeech = self.textMode ? 0 : audioTime-[candidate[@"end"] doubleValue];
        BOOL endpoint = [candidate[@"endpoint"] boolValue];
        NSTimeInterval delay = [candidate[@"final"] boolValue] ? 0.12 : endpoint ? 0.35 : sinceSpeech >= 0.45 ? 0.65 : multipart ? 0.65 : 1.20;
        if (!earlierPending && (!multipart || allMultipartPartsReady) && stable+0.000001 >= delay) {
            [ready addObject:@{@"question":candidate[@"question"], @"start":candidate[@"start"], @"end":candidate[@"end"], @"turnBoundary":candidate[@"taskBoundaryStart"] ?: @NO}];
            self.consumedThrough = MAX(self.consumedThrough, [candidate[@"end"] doubleValue]);
        } else {
            [remaining addObject:candidate];
            earlierPending = YES;
        }
    }
    self.pending = remaining;
    return ready;
}

@end
