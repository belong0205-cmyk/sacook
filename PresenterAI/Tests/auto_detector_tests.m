#import <Foundation/Foundation.h>
#import "../Sources/SCAutoQuestionDetector.h"

static NSUInteger checks = 0, failures = 0;
static NSArray *Words(NSString *text, double start) {
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *word in [text componentsSeparatedByString:@" "]) {
        if (!word.length) continue;
        [words addObject:@{@"text":word, @"start":@(start), @"end":@(start+0.16)}];
        start += 0.2;
    }
    return words;
}
static void Expect(BOOL condition, NSString *name) {
    checks++;
    if (!condition) { failures++; fprintf(stderr, "FAIL %s\n", name.UTF8String); }
}
static void ExpectQuestions(NSArray *actual, NSArray *expected, NSString *name) {
    NSArray *questions = [actual valueForKey:@"question"];
    Expect([questions isEqualToArray:expected], [NSString stringWithFormat:@"%@: expected %@ got %@",name,expected,questions]);
}

int main(void) {
    @autoreleasepool {
        SCAutoQuestionDetector *detector = [SCAutoQuestionDetector new];
        NSArray *words = Words(@"What is cleaning? I am still talking about something else", 0);
        ExpectQuestions([detector updateSegments:words audioTime:2.6 now:10 final:NO], @[], @"punctuated question waits for ASR stability");
        ExpectQuestions([detector tickWithAudioTime:2.7 now:10.36], @[@"What is cleaning?"], @"question emits ahead of trailing speech with no audio silence");
        ExpectQuestions([detector updateSegments:words audioTime:3 now:11 final:NO], @[], @"cumulative callbacks cannot repeat emitted question");
        ExpectQuestions([detector tickWithAudioTime:4 now:12], @[], @"statement tail never becomes a question");

        [detector reset];
        words = Words(@"Today we discuss safe kitchens. What is the difference between cleaning and sanitising?", 0);
        [detector updateSegments:words audioTime:4 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:4.1 now:10.36], @[@"What is the difference between cleaning and sanitising?"], @"leading statement does not block later question");

        [detector reset];
        words = Words(@"List three ways people may define their cultural identity. Describe how you avoid cross contamination.", 0);
        [detector updateSegments:words audioTime:5 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:5 now:10.36], @[@"List three ways people may define their cultural identity.",@"Describe how you avoid cross contamination."], @"embedded define and how never split imperative questions");

        [detector reset];
        words = Words(@"Which knife is the most versatile for slicing chopping and dicing What knife is best for cutting julienne or vegetables", 0);
        [detector updateSegments:words audioTime:5 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:5 now:10.36], @[], @"first part waits briefly for the second question in the same turn");
        ExpectQuestions([detector tickWithAudioTime:6 now:10.66], @[@"Which knife is the most versatile for slicing chopping and dicing",@"What knife is best for cutting julienne or vegetables"], @"both unpunctuated questions become ready together for one synthesis");

        [detector reset];
        [detector updateSegments:Words(@"What is cleaning?",0) audioTime:1 now:10 final:NO];
        [detector updateSegments:Words(@"What is cleaning and sanitising?",0) audioTime:2 now:10.2 final:NO];
        ExpectQuestions([detector tickWithAudioTime:2 now:10.36], @[], @"revised endpoint is not emitted from stale candidate");
        ExpectQuestions([detector tickWithAudioTime:2 now:10.56], @[@"What is cleaning and sanitising?"], @"latest revised full question emits once stable");

        [detector reset];
        words = Words(@"Give one example of preparing mise en place for a poultry seafood sandwich dish",0);
        [detector updateSegments:words audioTime:2.8 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:2.9 now:11.21], @[@"Give one example of preparing mise en place for a poultry seafood sandwich dish"], @"stable explicit question has bounded wait even without audio gap");

        [detector reset];
        [detector updateSegments:Words(@"What is the difference between",0) audioTime:3 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:5 now:12], @[], @"dangling preposition cannot be an endpoint");
        [detector updateSegments:Words(@"What is the difference between cleaning and sanitising",0) audioTime:5 now:12 final:NO];
        ExpectQuestions([detector tickWithAudioTime:6 now:12.66], @[@"What is the difference between cleaning and sanitising"], @"late final words complete pending question");

        [detector reset];
        words = Words(@"Tell me how do you ensure food safety?",0);
        [detector updateSegments:words audioTime:3 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:3 now:10.36], @[@"Tell me how do you ensure food safety?"], @"embedded interrogative after tell me stays attached");

        [detector reset];
        words = Words(@"What kitchen skills do you think are important?",0);
        [detector updateSegments:words audioTime:3 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:3 now:10.36], @[@"What kitchen skills do you think are important?"], @"late auxiliary is not mistaken for new question");

        [detector reset];
        words = [Words(@"List three ways",0) arrayByAddingObjectsFromArray:Words(@"people may define their cultural identity.",1.3)];
        [detector updateSegments:words audioTime:4 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:4 now:10.36], @[@"List three ways people may define their cultural identity."], @"natural pause within command retains full question");

        [detector reset];
        words = [Words(@"What is food safety",0) arrayByAddingObjectsFromArray:Words(@"in the kitchen?",1.4)];
        [detector updateSegments:words audioTime:4 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:4 now:10.36], @[@"What is food safety in the kitchen?"], @"paused qualifier stays attached");

        [detector reset];
        words = [Words(@"What is mise en place",0) arrayByAddingObjectsFromArray:Words(@"Do you know how to julienne vegetables?",1.7)];
        [detector updateSegments:words audioTime:4 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:4 now:10.36], @[@"What is mise en place", @"Do you know how to julienne vegetables?"], @"audio gap starts a separate auxiliary question");

        [detector reset];
        words = Words(@"What is cleaning? What is food safety?",0);
        [detector updateSegments:words audioTime:3 now:10 final:NO];
        words = Words(@"What is sanitising? What is food safety?",0);
        [detector updateSegments:words audioTime:3 now:10.2 final:NO];
        ExpectQuestions([detector tickWithAudioTime:3 now:10.36], @[], @"later stable candidate cannot consume earlier revised question");
        ExpectQuestions([detector tickWithAudioTime:3 now:10.56], @[@"What is sanitising?", @"What is food safety?"], @"revised candidates retain their audio order");

        [detector reset];
        words = Words(@"We have some time what is mise en place",0);
        [detector updateSegments:words audioTime:3 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:3 now:10.66], @[@"what is mise en place"], @"question after unpunctuated statement is detected");

        [detector reset];
        [detector updateSegments:Words(@"What is mise en place?",0) audioTime:2 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:2 now:10.36], @[@"What is mise en place?"], @"first occurrence emits");
        NSArray *second = [Words(@"What is mise en place?",0) arrayByAddingObjectsFromArray:Words(@"What is mise en place?",3)];
        [detector updateSegments:second audioTime:5 now:11 final:NO];
        ExpectQuestions([detector tickWithAudioTime:5 now:11.36], @[@"What is mise en place?"], @"same wording at a later audio interval is not suppressed");

        [detector reset];
        words = Words(@"What is food safety?",0);
        [detector updateSegments:words audioTime:2 now:10 final:YES];
        ExpectQuestions([detector tickWithAudioTime:2 now:10.13], @[@"What is food safety?"], @"final speech task uses short stabilization");

        [detector reset];
        [detector updateSegments:Words(@"Define julienne. Explain FIFO.",0) audioTime:2 now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:2 now:10.36], @[@"Define julienne.", @"Explain FIFO."], @"two-word culinary imperatives are valid requests");

        [detector reset];
        ExpectQuestions([detector updateText:@"What is cleaning?" now:10 final:NO], @[], @"untimed text waits for stable endpoint");
        Expect([detector.pendingText isEqualToString:@"What is cleaning?"], @"AUTO exposes independent live pending text");
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"What is cleaning?"], @"untimed zero-audio callback emits first question");
        Expect(detector.pendingText.length==0, @"AUTO pending text removes only consumed prefix");
        [detector updateText:@"What is cleaning? Define julienne." now:11 final:NO];
        Expect([detector.pendingText isEqualToString:@"Define julienne."], @"cumulative text exposes only new question");
        ExpectQuestions([detector tickWithAudioTime:0 now:11.36], @[@"Define julienne."], @"second question emits despite all-zero timing");
        [detector updateText:@"What is cleaning? Define julienne." now:12 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:14], @[], @"untimed repeated cumulative prefix does not replay");

        [detector reset];
        [detector updateText:@"What is cleaning" now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:10000 now:10.7], @[], @"text mode does not treat audio seconds as logical word positions");
        ExpectQuestions([detector tickWithAudioTime:0 now:11.21], @[@"What is cleaning"], @"untimed unpunctuated question has bounded wall-clock endpoint");

        [detector reset];
        [detector updateText:@"What is cleaning?" now:10 final:NO];
        [detector updateText:@"What is cleaning and sanitising?" now:10.2 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[], @"untimed cumulative correction cancels premature candidate");
        ExpectQuestions([detector tickWithAudioTime:0 now:10.56], @[@"What is cleaning and sanitising?"], @"untimed corrected full question settles");

        [detector reset];
        [detector updateText:@"What is mise en place?" now:10 final:NO];
        [detector tickWithAudioTime:0 now:10.36];
        [detector updateText:@"What is mise place? Define julienne." now:11 final:NO];
        Expect([detector.pendingText isEqualToString:@"Define julienne."], @"deletion in consumed ASR prefix does not remove next question's first word");
        ExpectQuestions([detector tickWithAudioTime:0 now:11.36], @[@"Define julienne."], @"next question survives shortened consumed prefix");

        [detector reset];
        [detector updateText:@"What is mise place?" now:10 final:NO];
        [detector tickWithAudioTime:0 now:10.36];
        [detector updateText:@"What is mise en place? Define julienne." now:11 final:NO];
        Expect([detector.pendingText isEqualToString:@"Define julienne."], @"insertion in consumed ASR prefix does not replay old ending");
        ExpectQuestions([detector tickWithAudioTime:0 now:11.36], @[@"Define julienne."], @"next question survives expanded consumed prefix");

        [detector reset];
        [detector updateText:@"What is cleaning?" now:10 final:YES];
        [detector finishTextTask];
        [detector finishTextTask];
        [detector updateText:@"Define julienne." now:10.1 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.13], @[@"What is cleaning?"], @"task rollover preserves pending final question and is idempotent");
        ExpectQuestions([detector tickWithAudioTime:0 now:10.46], @[@"Define julienne."], @"next task uses fresh logical offset without replacing prior task");
        [detector finishTextTask];
        [detector updateText:@"Define julienne." now:11 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:11.36], @[@"Define julienne."], @"same question on a later task is allowed");

        [detector reset];
        [detector updateText:@"What is cleaning" now:10 final:YES];
        [detector finishTextTask];
        [detector updateText:@"Explain FIFO." now:10.1 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.46], @[@"What is cleaning", @"Explain FIFO."], @"task boundary separates unpunctuated question from next imperative");

        [detector reset];
        [detector updateText:@"List three ways people may define their cultural identity. Describe how you avoid cross contamination." now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"List three ways people may define their cultural identity.", @"Describe how you avoid cross contamination."], @"untimed parser preserves embedded define and how");

        [detector reset];
        [detector updateText:@"Which knife is the most versatile for slicing chopping and dicing What knife is best for cutting julienne or vegetables" now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[], @"untimed multipart turn waits for its trailing question");
        ExpectQuestions([detector tickWithAudioTime:0 now:10.66], @[@"Which knife is the most versatile for slicing chopping and dicing",@"What knife is best for cutting julienne or vegetables"], @"untimed multipart questions become ready together");

        [detector reset];
        [detector updateText:@"What is cleaning?" now:10 final:NO];
        [detector discardPendingText];
        Expect(detector.pendingText.length==0, @"pausing AUTO clears only its own pending transcript");
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[], @"paused pending AUTO question does not emit");
        [detector updateText:@"What is cleaning? Define julienne." now:11 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:11.36], @[@"Define julienne."], @"resuming AUTO skips discarded prefix and receives only new question");

        [detector reset];
        [detector updateText:@"Define julienne What is food safety?" now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"Define julienne", @"What is food safety?"], @"two-word imperative separates from following unpunctuated question");
        [detector reset];
        [detector updateText:@"Explain how" now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:12], @[], @"two-word incomplete subordinate request remains pending");

        for (NSString *naturalRequest in @[@"Tell us how you prepare for service", @"Walk me through your mise en place", @"Talk us through food safety procedures", @"Share an example of handling pressure"]) {
            [detector reset];
            [detector updateText:naturalRequest now:10 final:NO];
            ExpectQuestions([detector tickWithAudioTime:0 now:11.21], @[naturalRequest], @"natural interview request is recognised without a question mark");
        }

        for(NSString *leadIn in @[@"All right what is the difference between cleaning and sanitising?", @"I would like to know how you prevent cross contamination", @"Let me ask which knife is the most versatile?"]) {
            [detector reset];
            [detector updateText:leadIn now:10 final:YES];
            NSArray *ready=[detector tickWithAudioTime:0 now:10.13];
            Expect(ready.count==1,[NSString stringWithFormat:@"natural lead-in produces one question: %@",leadIn]);
        }

        [detector reset];
        [detector updateText:@"How do you ensure quality and consistency in your work I follow recipes" now:10 final:NO];
        [detector updateText:@"How do you ensure quality and consistency in your work I follow recipes and check the presentation of every dish" now:10.2 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"How do you ensure quality and consistency in your work"], @"continuous unpunctuated quality Q&A closes before first-person answer");
        [detector updateText:@"How do you ensure quality and consistency in your work I follow recipes and check the presentation of every dish before service" now:10.5 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:12], @[], @"continuing quality answer never becomes another question");

        [detector reset];
        [detector updateText:@"How do you handle pressure during busy hours I stay calm and prioritise tasks" now:10 final:NO];
        [detector updateText:@"How do you handle pressure during busy hours I stay calm and prioritise tasks and communicate with my team" now:10.2 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"How do you handle pressure during busy hours"], @"continuous unpunctuated pressure Q&A emits while answer keeps growing");

        [detector reset];
        [detector updateText:@"How do you maintain food safety We always follow safe food handling procedures" now:10 final:NO];
        ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[@"How do you maintain food safety"], @"first-person plural answer with frequency adverb closes question");

        for (NSString *question in @[@"What exactly should I do when food is contaminated?", @"In what ways can we ensure food safety?", @"Describe a time when I follow a recipe incorrectly.", @"What happens if I keep food above the required temperature?", @"Explain how I maintain quality and consistency."]) {
            [detector reset];
            [detector updateText:question now:10 final:NO];
            ExpectQuestions([detector tickWithAudioTime:0 now:10.36], @[question], @"embedded first-person subject stays part of original request");
        }

        fprintf(stdout, "%lu AUTO detector checks, %lu failures\n", (unsigned long)checks, (unsigned long)failures);
        return failures ? 1 : 0;
    }
}
