#import <Foundation/Foundation.h>
#import "../Sources/SCSpeechTimeline.h"
#import <math.h>

static NSUInteger failures = 0, checks = 0;
static NSDictionary *Word(NSString *text, double start, double end) {
    return @{@"text":text, @"start":@(start), @"end":@(end)};
}
static void ExpectText(NSString *actual, NSString *expected, NSString *scenario) {
    checks++;
    if (![actual isEqualToString:expected]) {
        failures++;
        fprintf(stderr, "FAIL %s: expected <%s>, got <%s>\n", scenario.UTF8String, expected.UTF8String, actual.UTF8String);
    }
}
static void ExpectTime(double actual, double expected, NSString *scenario) {
    checks++;
    if (fabs(actual - expected) > 0.000001) {
        failures++;
        fprintf(stderr, "FAIL %s: expected %.6f, got %.6f\n", scenario.UTF8String, expected, actual);
    }
}

int main(void) {
    @autoreleasepool {
        SCSpeechTimeline *timeline = [SCSpeechTimeline new];

        // Partial callbacks are cumulative hypotheses, including corrections.
        [timeline replaceCurrentSegments:@[Word(@"What",0,.2),Word(@"is",.3,.4),Word(@"clean",.5,.8)]];
        [timeline replaceCurrentSegments:@[Word(@"What",0,.2),Word(@"is",.3,.4),Word(@"cleaning?",.5,.9)]];
        ExpectText([timeline textFrom:0 to:INFINITY], @"What is cleaning?", @"replace revised cumulative partial without duplication");

        // Space at t=2.0: final words can arrive late but retain their audio time.
        [timeline replaceCurrentSegments:@[Word(@"What",0,.2),Word(@"is",.3,.4),Word(@"cleaning",.5,.9),Word(@"and",1.0,1.2),Word(@"sanitising?",1.3,1.9),Word(@"Which",2.1,2.3),Word(@"knife?",2.4,2.7)]];
        ExpectText([timeline textFrom:0 to:2.0], @"What is cleaning and sanitising?", @"late last words before Space cutoff are retained");
        ExpectText([timeline textFrom:2.0 to:INFINITY], @"Which knife?", @"next question after Space cutoff stays separate");
        ExpectTime([timeline endTimeFrom:0 to:2.0], 1.9, @"AUTO cursor follows last selected word end");

        // Reading one consumer must not consume the other consumer's question.
        ExpectText([timeline textFrom:0 to:INFINITY], @"What is cleaning and sanitising? Which knife?", @"AUTO cursor independent of SPACE read");
        ExpectText([timeline textFrom:2.0 to:INFINITY], @"Which knife?", @"SPACE cursor independent of AUTO read");

        [timeline finishCurrentTask];
        [timeline finishCurrentTask];
        ExpectText([timeline textFrom:0 to:INFINITY], @"What is cleaning and sanitising? Which knife?", @"repeated finalisation does not append twice");

        // Main maps task-relative timestamps to global seconds at rollover.
        double restartOffset = 3.0;
        [timeline replaceCurrentSegments:@[Word(@"Describe",restartOffset+.1,restartOffset+.4),Word(@"mise",restartOffset+.5,restartOffset+.7)]];
        [timeline replaceCurrentSegments:@[Word(@"Describe",restartOffset+.1,restartOffset+.4),Word(@"mise",restartOffset+.5,restartOffset+.7),Word(@"en",restartOffset+.8,restartOffset+.9),Word(@"place.",restartOffset+1,restartOffset+1.4)]];
        ExpectText([timeline textFrom:2.0 to:INFINITY], @"Which knife? Describe mise en place.", @"new task uses global restart offset without replacing completed task");
        ExpectText([timeline textFrom:3.0 to:INFINITY], @"Describe mise en place.", @"restart boundary selects only new task");

        [timeline pruneBefore:3.0];
        ExpectText([timeline textFrom:0 to:INFINITY], @"Describe mise en place.", @"pruning old tasks preserves current task");
        [timeline pruneBefore:3.7];
        [timeline replaceCurrentSegments:@[Word(@"Describe",3.1,3.4),Word(@"mise",3.5,3.7),Word(@"en",3.8,3.9),Word(@"place.",4.0,4.4)]];
        ExpectText([timeline textFrom:0 to:INFINITY], @"en place.", @"later cumulative callback cannot reintroduce pruned words");
        ExpectTime([timeline endTimeFrom:6.0 to:7.0], 6.0, @"empty range does not advance cursor");

        [timeline reset];
        ExpectText([timeline textFrom:0 to:INFINITY], @"", @"reset clears all tasks and prune state");
        [timeline replaceCurrentSegments:@[Word(@"Before",.9,1.1),Word(@"At",1.0,1.3),Word(@"After",1.1,1.4)]];
        ExpectText([timeline textFrom:0 to:1.0], @"Before", @"word start determines cutoff even when word overlaps it");
        ExpectText([timeline textFrom:1.0 to:2.0], @"At After", @"cutoff belongs to the next interval");
        ExpectText([timeline textFrom:1.0 to:1.0], @"", @"empty half-open interval");

        [timeline reset];
        NSMutableString *mutableWord = [@"Valid" mutableCopy];
        [timeline replaceCurrentSegments:@[Word(mutableWord,0,.2),Word(@"",.3,.4),Word(@"NaN",NAN,.5),Word(@"backwards",2,1),@{@"text":@"bad",@"start":@"0",@"end":@1}]];
        [mutableWord setString:@"Changed"];
        ExpectText([timeline textFrom:0 to:INFINITY], @"Valid", @"segment snapshots are immutable and malformed times are ignored");

        fprintf(stdout, "%lu timeline checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
