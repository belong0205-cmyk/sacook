#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Tracks immutable, completed speech tasks plus the revisable current task.
/// Each segment is @{ @"text": NSString, @"start": NSNumber, @"end": NSNumber }.
/// Timestamps are seconds on one global audio stream, not task-relative time.
@interface SCSpeechTimeline : NSObject
- (void)replaceCurrentSegments:(NSArray<NSDictionary<NSString *, id> *> *)segments;
- (void)finishCurrentTask;
/// Includes words whose start is in [from, to), even when their end exceeds to.
- (NSString *)textFrom:(NSTimeInterval)from to:(NSTimeInterval)to;
/// Immutable word snapshot for a consumer's independent processing.
- (NSArray<NSDictionary *> *)segmentsFrom:(NSTimeInterval)from to:(NSTimeInterval)to;
/// Greatest end of the selected words, or from when there are no words.
- (NSTimeInterval)endTimeFrom:(NSTimeInterval)from to:(NSTimeInterval)to;
/// Drops words ending at/before time and prevents cumulative updates restoring them.
- (void)pruneBefore:(NSTimeInterval)time;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
