#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "../Sources/SCAudioUtteranceBuffer.h"

static NSUInteger checks=0;
static void Assert(BOOL condition,NSString *message) {
    checks++;
    if(!condition) { NSLog(@"FAIL: %@",message); exit(1); }
}

static AVAudioPCMBuffer *Buffer(AVAudioFrameCount frames,float value) {
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:2];
    AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
    buffer.frameLength=frames;
    for(AVAudioChannelCount channel=0;channel<2;channel++)
      for(AVAudioFrameCount frame=0;frame<frames;frame++) buffer.floatChannelData[channel][frame]=value;
    return buffer;
}

static uint32_t LE32(const uint8_t *bytes) {
    return (uint32_t)bytes[0]|((uint32_t)bytes[1]<<8)|((uint32_t)bytes[2]<<16)|((uint32_t)bytes[3]<<24);
}

int main(void) { @autoreleasepool {
    SCAudioUtteranceBuffer *capture=[SCAudioUtteranceBuffer new];
    [capture appendBuffer:Buffer(3200,0) voiced:NO];
    Assert(!capture.hasActiveUtterance,@"silence must stay in pre-roll only");
    [capture appendBuffer:Buffer(3200,0.2) voiced:YES];
    [capture appendBuffer:Buffer(6400,0.1) voiced:YES];
    Assert(capture.hasActiveUtterance,@"voice must start an utterance");
    Assert(capture.activeDuration>=0.74 && capture.activeDuration<=0.76,@"bounded pre-roll and voice frames must be retained exactly");
    NSData *wav=[capture finishUtteranceWithMinimumDuration:0.45];
    Assert(wav.length==44+24000,@"WAV must contain mono 16-bit PCM");
    const uint8_t *bytes=wav.bytes;
    Assert(!memcmp(bytes,"RIFF",4) && !memcmp(bytes+8,"WAVE",4),@"WAV header must be valid");
    Assert(LE32(bytes+24)==16000,@"WAV sample rate must match input");
    Assert(LE32(bytes+40)==24000,@"WAV payload length must match PCM");
    Assert(!capture.hasActiveUtterance,@"finish must reset the active turn");

    [capture appendBuffer:Buffer(800,0.1) voiced:YES];
    Assert([capture finishUtteranceWithMinimumDuration:1.0]==nil,@"very short noise turn must be discarded");
    [capture reset];
    Assert(!capture.hasActiveUtterance && capture.activeDuration==0,@"reset must clear all audio");
    NSLog(@"Audio utterance buffer tests passed (%lu checks)",(unsigned long)checks);
} return 0; }
