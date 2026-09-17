#import "SCSpeechTimeline.h"
#import <math.h>

@interface SCSpeechTimeline ()
@property NSArray<NSDictionary<NSString *, id> *> *completedSegments;
@property NSArray<NSDictionary<NSString *, id> *> *currentSegments;
@property NSTimeInterval pruneTime;
@end

@implementation SCSpeechTimeline

- (instancetype)init {
    self = [super init];
    if (self) [self reset];
    return self;
}

- (void)reset {
    self.completedSegments = @[];
    self.currentSegments = @[];
    self.pruneTime = -INFINITY;
}

- (void)replaceCurrentSegments:(NSArray<NSDictionary<NSString *, id> *> *)segments {
    NSMutableArray *validated = [NSMutableArray arrayWithCapacity:segments.count];
    for (id candidate in segments) {
        if (![candidate isKindOfClass:NSDictionary.class]) continue;
        id text = candidate[@"text"], startValue = candidate[@"start"], endValue = candidate[@"end"];
        if (![text isKindOfClass:NSString.class] ||
            ![startValue isKindOfClass:NSNumber.class] || ![endValue isKindOfClass:NSNumber.class]) continue;
        NSTimeInterval start = [startValue doubleValue], end = [endValue doubleValue];
        NSString *word = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!word.length || !isfinite(start) || !isfinite(end) || end < start || end <= self.pruneTime) continue;
        [validated addObject:@{@"text":word.copy, @"start":@(start), @"end":@(end)}];
    }
    [validated sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];
    // A speech callback is the latest complete hypothesis for this task.
    // Appending each callback would duplicate all previously recognised words.
    self.currentSegments = validated.copy;
}

- (void)finishCurrentTask {
    if (!self.currentSegments.count) return;
    self.completedSegments = [self.completedSegments arrayByAddingObjectsFromArray:self.currentSegments];
    self.currentSegments = @[];
}

- (NSArray<NSDictionary<NSString *, id> *> *)segmentsFrom:(NSTimeInterval)from to:(NSTimeInterval)to {
    if (isnan(from) || isnan(to) || from >= to) return @[];
    NSMutableArray *selected = [NSMutableArray array];
    for (NSArray *segments in @[self.completedSegments, self.currentSegments]) {
        for (NSDictionary *segment in segments) {
            NSTimeInterval start = [segment[@"start"] doubleValue];
            if (start >= from && start < to) [selected addObject:segment];
        }
    }
    [selected sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"start"] compare:b[@"start"]];
    }];
    return selected;
}

- (NSString *)textFrom:(NSTimeInterval)from to:(NSTimeInterval)to {
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (NSDictionary *segment in [self segmentsFrom:from to:to]) [words addObject:segment[@"text"]];
    return [words componentsJoinedByString:@" "];
}

- (NSTimeInterval)endTimeFrom:(NSTimeInterval)from to:(NSTimeInterval)to {
    NSTimeInterval end = from;
    for (NSDictionary *segment in [self segmentsFrom:from to:to]) end = MAX(end, [segment[@"end"] doubleValue]);
    return end;
}

- (void)pruneBefore:(NSTimeInterval)time {
    if (!isfinite(time) || time <= self.pruneTime) return;
    self.pruneTime = time;
    NSPredicate *keep = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *segment, __unused NSDictionary *bindings) {
        return [segment[@"end"] doubleValue] > time;
    }];
    self.completedSegments = [self.completedSegments filteredArrayUsingPredicate:keep];
    self.currentSegments = [self.currentSegments filteredArrayUsingPredicate:keep];
}

@end
