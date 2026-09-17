// Execute the preserved 5.12 implementation to demonstrate the regressions.
#define main BaselineApplicationMain
#import "main-v5.12.baseline.m"
#undef main
@interface BaselineApp : AppDelegate
@property NSMutableArray *captured;
@end
@implementation BaselineApp
- (void)appendOfflineAnswerForQuestion:(NSString *)q { [self.captured addObject:q]; }
- (void)setStatus:(NSString *)s color:(NSColor *)c {}
@end
int main(void) { @autoreleasepool {
    BaselineApp *app=[BaselineApp new]; app.captured=[NSMutableArray array];
    NSUInteger confirmed=0;
    if(![[app correctCulinaryTerms:@"julienne"] isEqualToString:@"julienne"]) confirmed++;
    NSString *q=@"List three ways people may define their cultural identity";
    if(![[app primaryQuestionFromText:q] isEqualToString:q]) confirmed++;
    [app processQuestionText:q]; if(app.captured.count!=1 || ![app.captured.firstObject isEqual:q]) confirmed++;
    if(![app looksLikeQuestion:@"Which knife is best for slicing"]) confirmed++;
    NSString *both=@"Which knife is best for slicing? What knife is best for julienne?";
    if(![[app primaryQuestionFromText:both] isEqualToString:both]) confirmed++;
    app.lastMatchedQuestion=@"How do you cook steak?"; app.lastMatchConfidence=0.55;
    if(![[app displayQuestionForHeardQuestion:q] isEqualToString:q]) confirmed++;
    fprintf(stdout,"v5.12 baseline: %lu/6 reported defects reproduced\n",(unsigned long)confirmed);
    return confirmed==6?0:1;
} }
