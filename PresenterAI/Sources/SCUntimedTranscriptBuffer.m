#import "SCUntimedTranscriptBuffer.h"
#import <math.h>

@interface SCUntimedTranscriptBuffer ()
@property (nonatomic, readwrite, copy) NSString *latestText;
@property (nonatomic, copy) NSArray<NSString *> *currentWords;
@property (nonatomic, copy) NSArray<NSString *> *carriedWords;
@property (nonatomic) NSUInteger consumedCount;
@end

@implementation SCUntimedTranscriptBuffer

- (instancetype)init {
    self = [super init];
    if (self) [self reset];
    return self;
}

- (void)reset {
    self.latestText = @"";
    self.currentWords = @[];
    self.carriedWords = @[];
    self.consumedCount = 0;
}

- (void)updateText:(NSString *)text {
    self.latestText = [text ?: @"" copy];
    NSArray<NSString *> *parts = [self.latestText componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSString *> *words = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) if (part.length) [words addObject:part.copy];
    self.currentWords = words;
    // The ASR may temporarily retract or revise its cumulative hypothesis. Keep
    // the consumed boundary until finishTask; shrinking it would replay words.
}

- (NSArray<NSString *> *)pendingWords {
    NSUInteger from = MIN(self.consumedCount, self.currentWords.count);
    NSArray<NSString *> *tail = [self.currentWords subarrayWithRange:NSMakeRange(from, self.currentWords.count - from)];
    return [self.carriedWords arrayByAddingObjectsFromArray:tail];
}

- (NSString *)pendingText {
    return [self.pendingWords componentsJoinedByString:@" "];
}

- (NSString *)consume {
    NSString *text = self.pendingText;
    self.carriedWords = @[];
    self.consumedCount = MAX(self.consumedCount, self.currentWords.count);
    return text;
}

- (void)finishTask {
    self.carriedWords = self.pendingWords;
    self.currentWords = @[];
    self.latestText = @"";
    self.consumedCount = 0;
}

@end

BOOL SCUsableSpeechSegments(NSArray<NSDictionary<NSString *, id> *> *segments, NSTimeInterval audioEnd) {
    if (!segments.count || !isfinite(audioEnd) || audioEnd < 0) return NO;
    NSTimeInterval previousStart = -INFINITY;
    for (id segment in segments) {
        if (![segment isKindOfClass:NSDictionary.class]) return NO;
        id text = segment[@"text"], startValue = segment[@"start"], endValue = segment[@"end"];
        if (![text isKindOfClass:NSString.class] ||
            ![startValue isKindOfClass:NSNumber.class] || ![endValue isKindOfClass:NSNumber.class]) return NO;
        if (![[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]) return NO;
        NSTimeInterval start = [startValue doubleValue], end = [endValue doubleValue];
        // Positive duration rejects all-zero partial metadata, including that
        // same metadata after a nonzero task offset has been added by the caller.
        // A small allowance accommodates recognizer rounding at the last buffer.
        if (!isfinite(start) || !isfinite(end) || start < 0 || end <= start ||
            start < previousStart || end > audioEnd + 0.25) return NO;
        previousStart = start;
    }
    return YES;
}
