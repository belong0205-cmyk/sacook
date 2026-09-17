#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A per-consumer fallback for cumulative speech hypotheses without usable timing.
/// Word positions are textual boundaries, never claimed to be audio timestamps.
@interface SCUntimedTranscriptBuffer : NSObject
@property (nonatomic, readonly, copy) NSString *latestText;
@property (nonatomic, readonly, copy) NSString *pendingText;
@property (nonatomic, readonly, copy) NSArray<NSString *> *pendingWords;
- (void)updateText:(NSString *)text;
/// Carries only unconsumed words into the next ASR task.
- (void)finishTask;
/// Returns pending words and advances this consumer's textual boundary.
- (NSString *)consume;
- (void)reset;
@end

/// Structural validation only: even nonzero partial-result times may be revised.
/// Input segments have global @"start"/@"end" seconds and @"text" strings.
FOUNDATION_EXPORT BOOL SCUsableSpeechSegments(NSArray<NSDictionary<NSString *, id> *> *segments,
                                             NSTimeInterval audioEnd);

NS_ASSUME_NONNULL_END
