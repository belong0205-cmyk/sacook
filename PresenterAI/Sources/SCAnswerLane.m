#import "SCAnswerLane.h"
#import <dispatch/dispatch.h>

@interface SCAnswerJob : NSObject
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSString *question;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *records;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL finished;
@end
@implementation SCAnswerJob
@end

@interface SCAnswerLane ()
@property (nonatomic, copy) SCAnswerRequest requestBlock;
@property (nonatomic, strong) NSMutableArray<SCAnswerJob *> *queue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCAnswerJob *> *jobs;
@property (nonatomic, readwrite) NSUInteger activeCount;
@property (nonatomic) BOOL draining;
@end

@implementation SCAnswerLane

- (instancetype)initWithRequestBlock:(SCAnswerRequest)requestBlock {
    NSParameterAssert(requestBlock);
    if ((self = [super init])) {
        _requestBlock = [requestBlock copy];
        _queue = [NSMutableArray array];
        _jobs = [NSMutableDictionary dictionary];
        _cache = [NSMutableDictionary dictionary];
        _maxConcurrent = 2;
    }
    return self;
}

- (void)setCache:(NSMutableDictionary<NSString *, NSString *> *)cache {
    NSAssert(NSThread.isMainThread, @"Configure answer lanes on the main thread");
    _cache = [cache mutableCopy] ?: [NSMutableDictionary dictionary];
}

- (NSUInteger)pendingCount { return self.queue.count; }

- (void)setMaxConcurrent:(NSUInteger)maxConcurrent {
    NSAssert(NSThread.isMainThread, @"Configure answer lanes on the main thread");
    _maxConcurrent = MAX((NSUInteger)1, maxConcurrent);
    [self drain];
}

- (void)notifyChange { if (self.onChange) self.onChange(); }

- (void)enqueueRecord:(NSMutableDictionary *)record cacheKey:(NSString *)cacheKey {
    NSAssert(NSThread.isMainThread, @"Enqueue answers on the main thread");
    NSString *question = [record[@"requestQuestion"] isKindOfClass:NSString.class] ? record[@"requestQuestion"] : record[@"question"];
    if (![question isKindOfClass:NSString.class]) question=@"";
    question = [question stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!question.length || !cacheKey.length) {
        record[@"answer"] = @"No question was captured. Please try again.";
        record[@"state"] = @"failed";
        [self notifyChange];
        return;
    }
    NSString *cached = self.cache[cacheKey];
    if ([cached isKindOfClass:NSString.class] && cached.length) {
        record[@"answer"] = cached;
        record[@"state"] = @"complete";
        [self notifyChange];
        return;
    }
    SCAnswerJob *existing = self.jobs[cacheKey];
    if (existing) {
        if ([existing.records indexOfObjectIdenticalTo:record] == NSNotFound)
            [existing.records addObject:record];
        record[@"state"] = existing.started ? @"loading" : @"waiting";
        [self notifyChange];
        return;
    }
    SCAnswerJob *job = [SCAnswerJob new];
    job.key = cacheKey;
    job.question = question;
    job.records = [NSMutableArray arrayWithObject:record];
    self.jobs[cacheKey] = job;
    [self.queue addObject:job];
    record[@"state"] = @"waiting";
    [self notifyChange];
    [self drain];
}

- (void)finishJob:(SCAnswerJob *)job answer:(NSString *)answer success:(BOOL)success {
    NSAssert(NSThread.isMainThread, @"Resolve answer records on the main thread");
    if (job.finished) return; // A duplicate network callback cannot release another request's slot.
    job.finished = YES;
    NSString *trimmed = [answer isKindOfClass:NSString.class]
        ? [answer stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    success = success && trimmed.length > 0;
    if (!trimmed.length) trimmed = @"The AI returned no answer. Please try again.";
    for (NSMutableDictionary *record in job.records) {
        record[@"answer"] = trimmed;
        record[@"state"] = success ? @"complete" : @"failed";
    }
    [self.jobs removeObjectForKey:job.key];
    self.activeCount--;
    if (success) {
        self.cache[job.key] = trimmed;
        if (self.onCacheChange) self.onCacheChange();
    }
    [self notifyChange];
    [self drain];
}

- (void)drain {
    if (self.draining) return;
    self.draining = YES;
    while (self.activeCount < self.maxConcurrent && self.queue.count) {
        SCAnswerJob *job = self.queue.firstObject;
        [self.queue removeObjectAtIndex:0];
        job.started = YES;
        self.activeCount++;
        for (NSMutableDictionary *record in job.records) record[@"state"] = @"loading";
        [self notifyChange];
        __weak typeof(self) weakSelf = self;
        self.requestBlock(job.question, ^(NSString *answer, BOOL success) {
            void (^finish)(void) = ^{ [weakSelf finishJob:job answer:answer success:success]; };
            if (NSThread.isMainThread) finish();
            else dispatch_async(dispatch_get_main_queue(), finish);
        });
    }
    self.draining = NO;
}

@end
