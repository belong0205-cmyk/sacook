#import <Foundation/Foundation.h>
#import "../Sources/SCAnswerLane.h"

static NSUInteger assertions, failures;
static void Check(BOOL condition, NSString *message) {
    assertions++;
    if (!condition) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Equal(id actual, id expected, NSString *message) {
    Check([actual isEqual:expected], [NSString stringWithFormat:@"%@ — expected %@; got %@", message, expected, actual]);
}
static NSMutableDictionary *Record(NSString *question) {
    return [@{@"question": question, @"answer": @"Preparing…", @"state": @"queued"} mutableCopy];
}

int main(void) {
    @autoreleasepool {
        NSMutableArray<NSString *> *manualSent = [NSMutableArray array], *autoSent = [NSMutableArray array];
        NSMutableArray<SCAnswerCompletion> *manualDone = [NSMutableArray array], *autoDone = [NSMutableArray array];
        SCAnswerLane *manual = [[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question, SCAnswerCompletion completion) {
            [manualSent addObject:question]; [manualDone addObject:[completion copy]];
        }];
        SCAnswerLane *automatic = [[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question, SCAnswerCompletion completion) {
            [autoSent addObject:question]; [autoDone addObject:[completion copy]];
        }];
        __block NSUInteger manualChanges = 0, autoChanges = 0, cacheChanges = 0;
        manual.onChange = ^{ manualChanges++; };
        automatic.onChange = ^{ autoChanges++; };
        manual.onCacheChange = ^{ cacheChanges++; };

        NSMutableDictionary *first = Record(@"What is mise en place?"), *second = Record(@"What is julienne?"), *third = Record(@"What is brunoise?");
        [manual enqueueRecord:first cacheKey:@"mise"];
        [manual enqueueRecord:second cacheKey:@"julienne"];
        [manual enqueueRecord:third cacheKey:@"brunoise"];
        Equal(@(manual.activeCount), @2, @"SPACE has its own two request slots");
        Equal(@(manual.pendingCount), @1, @"A busy SPACE retains its third question");
        Equal(third[@"state"], @"waiting", @"Queued SPACE record shows waiting state");
        NSMutableDictionary *autoFirst = Record(@"What is mise en place?");
        [automatic enqueueRecord:autoFirst cacheKey:@"mise"];
        Equal(@(autoSent.count), @1, @"AUTO starts immediately while SPACE is saturated");
        Equal(@(automatic.activeCount), @1, @"AUTO accounts for its own active request");
        Equal(@(manualSent.count), @2, @"AUTO does not consume or dispatch SPACE slots");
        Equal(autoSent.firstObject, manualSent.firstObject, @"Identical questions issue independent requests in both lanes");
        NSUInteger manualChangesBeforeAuto = manualChanges;
        autoDone[0](@"AUTO answer", YES);
        Equal(autoFirst[@"answer"], @"AUTO answer", @"AUTO receives its own answer");
        Equal(first[@"answer"], @"Preparing…", @"AUTO answer does not fill SPACE record");
        Equal(@(manualChanges), @(manualChangesBeforeAuto), @"AUTO completion does not notify SPACE observers");
        Check(manual.cache[@"mise"] == nil, @"AUTO success does not enter SPACE cache");

        // Finish out of order, then exercise a callback delivered twice.
        manualDone[1](@"Small matchstick cut", YES);
        Equal(@(manualSent.count), @3, @"SPACE starts its retained question after a slot opens");
        Equal(manualSent.lastObject, third[@"question"], @"FIFO preserves the queued question");
        Equal(second[@"answer"], @"Small matchstick cut", @"Out-of-order answer updates only its originating row");
        Equal(first[@"answer"], @"Preparing…", @"Out-of-order answer leaves first row pending");
        manualDone[1](@"Duplicate result", YES);
        Equal(@(manual.activeCount), @2, @"Duplicate callback cannot release an unrelated slot");
        Equal(second[@"answer"], @"Small matchstick cut", @"Duplicate callback cannot overwrite completed answer");
        manualDone[2](@"Small dice", YES);
        manualDone[0](@"SPACE answer", YES);
        Equal(first[@"answer"], @"SPACE answer", @"Late SPACE response retains its own result");
        Equal(third[@"answer"], @"Small dice", @"Late older response cannot overwrite newest row");
        Equal(autoFirst[@"answer"], @"AUTO answer", @"Late SPACE result cannot overwrite AUTO");
        Equal(@(manual.activeCount), @0, @"All SPACE slots released");
        Equal(@(manual.pendingCount), @0, @"SPACE queue drained");
        Equal(@(cacheChanges), @3, @"Cache observers run once per successful request");

        NSMutableDictionary *manualRepeat = Record(@"What is mise en place?"), *autoRepeat = Record(@"What is mise en place?");
        [manual enqueueRecord:manualRepeat cacheKey:@"mise"];
        [automatic enqueueRecord:autoRepeat cacheKey:@"mise"];
        Equal(manualRepeat[@"answer"], @"SPACE answer", @"SPACE repeats use only the SPACE cache");
        Equal(autoRepeat[@"answer"], @"AUTO answer", @"AUTO repeats use only the AUTO cache");
        Equal(@(manualSent.count), @3, @"SPACE cache does not issue another request");
        Equal(@(autoSent.count), @1, @"AUTO cache does not issue another request");

        NSMutableDictionary *failed = Record(@"Why did the request fail?");
        [manual enqueueRecord:failed cacheKey:@"failure"];
        manualDone[3](@"Network timeout", NO);
        Equal(failed[@"state"], @"failed", @"Failure leaves a terminal, readable state");
        Check(manual.cache[@"failure"] == nil, @"Failure is never cached");
        Equal(@(cacheChanges), @3, @"Failure does not trigger cache persistence");
        NSMutableDictionary *retry = Record(@"Why did the request fail?");
        [manual enqueueRecord:retry cacheKey:@"failure"];
        Equal(@(manualSent.count), @5, @"Failed question can retry");
        manualDone[4](@"   \n", YES);
        Equal(retry[@"state"], @"failed", @"Empty successful payload is rejected");
        Check(manual.cache[@"failure"] == nil, @"Empty payload is never cached");

        NSMutableDictionary *same1 = Record(@"What is a chef knife?"), *same2 = Record(@"What is a chef knife");
        [manual enqueueRecord:same1 cacheKey:@"knife"];
        [manual enqueueRecord:same2 cacheKey:@"knife"];
        [manual enqueueRecord:same2 cacheKey:@"knife"];
        Equal(@(manualSent.count), @6, @"Only same-lane matching keys may coalesce");
        manualDone[5](@"A versatile kitchen knife.", YES);
        Equal(same1[@"answer"], same2[@"answer"], @"Same-lane waiters are both resolved");
        Equal(same2[@"question"], @"What is a chef knife", @"Coalescing keeps each original question text");

        // Even explicit cache injection does not share mutable storage across lanes.
        NSMutableDictionary *seed = [@{@"seed": @"Seed answer"} mutableCopy];
        manual.cache = seed; automatic.cache = seed;
        manual.cache[@"manual-only"] = @"Local answer";
        Check(automatic.cache[@"manual-only"] == nil, @"Injected cache is copied into each lane");
        Check(seed[@"manual-only"] == nil, @"Lane writes do not mutate the injected seed");

        // Synchronous providers must also drain safely without recursive scheduling.
        __block NSUInteger synchronousRequests = 0;
        SCAnswerLane *synchronous = [[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question, SCAnswerCompletion completion) {
            synchronousRequests++; completion(question, YES);
        }];
        NSMutableDictionary *sync = Record(@"A synchronous answer");
        [synchronous enqueueRecord:sync cacheKey:@"sync"];
        Equal(@(synchronousRequests), @1, @"Synchronous provider called once");
        Equal(@(synchronous.activeCount), @0, @"Synchronous completion releases its slot");
        Equal(sync[@"state"], @"complete", @"Synchronous result completes the right row");
        Check(manualChanges > 0 && autoChanges > 0, @"Each lane notifies its own observer");

        __block BOOL changesOnMainThread = YES;
        SCAnswerLane *background = [[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question, SCAnswerCompletion completion) {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ completion(question, YES); });
        }];
        background.onChange = ^{ changesOnMainThread = changesOnMainThread && NSThread.isMainThread; };
        NSMutableDictionary *backgroundRecord = Record(@"Background response");
        [background enqueueRecord:backgroundRecord cacheKey:@"background"];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (![backgroundRecord[@"state"] isEqual:@"complete"] && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        Equal(backgroundRecord[@"state"], @"complete", @"Background completion reaches its originating record");
        Check(changesOnMainThread, @"Background result notifies UI observers only on the main thread");

        fprintf(stdout, "Independent answer lanes: %lu assertions; %lu failures\n", (unsigned long)assertions, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
