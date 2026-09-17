#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^SCAnswerCompletion)(NSString *answer, BOOL success);
typedef void (^SCAnswerRequest)(NSString *question, SCAnswerCompletion completion);

/// One panel's answer requests. Create a separate instance for SPACE and AUTO.
/// Enqueue and configure on the main thread; request completions may arrive on any thread.
@interface SCAnswerLane : NSObject
- (instancetype)initWithRequestBlock:(SCAnswerRequest)requestBlock NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Assignment copies the dictionary, so lanes cannot accidentally share cache storage.
@property (nonatomic, copy) NSMutableDictionary<NSString *, NSString *> *cache;
@property (nonatomic, copy, nullable) void (^onChange)(void);
@property (nonatomic, copy, nullable) void (^onCacheChange)(void);
@property (nonatomic) NSUInteger maxConcurrent;
@property (nonatomic, readonly) NSUInteger activeCount;
@property (nonatomic, readonly) NSUInteger pendingCount;

/// Keeps this record until its own result arrives. No global/current-panel state is used.
/// Records must contain a nonempty question. State becomes waiting/loading/complete/failed.
- (void)enqueueRecord:(NSMutableDictionary *)record cacheKey:(NSString *)cacheKey;
@end

NS_ASSUME_NONNULL_END
