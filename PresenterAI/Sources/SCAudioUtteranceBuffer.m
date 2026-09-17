#import "SCAudioUtteranceBuffer.h"
#import <math.h>

static void SCAppendLE16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2]={(uint8_t)(value&0xff),(uint8_t)((value>>8)&0xff)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void SCAppendLE32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4]={(uint8_t)(value&0xff),(uint8_t)((value>>8)&0xff),(uint8_t)((value>>16)&0xff),(uint8_t)((value>>24)&0xff)};
    [data appendBytes:bytes length:sizeof(bytes)];
}

@interface SCAudioUtteranceBuffer ()
@property NSMutableData *preRoll;
@property NSMutableData *utterance;
@property double sampleRate;
@property (nonatomic, readwrite) BOOL hasActiveUtterance;
@end

@implementation SCAudioUtteranceBuffer

- (instancetype)init {
    self=[super init];
    if(self) [self reset];
    return self;
}

- (void)reset {
    @synchronized(self) {
      self.preRoll=[NSMutableData data];
      self.utterance=[NSMutableData data];
      self.sampleRate=0;
      self.hasActiveUtterance=NO;
    }
}

- (NSData *)monoPCM16FromBuffer:(AVAudioPCMBuffer *)buffer {
    if(!buffer || !buffer.frameLength || !buffer.format.channelCount) return [NSData data];
    AVAudioFrameCount frames=buffer.frameLength;
    AVAudioChannelCount channels=buffer.format.channelCount;
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)frames*sizeof(int16_t)];
    int16_t *output=data.mutableBytes;
    float *const *floats=buffer.floatChannelData;
    if(floats) {
      for(AVAudioFrameCount frame=0;frame<frames;frame++) {
        double sum=0;
        for(AVAudioChannelCount channel=0;channel<channels;channel++) sum+=floats[channel][frame];
        double sample=MAX(-1.0,MIN(1.0,sum/channels));
        output[frame]=(int16_t)lrint(sample*32767.0);
      }
      return data;
    }
    int16_t *const *signed16=buffer.int16ChannelData;
    if(signed16) {
      for(AVAudioFrameCount frame=0;frame<frames;frame++) {
        long sum=0;
        for(AVAudioChannelCount channel=0;channel<channels;channel++) sum+=signed16[channel][frame];
        output[frame]=(int16_t)(sum/(long)channels);
      }
      return data;
    }
    return [NSData data];
}

- (void)appendBuffer:(AVAudioPCMBuffer *)buffer voiced:(BOOL)voiced {
    NSData *chunk=[self monoPCM16FromBuffer:buffer];
    if(!chunk.length || buffer.format.sampleRate<=0) return;
    @synchronized(self) {
      if(self.sampleRate<=0) self.sampleRate=buffer.format.sampleRate;
      if(fabs(self.sampleRate-buffer.format.sampleRate)>1) [self reset];
      self.sampleRate=buffer.format.sampleRate;
      if(self.hasActiveUtterance) {
        [self.utterance appendData:chunk];
      } else {
        [self.preRoll appendData:chunk];
        NSUInteger maximum=(NSUInteger)llround(self.sampleRate*0.35)*sizeof(int16_t);
        if(self.preRoll.length>maximum)
          [self.preRoll replaceBytesInRange:NSMakeRange(0,self.preRoll.length-maximum) withBytes:NULL length:0];
        if(voiced) {
          self.utterance=[self.preRoll mutableCopy];
          self.hasActiveUtterance=YES;
        }
      }
      // A meeting turn should never grow without bound if background noise keeps
      // VAD open. Thirty seconds is ample for an interview question.
      NSUInteger maximum=(NSUInteger)llround(self.sampleRate*30.0)*sizeof(int16_t);
      if(self.utterance.length>maximum)
        [self.utterance replaceBytesInRange:NSMakeRange(0,self.utterance.length-maximum) withBytes:NULL length:0];
    }
}

- (NSTimeInterval)activeDuration {
    @synchronized(self) {
      return self.sampleRate>0?(double)(self.utterance.length/sizeof(int16_t))/self.sampleRate:0;
    }
}

- (NSData *)wavDataForPCM:(NSData *)pcm sampleRate:(double)sampleRate {
    if(!pcm.length || sampleRate<=0 || pcm.length>UINT32_MAX-44) return nil;
    uint32_t payload=(uint32_t)pcm.length,rate=(uint32_t)llround(sampleRate);
    NSMutableData *wav=[NSMutableData dataWithCapacity:44+payload];
    [wav appendBytes:"RIFF" length:4]; SCAppendLE32(wav,36+payload);
    [wav appendBytes:"WAVEfmt " length:8]; SCAppendLE32(wav,16); SCAppendLE16(wav,1); SCAppendLE16(wav,1);
    SCAppendLE32(wav,rate); SCAppendLE32(wav,rate*2); SCAppendLE16(wav,2); SCAppendLE16(wav,16);
    [wav appendBytes:"data" length:4]; SCAppendLE32(wav,payload); [wav appendData:pcm];
    return wav;
}

- (NSData *)finishUtteranceWithMinimumDuration:(NSTimeInterval)minimumDuration {
    @synchronized(self) {
      if(!self.hasActiveUtterance) return nil;
      NSData *pcm=[self.utterance copy]; double rate=self.sampleRate;
      NSUInteger tailMaximum=(NSUInteger)llround(rate*0.35)*sizeof(int16_t);
      NSUInteger tail=MIN(tailMaximum,pcm.length);
      self.preRoll=tail?[NSMutableData dataWithData:[pcm subdataWithRange:NSMakeRange(pcm.length-tail,tail)]]:[NSMutableData data];
      self.utterance=[NSMutableData data]; self.hasActiveUtterance=NO;
      NSTimeInterval duration=rate>0?(double)(pcm.length/sizeof(int16_t))/rate:0;
      return duration+0.000001>=minimumDuration?[self wavDataForPCM:pcm sampleRate:rate]:nil;
    }
}

@end
