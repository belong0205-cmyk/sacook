#import <Foundation/Foundation.h>
#import "../Sources/SCUntimedTranscriptBuffer.h"
#import <math.h>

static NSUInteger checks = 0, failures = 0;
static void Check(BOOL value, NSString *message) {
    checks++;
    if (!value) { failures++; fprintf(stderr, "FAIL: %s\n", message.UTF8String); }
}
static void Equal(NSString *actual, NSString *expected, NSString *message) {
    Check([actual isEqualToString:expected], [NSString stringWithFormat:@"%@ — expected <%@>, actual <%@>", message, expected, actual]);
}
static NSDictionary *Word(NSString *text, double start, double end) {
    return @{@"text":text, @"start":@(start), @"end":@(end)};
}

int main(void) {
    @autoreleasepool {
        SCUntimedTranscriptBuffer *space = [SCUntimedTranscriptBuffer new];
        SCUntimedTranscriptBuffer *automatic = [SCUntimedTranscriptBuffer new];
        NSString *first = @"What is cleaning and sanitising?";
        [space updateText:@"What is cleaning"];
        [space updateText:first];
        [automatic updateText:first];
        Equal(space.pendingText, first, @"Cumulative partial replaces earlier words rather than duplicating them");
        Equal(space.latestText, first, @"Latest full ASR text remains available");
        Check(space.pendingWords.count == 5, @"Pending words retain a textual boundary");
        Equal([space consume], first, @"Space snapshots exactly the visible untimed hypothesis");
        Equal(space.pendingText, @"", @"Space consumes its own words once");
        Equal(automatic.pendingText, first, @"Space cannot consume AUTO's buffer");
        Equal([space consume], @"", @"Repeated empty consume does not replay a question");

        NSString *second = @"Which knife is best?";
        NSString *cumulative = [first stringByAppendingFormat:@" %@", second];
        [space updateText:cumulative];
        Equal(space.pendingText, second, @"New cumulative tail remains available after an untimed consume");
        [space updateText:@"What is cleaning and sanitizing? Which knife is best?"];
        Equal(space.pendingText, second, @"Revision before consumed boundary cannot restore the previous question");
        [space updateText:@"What is cleaning"];
        Equal(space.pendingText, @"", @"Shorter interim hypothesis never moves consumed boundary backwards");
        [space consume];
        [space updateText:cumulative];
        Equal(space.pendingText, second, @"Consuming a temporarily shortened partial preserves the old boundary");
        [space consume];
        [space updateText:cumulative];
        Equal(space.pendingText, @"", @"Identical cumulative callback after consume produces no duplicate");

        [automatic finishTask];
        Equal(automatic.pendingText, first, @"Rollover carries unconsumed words");
        Equal(automatic.latestText, @"", @"Rollover starts a fresh task hypothesis");
        [automatic finishTask];
        Equal(automatic.pendingText, first, @"Repeated rollover cannot duplicate carried words");
        [automatic updateText:second];
        Equal(automatic.pendingText, cumulative, @"Next task text follows carried unconsumed text");
        Equal([automatic consume], cumulative, @"Consume includes old carried words and current task once");
        [automatic finishTask];
        [automatic updateText:@"Define HACCP."];
        Equal(automatic.pendingText, @"Define HACCP.", @"New task resets previous task's consumed word boundary");
        Equal(space.pendingText, @"", @"AUTO rollover leaves SPACE untouched");

        [space finishTask];
        NSMutableString *mutableText = [@"  Mise\n en\tplace?  " mutableCopy];
        [space updateText:mutableText];
        [mutableText setString:@"Changed"];
        Equal(space.pendingText, @"Mise en place?", @"Whitespace is normalised and supplied mutable text is copied");
        Equal(space.latestText, @"  Mise\n en\tplace?  ", @"Raw latest text is preserved separately");
        [space reset];
        Equal(space.pendingText, @"", @"Reset clears carried and current words");
        Equal(space.latestText, @"", @"Reset clears latest hypothesis");

        Check(SCUsableSpeechSegments(@[Word(@"What",0,.2),Word(@"is",.3,.5),Word(@"FIFO?",.6,.9)], 1), @"Valid nonzero durations are structurally usable");
        Check(!SCUsableSpeechSegments(@[Word(@"What",0,0),Word(@"is",0,0)], 1), @"All-zero partial timing uses textual fallback");
        Check(!SCUsableSpeechSegments(@[Word(@"What",20,20),Word(@"is",20,20)], 21), @"All-zero relative timing is still rejected after task offset");
        Check(!SCUsableSpeechSegments(@[Word(@"Bad",1,.5)], 2), @"Backwards durations are rejected");
        Check(!SCUsableSpeechSegments(@[Word(@"Bad",NAN,1)], 2), @"Nonfinite metadata is rejected");
        Check(!SCUsableSpeechSegments(@[Word(@"Bad",-1,.5)], 2), @"Negative global start is rejected");
        Check(!SCUsableSpeechSegments(@[Word(@"Later",1,1.2),Word(@"Earlier",.3,.6)], 2), @"Out-of-order segment timestamps are rejected");
        Check(!SCUsableSpeechSegments(@[Word(@"Future",2,3)], 1), @"Metadata extending beyond supplied audio is rejected");
        Check(!SCUsableSpeechSegments(@[Word(@"",0,.2)], 1), @"Empty words are rejected");
        Check(!SCUsableSpeechSegments(@[@{@"text":@"Bad",@"start":@"0",@"end":@1}], 1), @"Invalid metadata types are rejected");
        Check(!SCUsableSpeechSegments(@[], 1), @"Missing segments are not usable");
        Check(!SCUsableSpeechSegments(@[Word(@"Valid",0,.2)], NAN), @"Invalid audio cursor is rejected");
        Check(SCUsableSpeechSegments(@[Word(@"Rounding",0,1.1)], 1), @"Small final-buffer estimate tolerance is accepted");
        fprintf(stdout, "%lu untimed transcript checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
