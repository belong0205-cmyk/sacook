#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thread-safe mono PCM utterance recorder used by AUTO's enhanced
/// transcription path. It keeps a short pre-roll so the first consonant is not
/// lost when voice activity crosses the threshold.
@interface SCAudioUtteranceBuffer : NSObject
@property (nonatomic, readonly) BOOL hasActiveUtterance;
@property (nonatomic, readonly) NSTimeInterval activeDuration;
- (void)appendBuffer:(AVAudioPCMBuffer *)buffer voiced:(BOOL)voiced;
/// Returns a complete 16-bit mono WAV and starts a fresh utterance. Returns nil
/// for empty/noise-only captures shorter than minimumDuration.
- (nullable NSData *)finishUtteranceWithMinimumDuration:(NSTimeInterval)minimumDuration;
- (void)reset;
@end

NS_ASSUME_NONNULL_END
