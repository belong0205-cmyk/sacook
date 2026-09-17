#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Independent AUTO endpoint state. Feed snapshots of word segments in global
/// audio seconds; `now` is a monotonic wall clock used to settle ASR revisions.
/// Each returned item is @{ @"question": NSString, @"start": NSNumber, @"end": NSNumber }.
/// Calling these methods never consumes or changes a SPACE transcript.
@interface SCAutoQuestionDetector : NSObject
@property (nonatomic, readonly) NSTimeInterval consumedThrough;
/// Live unconsumed words, independent of any manual/SPACE cursor.
@property (nonatomic, readonly, copy) NSString *pendingText;
/// Preferred for recognition engines that omit timing from partial results.
/// Returned start/end and consumedThrough are logical word positions in this
/// mode, not audio seconds. Cumulative text revisions replace the current task.
- (NSArray<NSDictionary<NSString *, id> *> *)updateText:(NSString *)cumulativeText
                                                  now:(NSTimeInterval)now
                                                final:(BOOL)isFinal;
/// Preserve unconsumed text and begin the next recognition task at a new offset.
- (void)finishTextTask;
/// Consume the current AUTO-only buffer while paused; future text remains eligible.
- (void)discardPendingText;
/// Do not mix timing and text modes on one instance without calling reset.
- (NSArray<NSDictionary<NSString *, id> *> *)updateSegments:(NSArray<NSDictionary<NSString *, id> *> *)segments
                                                audioTime:(NSTimeInterval)audioTime
                                                      now:(NSTimeInterval)now
                                                    final:(BOOL)isFinal;
/// Call periodically (e.g. every 100 ms), even when no recognition callback arrives.
- (NSArray<NSDictionary<NSString *, id> *> *)tickWithAudioTime:(NSTimeInterval)audioTime
                                                       now:(NSTimeInterval)now;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
