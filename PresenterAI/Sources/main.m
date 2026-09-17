#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <PDFKit/PDFKit.h>
#import <Security/Security.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#import <float.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <unistd.h>
#import "SCSpeechTimeline.h"
#import "SCAutoQuestionDetector.h"
#import "SCAnswerLane.h"
#import "SCUntimedTranscriptBuffer.h"
#import "SCAudioUtteranceBuffer.h"

static const NSTimeInterval SCAutoUtteranceSilence = 0.72;
static const NSTimeInterval SCAutoTurnSilence = 0.82;
static const NSTimeInterval SCAutoTurnSettle = 0.06;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property NSSecureTextField *keyField;
@property NSTextField *topicField;
@property NSTextView *transcriptView;
@property NSTextView *answerView;
@property NSTextView *currentAnswerView;
@property NSTextView *autoAnswerView;
@property NSTextView *autoHistoryView;
@property NSTextField *status;
@property NSButton *listenButton;
@property NSButton *commitButton;
@property NSButton *autoButton;
@property NSPopUpButton *languageButton;
@property NSPopUpButton *deviceButton;
@property NSArray<NSNumber *> *inputDeviceIDs;
@property NSTextField *levelLabel;
@property CFAbsoluteTime lastLevelUpdate;
@property AudioDeviceID originalInputDevice;
@property AVAudioEngine *audioEngine;
@property SFSpeechRecognizer *recognizer;
@property SFSpeechAudioBufferRecognitionRequest *speechRequest;
@property SFSpeechRecognitionTask *speechTask;
@property NSTimer *silenceTimer;
@property NSTimer *autoTimer;
@property NSString *latestTranscript;
@property NSString *autoTranscript;
@property NSString *autoPendingSnapshot;
@property NSTimeInterval autoPendingChangedAt;
@property NSString *speechCarry;
@property NSString *taskTranscript;
@property NSString *lastAsked;
@property NSString *lastAutoAsked;
@property BOOL listening;
@property BOOL requestInFlight;
@property BOOL autoRequestInFlight;
@property BOOL spaceCommitPending;
@property NSString *spaceTranscriptSnapshot;
@property NSString *knowledge;
@property NSString *answerPolicy;
@property NSArray<NSString *> *knowledgeNames;
@property NSUInteger processedTranscriptLength;
@property NSUInteger historyCount;
@property NSString *currentQuestion;
@property NSString *currentAnswer;
@property NSString *autoQuestion;
@property NSString *autoAnswer;
@property NSArray<NSDictionary *> *qaEntries;
@property NLEmbedding *englishEmbedding;
@property NSString *lastMatchedQuestion;
@property double lastMatchConfidence;
@property NSArray<NSDictionary *> *docChunks;
@property NSArray<NSDictionary *> *qaSearchEntries;
@property NSDictionary<NSString *,NSDictionary *> *exactQAMemory;
@property NSDictionary<NSString *,NSArray<NSDictionary *> *> *qaTermIndex;
@property NSArray<NSString *> *speechHints;
@property NSSet<NSString *> *speechLexicon;
@property NSMutableDictionary<NSString *,NSString *> *answerCache;
@property id spaceKeyMonitor;
@property SCSpeechTimeline *timeline; // SPACE only; AUTO owns a different instance.
@property SCAutoQuestionDetector *autoDetector;
@property SCUntimedTranscriptBuffer *manualUntimedBuffer;
@property BOOL hasUsableSpeechTiming;
@property BOOL manualUsesUntimed;
@property SCAnswerLane *manualAnswerLane;
@property SCAnswerLane *autoAnswerLane;
@property NSTextView *autoTranscriptView;
@property NSTextField *manualLiveLabel;
@property NSTextField *autoLiveLabel;
@property CFAbsoluteTime lastManualSnapshotChange;
@property BOOL manualSnapshotFinal;
@property NSTimeInterval audioTime;
@property NSTimeInterval lastVoiceAudioTime;
@property BOOL lastRecognitionWasFinal;
@property NSTimeInterval taskAudioStart;
@property NSTimeInterval manualCursor;
@property NSTimeInterval autoCursor;
@property NSTimeInterval pendingSpaceFrom;
@property NSTimeInterval pendingSpaceTo;
@property NSTimer *spaceSettleTimer;
@property NSTimer *spaceDeadlineTimer;
@property BOOL inputTapInstalled;
@property NSUInteger recognitionGeneration;
@property NSMutableArray<NSMutableDictionary *> *manualRecords;
@property NSMutableArray<NSMutableDictionary *> *autoRecords;
@property CGFloat readingFontSize;
@property NSTextField *readingSizeLabel;
@property NSButton *smallerTextButton;
@property NSButton *largerTextButton;
@property NSPopUpButton *moreButton;
@property NSScrollView *manualHistoryScroll;
@property NSScrollView *autoHistoryScroll;
@property NSLayoutConstraint *manualHistoryHeight;
@property NSLayoutConstraint *autoHistoryHeight;
@property NSButton *manualHistoryButton;
@property NSButton *autoHistoryButton;
@property NSDictionary *manualHistoryRenderState;
@property NSDictionary *autoHistoryRenderState;
@property NSInteger backdropStrength;
@property NSView *controlDock;
@property NSArray<NSMenuItem *> *backdropMenuItems;
@property SCAudioUtteranceBuffer *autoAudioBuffer;
@property SCUntimedTranscriptBuffer *enhancedAutoTranscriptBuffer;
@property NSMutableArray<NSDictionary *> *autoTranscriptionQueue;
@property BOOL autoTranscriptionInFlight;
@property BOOL autoEnhancedUnavailable;
@property NSMutableArray<NSString *> *autoTurnParts;
@property NSTimeInterval autoTurnChangedAt;
- (void)stageAutoQuestionTurnText:(NSString *)text;
- (void)flushAutoQuestionTurnIfReadyAt:(NSTimeInterval)now force:(BOOL)force;
- (NSArray<NSString *> *)questionPartsForSynthesis:(NSString *)question;
- (BOOL)questionPartsAreLinked:(NSArray<NSString *> *)parts;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [self buildMenu]; [self buildUI]; [self loadAudioDevices]; [self loadSavedAPIKey]; [self loadBundledKnowledge];
    __weak typeof(self) weakSelf=self;
    self.spaceKeyMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
      NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl;
      if (event.window == weakSelf.window && event.keyCode == 49 && (event.modifierFlags & blocked) == 0) {
        if (event.isARepeat) return nil;
        if ([event.window.firstResponder isKindOfClass:NSTextView.class] && [(NSTextView *)event.window.firstResponder isEditable]) return event;
        [weakSelf commitCurrentQuestionFromSpace];
        return nil;
      }
      return event;
    }];
    self.window.sharingType = NSWindowSharingNone;
    [NSApp activateIgnoringOtherApps:YES]; [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)hasVisibleWindows {
    (void)sender;
    if (!hasVisibleWindows) {
      [self.window deminiaturize:nil];
      [self.window makeKeyAndOrderFront:nil];
      [NSApp activateIgnoringOtherApps:YES];
    }
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return YES;
}

- (void)loadSavedAPIKey {
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:@"PresenterAI.openaiAPIKey.local.v1"];
    if (key.length) self.keyField.stringValue = key;
}

- (BOOL)saveAPIKeyToKeychain:(NSString *)key {
    if (!key.length) return NO;
    [[NSUserDefaults standardUserDefaults] setObject:key forKey:@"PresenterAI.openaiAPIKey.local.v1"];
    return [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)configureAI:(id)sender {
    NSAlert *alert=[NSAlert new]; alert.messageText=@"OpenAI API Key"; alert.informativeText=@"Key sẽ được lưu trong app settings trên máy này để không hiện lại hộp hỏi mật khẩu Keychain. Ứng dụng dùng dữ liệu SA Cook làm ngữ cảnh rồi nhờ ChatGPT tổng hợp câu trả lời tiếng Anh.";
    NSSecureTextField *field=[[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,0,360,24)]; field.placeholderString=@"sk-proj-…"; field.stringValue=self.keyField.stringValue ?: @""; alert.accessoryView=field;
    [alert addButtonWithTitle:@"Lưu"]; [alert addButtonWithTitle:@"Hủy"];
    if ([alert runModal]==NSAlertFirstButtonReturn) {
      NSString *clean=[[[field.stringValue componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]] componentsJoinedByString:@""];
      if(![clean hasPrefix:@"sk-"]){[self showUpdateAlert:@"Key không đúng định dạng" detail:@"OpenAI API key thường bắt đầu bằng sk- hoặc sk-proj-. Hãy tạo key tại platform.openai.com."];return;}
      [self validateAndSaveOpenAIKey:clean];
    }
}

- (void)validateAndSaveOpenAIKey:(NSString *)key {
    [self setStatus:@"Đang xác thực OpenAI key…" color:NSColor.systemOrangeColor];
    NSDictionary *body=@{@"model":@"gpt-4.1-mini",@"input":@"Reply OK",@"max_output_tokens":@16};NSData *data=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];req.HTTPMethod=@"POST";req.HTTPBody=data;[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){NSInteger code=[(NSHTTPURLResponse *)r statusCode];NSString *message=e.localizedDescription;if(d){id parsed=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if([parsed isKindOfClass:NSDictionary.class]){id errorObject=[(NSDictionary *)parsed objectForKey:@"error"];if([errorObject isKindOfClass:NSDictionary.class]){id apiMessage=[(NSDictionary *)errorObject objectForKey:@"message"];if([apiMessage isKindOfClass:NSString.class])message=apiMessage;}}}dispatch_async(dispatch_get_main_queue(),^{
      if(code>=200&&code<300){self.keyField.stringValue=key;if([self saveAPIKeyToKeychain:key])[self setStatus:@"✓ OpenAI key hợp lệ và đã lưu trong app" color:NSColor.systemGreenColor];return;}
      NSString *title=nil;if(code==401)title=@"OpenAI key không hợp lệ";else if(code==403)title=@"Key không có quyền dùng model";else if(code==404)title=@"Model OpenAI không khả dụng";else if(code==429)title=@"OpenAI API hết quota hoặc bị giới hạn";else title=@"Không thể kết nối OpenAI";
      if(code!=401&&key.length){self.keyField.stringValue=key;[self saveAPIKeyToKeychain:key];}
      [self setStatus:title color:NSColor.systemRedColor];[self showUpdateAlert:title detail:[NSString stringWithFormat:@"HTTP %ld: %@",(long)code,message?:@"Không có phản hồi từ OpenAI"]];
    });}] resume];
}

- (void)showUpdateAlert:(NSString *)title detail:(NSString *)detail {
    NSAlert *alert=[NSAlert new];alert.messageText=title;alert.informativeText=detail;[alert addButtonWithTitle:@"OK"];[alert runModal];
}

- (NSArray<NSNumber *> *)semanticVersionParts:(NSString *)version {
    NSString *clean=[version stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *expression=[NSRegularExpression regularExpressionWithPattern:@"^[vV]?(\\d+)\\.(\\d+)(?:\\.(\\d+))?$" options:0 error:nil];
    NSTextCheckingResult *match=[expression firstMatchInString:clean options:0 range:NSMakeRange(0,clean.length)];
    if(!match) return nil;
    NSMutableArray<NSNumber *> *parts=[NSMutableArray arrayWithCapacity:3];
    for(NSUInteger index=1;index<=3;index++) {
      NSRange range=[match rangeAtIndex:index];
      [parts addObject:@(range.location==NSNotFound?0:[[clean substringWithRange:range] integerValue])];
    }
    return parts;
}

- (NSComparisonResult)compareSemanticVersion:(NSString *)left to:(NSString *)right {
    NSArray<NSNumber *> *a=[self semanticVersionParts:left],*b=[self semanticVersionParts:right];
    if(!a || !b) return NSOrderedSame;
    for(NSUInteger index=0;index<3;index++) {
      NSInteger av=a[index].integerValue,bv=b[index].integerValue;
      if(av<bv) return NSOrderedAscending;
      if(av>bv) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

- (NSString *)canonicalSemanticVersion:(NSString *)version {
    NSArray<NSNumber *> *parts=[self semanticVersionParts:version];
    return parts?[NSString stringWithFormat:@"%ld.%ld.%ld",(long)parts[0].integerValue,(long)parts[1].integerValue,(long)parts[2].integerValue]:nil;
}

- (NSString *)macOSVersionFromArchiveName:(NSString *)name preferred:(BOOL *)preferred {
    NSArray<NSString *> *patterns=@[@"^SA-Cook-Assistant-macOS-v(\\d+\\.\\d+\\.\\d+)\\.zip$",@"^SA-Cook-Assistant-v(\\d+\\.\\d+(?:\\.\\d+)?)\\.zip$"];
    for(NSUInteger index=0;index<patterns.count;index++) {
      NSRegularExpression *expression=[NSRegularExpression regularExpressionWithPattern:patterns[index] options:0 error:nil];
      NSTextCheckingResult *match=[expression firstMatchInString:name options:0 range:NSMakeRange(0,name.length)];
      if(match) {
        if(preferred) *preferred=index==0;
        return [name substringWithRange:[match rangeAtIndex:1]];
      }
    }
    return nil;
}

- (NSDictionary *)macOSAssetInRelease:(NSDictionary *)release version:(NSString *)tagVersion {
    NSString *canonical=[self canonicalSemanticVersion:tagVersion];
    if(!canonical) return nil;
    NSString *cleanTag=[tagVersion stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([cleanTag hasPrefix:@"v"] || [cleanTag hasPrefix:@"V"]) cleanTag=[cleanTag substringFromIndex:1];
    NSString *preferred=[NSString stringWithFormat:@"SA-Cook-Assistant-macOS-v%@.zip",canonical];
    NSString *legacy=[NSString stringWithFormat:@"SA-Cook-Assistant-v%@.zip",cleanTag];
    NSArray *assets=[release[@"assets"] isKindOfClass:NSArray.class]?release[@"assets"]:@[];
    for(NSString *expected in @[preferred,legacy]) for(NSDictionary *asset in assets) {
      NSString *name=[asset[@"name"] isKindOfClass:NSString.class]?asset[@"name"]:@"";
      NSString *download=[asset[@"browser_download_url"] isKindOfClass:NSString.class]?asset[@"browser_download_url"]:@"";
      if([name isEqualToString:expected] && download.length) return asset;
    }
    return nil;
}

- (void)checkForUpdates:(id)sender {
    NSString *current=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"0";
    NSString *updatesPath=@"/Users/trunghuy/Documents/Codex/2026-07-05/to/outputs";
    NSString *bestVersion=nil,*bestFile=nil; BOOL bestPreferred=NO;
    for(NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:updatesPath error:nil]){
      BOOL preferred=NO; NSString *version=[self macOSVersionFromArchiveName:name preferred:&preferred];
      if(!version || [self compareSemanticVersion:version to:current]!=NSOrderedDescending) continue;
      NSComparisonResult order=bestVersion?[self compareSemanticVersion:version to:bestVersion]:NSOrderedDescending;
      if(order==NSOrderedDescending || (order==NSOrderedSame && preferred && !bestPreferred)) {bestVersion=version;bestFile=[updatesPath stringByAppendingPathComponent:name];bestPreferred=preferred;}
    }
    if(bestFile){
      NSAlert *confirm=[NSAlert new];confirm.messageText=[NSString stringWithFormat:@"Cập nhật lên %@?",bestVersion];confirm.informativeText=@"Ứng dụng sẽ tự thay thế và mở lại. Bạn không cần tải file.";[confirm addButtonWithTitle:@"Update"];[confirm addButtonWithTitle:@"Hủy"];
      if([confirm runModal]==NSAlertFirstButtonReturn)[self downloadAndInstallUpdate:[NSURL fileURLWithPath:bestFile] version:bestVersion];return;
    }
    [self setStatus:@"Đang kiểm tra bản cập nhật…" color:NSColor.systemOrangeColor];
    NSURL *url=[NSURL URLWithString:@"https://api.github.com/repos/belong0205-cmyk/sacook/releases/latest"];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:url];[request setValue:@"SA-Cook-Assistant" forHTTPHeaderField:@"User-Agent"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
      NSDictionary *release=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;NSInteger code=[(NSHTTPURLResponse *)response statusCode];
      dispatch_async(dispatch_get_main_queue(),^{
        if(error||code!=200||!release[@"tag_name"]){[self setStatus:@"Chưa tìm thấy GitHub Release" color:NSColor.systemOrangeColor];[self showUpdateAlert:@"Chưa có bản cập nhật" detail:@"Hãy tạo một Release trong repository belong0205-cmyk/sacook và đính kèm file ZIP của ứng dụng."];return;}
        NSString *tag=[release[@"tag_name"] isKindOfClass:NSString.class]?release[@"tag_name"]:@"";
        NSString *latest=[self canonicalSemanticVersion:tag];
        if(!latest){[self setStatus:@"Release có phiên bản không hợp lệ" color:NSColor.systemOrangeColor];[self showUpdateAlert:@"Không thể đọc phiên bản" detail:@"Stable release phải dùng tag vX.Y hoặc vX.Y.Z."];return;}
        if([self compareSemanticVersion:latest to:current]!=NSOrderedDescending){[self setStatus:@"✓ Ứng dụng đang ở bản mới nhất" color:NSColor.systemGreenColor];[self showUpdateAlert:@"Đã cập nhật" detail:[NSString stringWithFormat:@"Bạn đang dùng phiên bản %@.",current]];return;}
        NSDictionary *asset=[self macOSAssetInRelease:release version:tag];
        NSURL *assetURL=[NSURL URLWithString:[asset[@"browser_download_url"] isKindOfClass:NSString.class]?asset[@"browser_download_url"]:@""];
        if(!assetURL){[self showUpdateAlert:@"Release thiếu file macOS" detail:[NSString stringWithFormat:@"Release %@ cần đúng file SA-Cook-Assistant-macOS-v%@.zip (hoặc tên macOS cũ khớp chính xác).",latest,latest]];return;}
        NSAlert *confirm=[NSAlert new];confirm.messageText=[NSString stringWithFormat:@"Cập nhật lên %@?",latest];confirm.informativeText=@"Ứng dụng sẽ tải bản mới, tự thay thế rồi mở lại.";[confirm addButtonWithTitle:@"Update"];[confirm addButtonWithTitle:@"Hủy"];
        if([confirm runModal]==NSAlertFirstButtonReturn)[self downloadAndInstallUpdate:assetURL version:latest];
      });
    }] resume];
}

- (void)downloadAndInstallUpdate:(NSURL *)url version:(NSString *)version {
    [self setStatus:url.isFileURL?@"Đang cài bản cập nhật…":@"Đang tải bản cập nhật…" color:NSColor.systemOrangeColor];
    void (^install)(NSURL *,NSError *)=^(NSURL *location,NSError *error){
      if(error){dispatch_async(dispatch_get_main_queue(),^{[self showUpdateAlert:@"Tải thất bại" detail:error.localizedDescription];});return;}
      NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];NSString *zip=[root stringByAppendingPathComponent:@"update.zip"];NSString *expanded=[root stringByAppendingPathComponent:@"expanded"];
      NSError *copyError=nil;[[NSFileManager defaultManager] createDirectoryAtPath:expanded withIntermediateDirectories:YES attributes:nil error:nil];[[NSFileManager defaultManager] copyItemAtURL:location toURL:[NSURL fileURLWithPath:zip] error:&copyError];if(copyError){dispatch_async(dispatch_get_main_queue(),^{[self showUpdateAlert:@"Không thể chuẩn bị bản cập nhật" detail:copyError.localizedDescription];});return;}
      NSTask *ditto=[NSTask new];ditto.executableURL=[NSURL fileURLWithPath:@"/usr/bin/ditto"];ditto.arguments=@[@"-x",@"-k",zip,expanded];[ditto launchAndReturnError:nil];[ditto waitUntilExit];
      NSDirectoryEnumerator *files=[[NSFileManager defaultManager] enumeratorAtPath:expanded];NSString *relative=nil,*item;while((item=[files nextObject]))if([item.pathExtension.lowercaseString isEqualToString:@"app"]){relative=item;[files skipDescendants];break;}
      NSString *newApp=relative?[expanded stringByAppendingPathComponent:relative]:nil;NSBundle *bundle=newApp?[NSBundle bundleWithPath:newApp]:nil;
      if(![bundle.bundleIdentifier isEqualToString:@"local.codex.PresenterAI"]){dispatch_async(dispatch_get_main_queue(),^{[self showUpdateAlert:@"Bản cập nhật không hợp lệ" detail:@"File tải về không phải SA Cook Assistant."];});return;}
      NSString *script=[root stringByAppendingPathComponent:@"install-update.sh"];NSString *body=@"#!/bin/sh\nwhile kill -0 \"$3\" 2>/dev/null; do sleep 1; done\nrm -rf \"$1.old\"\nmv \"$1\" \"$1.old\" || exit 1\nif cp -R \"$2\" \"$1\"; then open \"$1\"; rm -rf \"$1.old\"; else mv \"$1.old\" \"$1\"; fi\n";[body writeToFile:script atomically:YES encoding:NSUTF8StringEncoding error:nil];[[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0755} ofItemAtPath:script error:nil];
      dispatch_async(dispatch_get_main_queue(),^{NSTask *helper=[NSTask new];helper.executableURL=[NSURL fileURLWithPath:@"/bin/sh"];helper.arguments=@[script,[NSBundle mainBundle].bundlePath,newApp,[NSString stringWithFormat:@"%d",getpid()]];[helper launchAndReturnError:nil];[NSApp terminate:nil];});
    };
    if(url.isFileURL)dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{install(url,nil);});
    else [[[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location,NSURLResponse *response,NSError *error){install(location,error);}] resume];
}

- (NSString *)knowledgeResourcePath:(NSString *)name extension:(NSString *)extension {
    return [[NSBundle mainBundle] pathForResource:name ofType:extension];
}
- (void)loadBundledKnowledge {
    NSString *policyPath=[self knowledgeResourcePath:@"answer-policy" extension:@"txt"];
    NSString *policy=policyPath?[NSString stringWithContentsOfFile:policyPath encoding:NSUTF8StringEncoding error:nil]:nil;
    self.answerPolicy=[policy stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *path = [self knowledgeResourcePath:@"sa-cook-knowledge" extension:@"txt"];
    if (!path) return;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return;
    self.knowledge = text; self.knowledgeNames = @[@"SA Cook Study"];
    NSString *qaPath=[self knowledgeResourcePath:@"sa-cook-qa" extension:@"json"];
    NSData *qaData=qaPath?[NSData dataWithContentsOfFile:qaPath]:nil; if (qaData) self.qaEntries=[NSJSONSerialization JSONObjectWithData:qaData options:0 error:nil];
    NSMutableArray *qa=[self.qaEntries mutableCopy]?:[NSMutableArray array];
    NSString *internetPath=[self knowledgeResourcePath:@"internet-qa" extension:@"json"];NSData *internetData=internetPath?[NSData dataWithContentsOfFile:internetPath]:nil;id internetQA=internetData?[NSJSONSerialization JSONObjectWithData:internetData options:0 error:nil]:nil;if([internetQA isKindOfClass:NSArray.class])[qa addObjectsFromArray:internetQA];
    NSString *hintsPath=[self knowledgeResourcePath:@"speech-hints" extension:@"txt"];NSString *hints=hintsPath?[NSString stringWithContentsOfFile:hintsPath encoding:NSUTF8StringEncoding error:nil]:nil;if(hints.length){NSMutableArray *items=[NSMutableArray array];for(NSString *line in [hints componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *item=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(item.length)[items addObject:item];}self.speechHints=items;self.speechLexicon=nil;}
    [qa addObject:@{@"question":@"List three ways people may define their cultural identity.",@"answer":@"People may define their cultural identity through their ethnicity or nationality, their language and traditions, and their religion or beliefs."}];
    [qa addObject:@{@"question":@"In what ways can problems or misunderstandings with customers or colleagues from different cultural backgrounds be avoided?",@"answer":@"I avoid misunderstandings by communicating clearly and respectfully, listening actively, asking polite clarifying questions, avoiding assumptions or stereotypes, and showing cultural awareness and empathy."}];
    [qa addObject:@{@"question":@"What is the difference between cleaning and sanitising?",@"answer":@"Cleaning removes dirt, grease and food residue, while sanitising reduces harmful bacteria to a safe level; I always clean first, then sanitise."}];
    [qa addObject:@{@"question":@"Give one example of preparing Mise en Place for a poultry, seafood or sandwich dish.",@"answer":@"For grilled chicken breast, my mise en place is to trim and portion the chicken, marinate it, blanch the vegetables, prepare the sauce and garnish, and set out the pan, tongs and thermometer before service."}];
    [qa addObject:@{@"question":@"Which knife is the most versatile for slicing, chopping and dicing?",@"answer":@"The chef's knife is the most versatile knife for slicing, chopping and dicing."}];
    [qa addObject:@{@"question":@"What knife is best for cutting julienne or vegetables?",@"answer":@"A chef's knife is best for cutting vegetables and making julienne cuts."}];
    self.qaEntries=qa;
    NSMutableArray *search=[NSMutableArray array];NSMutableDictionary *exact=[NSMutableDictionary dictionary],*termIndex=[NSMutableDictionary dictionary];
    for(NSDictionary *entry in self.qaEntries){NSString *question=entry[@"question"]?:@"",*blob=[NSString stringWithFormat:@"%@ %@",question,entry[@"answer"]?:@""];NSSet *qterms=[self contentTerms:question];NSString *normal=[self normalisedQuestion:question];NSDictionary *searchEntry=@{@"entry":entry,@"terms":[self contentTerms:blob],@"qterms":qterms,@"normal":normal};[search addObject:searchEntry];if(normal.length)exact[normal]=entry;
      for(NSString *term in qterms){NSMutableArray *bucket=termIndex[term];if(!bucket){bucket=[NSMutableArray array];termIndex[term]=bucket;}[bucket addObject:searchEntry];}
      for(NSString *part in [question componentsSeparatedByString:@"?"]){NSString *clean=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if([self contentTerms:clean].count>=2){NSString *alias=[self normalisedQuestion:clean];if(alias.length&&!exact[alias])exact[alias]=entry;}}
    }
    self.qaSearchEntries=search;self.exactQAMemory=exact;self.qaTermIndex=termIndex;
    [self ensureAnswerState];
    // v15 drops shorter B1-era answers so both lanes use the richer B2 policy.
    NSDictionary *savedManual=[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"PresenterAI.answerCache.manual.v16"];
    NSDictionary *savedAuto=[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"PresenterAI.answerCache.auto.v16"];
    self.manualAnswerLane.cache=[savedManual mutableCopy] ?: [NSMutableDictionary dictionary];
    self.autoAnswerLane.cache=[savedAuto mutableCopy] ?: [NSMutableDictionary dictionary];
    // No unused embedding model is loaded on startup.
    NSString *handbookPath=[self knowledgeResourcePath:@"sa-cook-handbook" extension:@"txt"];
    NSString *handbook=handbookPath?[NSString stringWithContentsOfFile:handbookPath encoding:NSUTF8StringEncoding error:nil]:nil;
    if(handbook.length){NSMutableArray *chunks=[NSMutableArray array];NSMutableString *buffer=[NSMutableString string];for(NSString *line in [handbook componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *clean=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!clean.length)continue;[buffer appendFormat:@"%@ ",clean];if(buffer.length>=600){[chunks addObject:@{@"text":buffer.copy,@"terms":[self contentTerms:buffer]}];[buffer setString:@""];}}if(buffer.length)[chunks addObject:@{@"text":buffer.copy,@"terms":[self contentTerms:buffer]}];self.docChunks=chunks;}
    [self setStatus:[NSString stringWithFormat:@"✓ Bộ nhớ sẵn sàng • %lu câu • %lu biến thể • %lu thuật ngữ nghe",(unsigned long)self.qaEntries.count,(unsigned long)self.exactQAMemory.count,(unsigned long)self.speechHints.count] color:NSColor.systemGreenColor];
    self.topicField.stringValue = @"Phỏng vấn đánh giá kỹ năng nghề Cook/Chef, trả lời theo bộ SA Cook Study";
}
- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *v = [NSTextField labelWithString:text];
    v.font = [NSFont systemFontOfSize:size weight:weight]; v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}
- (NSInteger)initialBackdropStrength {
    NSNumber *saved=[[NSUserDefaults standardUserDefaults] objectForKey:@"PresenterAI.backdropStrength.v1"];
    NSInteger value=saved.integerValue;
    return saved && value>=0 && value<=2 ? value : 1;
}
- (CGFloat)readingSurfaceAlpha {
    return self.backdropStrength==0?0.14:(self.backdropStrength==2?0.46:0.28);
}
- (CGFloat)rootBackdropAlpha {
    return 0.02;
}
- (CGFloat)dockBackdropAlpha {
    return 0.10;
}
- (NSColor *)readingSurfaceColor {
    // The plain window has no system blur. This local veil is adjustable and
    // supports text while leaving the presentation visible behind it.
    return [NSColor colorWithWhite:0.015 alpha:[self readingSurfaceAlpha]];
}
- (void)refreshBackdropAppearance {
    self.window.contentView.layer.backgroundColor=[NSColor colorWithWhite:0 alpha:[self rootBackdropAlpha]].CGColor;
    self.controlDock.layer.backgroundColor=[NSColor colorWithWhite:0.025 alpha:[self dockBackdropAlpha]].CGColor;
    for(NSTextView *text in @[self.currentAnswerView ?: (id)NSNull.null,self.autoAnswerView ?: (id)NSNull.null,self.transcriptView ?: (id)NSNull.null,self.autoTranscriptView ?: (id)NSNull.null,self.answerView ?: (id)NSNull.null,self.autoHistoryView ?: (id)NSNull.null])
      if([text isKindOfClass:NSTextView.class]) { text.backgroundColor=[self readingSurfaceColor]; [text setNeedsDisplay:YES]; }
    for(NSMenuItem *item in self.backdropMenuItems) item.state=item.tag==self.backdropStrength?NSControlStateValueOn:NSControlStateValueOff;
    [self.window.contentView setNeedsDisplay:YES]; [self.controlDock setNeedsDisplay:YES];
}
- (void)changeBackdropStrength:(NSMenuItem *)sender {
    self.backdropStrength=MAX(0,MIN(2,sender.tag));
    [[NSUserDefaults standardUserDefaults] setInteger:self.backdropStrength forKey:@"PresenterAI.backdropStrength.v1"];
    [self refreshBackdropAppearance];
}
- (NSColor *)laneAccent:(BOOL)automatic {
    return automatic ? [NSColor colorWithRed:0.67 green:0.55 blue:0.98 alpha:1] : [NSColor colorWithRed:0.37 green:0.91 blue:0.82 alpha:1];
}
- (NSButton *)readingButton:(NSString *)title action:(SEL)action {
    NSButton *button=[NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints=NO;
    button.bordered=NO; button.wantsLayer=YES;
    button.layer.cornerRadius=9; button.layer.borderWidth=1;
    button.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:0.075].CGColor;
    button.layer.borderColor=[NSColor colorWithWhite:1 alpha:0.11].CGColor;
    button.contentTintColor=[NSColor colorWithWhite:0.93 alpha:1];
    button.font=[NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    return button;
}
- (NSMenuItem *)secondaryMenuItem:(NSString *)title action:(SEL)action tag:(NSInteger)tag {
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target=self; item.tag=tag; return item;
}
- (NSScrollView *)textBox:(NSTextView **)out editable:(BOOL)editable {
    NSScrollView *scroll=[NSScrollView new]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.hasVerticalScroller=YES; scroll.autohidesScrollers=YES; scroll.hasHorizontalScroller=NO;
    scroll.scrollerStyle=NSScrollerStyleOverlay; scroll.verticalScrollElasticity=NSScrollElasticityAllowed;
    scroll.borderType=NSNoBorder; scroll.wantsLayer=YES;
    scroll.layer.cornerRadius=14; scroll.layer.masksToBounds=YES;
    scroll.layer.borderWidth=0;
    // One translucent layer is enough. Previously both the scroll view and
    // text view painted the same black tint, making each lane look heavy.
    scroll.drawsBackground=NO; scroll.backgroundColor=NSColor.clearColor;
    scroll.contentView.drawsBackground=NO; scroll.contentView.backgroundColor=NSColor.clearColor;
    NSTextView *text=[[NSTextView alloc] initWithFrame:NSMakeRect(0,0,400,100)];
    text.editable=editable; text.selectable=YES; text.richText=NO;
    text.automaticLinkDetectionEnabled=YES;
    text.verticallyResizable=YES; text.horizontallyResizable=NO;
    text.minSize=NSMakeSize(0,0); text.maxSize=NSMakeSize(CGFLOAT_MAX,CGFLOAT_MAX);
    text.autoresizingMask=NSViewWidthSizable;
    text.textContainer.containerSize=NSMakeSize(400,CGFLOAT_MAX);
    text.textContainer.widthTracksTextView=YES;
    text.font=[NSFont systemFontOfSize:16]; text.textContainerInset=NSMakeSize(14,12);
    text.drawsBackground=YES; text.backgroundColor=[self readingSurfaceColor];
    text.textColor=[NSColor colorWithWhite:0.94 alpha:1]; text.insertionPointColor=NSColor.whiteColor;
    NSMenu *selectionMenu=[NSMenu new];
    NSMenuItem *copy=[selectionMenu addItemWithTitle:@"Sao chép" action:@selector(copy:) keyEquivalent:@""]; copy.target=nil;
    NSMenuItem *selectAll=[selectionMenu addItemWithTitle:@"Chọn tất cả" action:@selector(selectAll:) keyEquivalent:@""]; selectAll.target=nil;
    text.menu=selectionMenu;
    scroll.documentView=text; *out=text; return scroll;
}
- (NSView *)buildReadingLane:(BOOL)automatic {
    NSColor *accent=[self laneAccent:automatic];
    NSView *card=[NSView new]; card.translatesAutoresizingMaskIntoConstraints=NO; card.wantsLayer=YES;
    card.layer.backgroundColor=NSColor.clearColor.CGColor;
    card.layer.cornerRadius=18; card.layer.borderWidth=0;
    card.layer.shadowOpacity=0;
    card.identifier=automatic?@"autoConversationLane":@"spaceConversationLane";
    card.accessibilityLabel=automatic?@"AUTO — independent automatic answers":@"SPACE — independent manual answers";
    NSTextView *answer=nil,*transcript=nil,*history=nil;
    NSScrollView *answerScroll=[self textBox:&answer editable:NO];
    answer.textContainerInset=NSMakeSize(14,10);
    answer.accessibilityLabel=automatic?@"AUTO complete conversation":@"SPACE complete conversation";
    NSScrollView *liveScroll=[self textBox:&transcript editable:NO];
    transcript.font=[NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
    transcript.textColor=[NSColor colorWithWhite:0.82 alpha:1];
    transcript.textContainerInset=NSMakeSize(12,8);
    transcript.string=automatic?@"Câu AUTO đang nghe sẽ hiện ở đây.":@"Nghe hết câu hỏi, rồi bấm Space.";
    transcript.accessibilityLabel=automatic?@"AUTO live transcript":@"SPACE live transcript";
    NSTextField *liveLabel=[self label:automatic?@"Đang nghe tự động":@"Bản chép trực tiếp" size:11 weight:NSFontWeightMedium];
    liveLabel.textColor=accent; liveLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    [liveLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    NSScrollView *historyScroll=[self textBox:&history editable:NO];
    history.textContainerInset=NSMakeSize(14,12);
    history.accessibilityLabel=automatic?@"AUTO answer history":@"SPACE answer history";
    history.string=@"No previous conversation yet.";
    historyScroll.hidden=YES; liveScroll.hidden=YES;
    NSLayoutConstraint *historyHeight=[historyScroll.heightAnchor constraintEqualToConstant:0];
    NSButton *historyButton=nil;
    if(automatic) {
        self.autoAnswerView=answer; self.autoTranscriptView=transcript; self.autoHistoryView=history;
        self.autoLiveLabel=liveLabel; self.autoHistoryScroll=historyScroll; self.autoHistoryHeight=historyHeight; self.autoHistoryButton=historyButton;
    } else {
        self.currentAnswerView=answer; self.transcriptView=transcript; self.answerView=history;
        self.manualLiveLabel=liveLabel; self.manualHistoryScroll=historyScroll; self.manualHistoryHeight=historyHeight; self.manualHistoryButton=historyButton;
    }
    // Transcript, current answer, and previous turns are rendered into this
    // single scrolling surface. The backing transcript/history views above
    // remain state holders only and are deliberately not shown as extra boxes.
    [card addSubview:answerScroll];
    [NSLayoutConstraint activateConstraints:@[
        [answerScroll.topAnchor constraintEqualToAnchor:card.topAnchor],[answerScroll.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8],
        [answerScroll.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8],[answerScroll.bottomAnchor constraintEqualToAnchor:card.bottomAnchor]
    ]];
    return card;
}
- (void)toggleReadingHistory:(NSButton *)sender {
    BOOL automatic=sender.tag==1;
    NSScrollView *scroll=automatic?self.autoHistoryScroll:self.manualHistoryScroll;
    NSLayoutConstraint *height=automatic?self.autoHistoryHeight:self.manualHistoryHeight;
    BOOL open=scroll.hidden; scroll.hidden=!open; height.constant=open?185:0;
    [self updateReadingHistoryButton:automatic];
    [self.window.contentView layoutSubtreeIfNeeded];
}
- (void)updateReadingHistoryButton:(BOOL)automatic {
    NSButton *button=automatic?self.autoHistoryButton:self.manualHistoryButton;
    NSScrollView *scroll=automatic?self.autoHistoryScroll:self.manualHistoryScroll;
    NSArray *records=automatic?self.autoRecords:self.manualRecords;
    NSUInteger count=records.count>1?MIN((NSUInteger)50,records.count-1):0;
    button.title=[NSString stringWithFormat:@"%@  Previous · %lu",scroll.hidden?@"▸":@"▾",(unsigned long)count];
    button.accessibilityLabel=[NSString stringWithFormat:@"%@ lịch sử %@",scroll.hidden?@"Mở":@"Thu",automatic?@"AUTO":@"SPACE"];
}
- (CGFloat)effectiveReadingFontSize {
    return self.readingFontSize>=20?MIN(self.readingFontSize,40):20;
}
- (void)changeReadingFont:(NSButton *)sender {
    self.readingFontSize=MAX(20,MIN(40,[self effectiveReadingFontSize]+sender.tag*2));
    [[NSUserDefaults standardUserDefaults] setDouble:self.readingFontSize forKey:@"PresenterAI.readingFontSize.v2"];
    [self refreshReadingTypography];
}
- (void)refreshReadingTypography {
    CGFloat size=[self effectiveReadingFontSize];
    self.readingSizeLabel.stringValue=[NSString stringWithFormat:@"%.0f pt",size];
    self.smallerTextButton.enabled=size>20; self.largerTextButton.enabled=size<40;
    [self showCurrentQuestion:self.currentQuestion answer:self.currentAnswer.length?self.currentAnswer:@"Press Space after the question.\nYour answer will appear here."];
    [self showAutoQuestion:self.autoQuestion answer:self.autoAnswer.length?self.autoAnswer:@""];
    [self renderHistoryRecords:self.manualRecords inView:self.answerView];
    [self renderHistoryRecords:self.autoRecords inView:self.autoHistoryView];
}
- (void)buildUI {
    self.readingFontSize=[[NSUserDefaults standardUserDefaults] doubleForKey:@"PresenterAI.readingFontSize.v2"];
    self.backdropStrength=[self initialBackdropStrength];
    self.window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1080,700)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"SA Cook Assistant"; self.window.contentMinSize=NSMakeSize(900,600);
    self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    self.window.titleVisibility=NSWindowTitleHidden; self.window.titlebarAppearsTransparent=YES;
    self.window.movableByWindowBackground=YES; self.window.opaque=NO; self.window.alphaValue=1.0; self.window.backgroundColor=NSColor.clearColor; self.window.hasShadow=YES;
    self.window.level=NSFloatingWindowLevel;
    self.window.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    [self.window center];
    // NSVisualEffectView keeps painting a dark system material even when its
    // layer colour is nearly clear. Use a plain layer-backed view for a truly
    // see-through overlay instead of a frosted/blurred sheet.
    NSView *root=[NSView new]; self.window.contentView=root;
    root.wantsLayer=YES; root.layer.backgroundColor=[NSColor colorWithWhite:0 alpha:[self rootBackdropAlpha]].CGColor; root.layer.cornerRadius=20; root.layer.masksToBounds=YES;
    root.layer.borderWidth=0;
    NSString *version=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"5.47";
    self.keyField=[NSSecureTextField new]; self.topicField=[NSTextField new];
    self.languageButton=[NSPopUpButton new]; [self.languageButton addItemWithTitle:@"English (Australia)"];
    self.listenButton=[self readingButton:@"Bắt đầu nghe" action:@selector(toggleListening:)];
    self.listenButton.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.listenButton.layer.backgroundColor=[NSColor colorWithRed:0.18 green:0.75 blue:0.55 alpha:0.22].CGColor;
    self.listenButton.layer.borderColor=[NSColor colorWithRed:0.30 green:0.92 blue:0.69 alpha:0.40].CGColor;
    self.deviceButton=[NSPopUpButton new]; self.deviceButton.translatesAutoresizingMaskIntoConstraints=NO; self.deviceButton.font=[NSFont systemFontOfSize:13];
    self.deviceButton.toolTip=@"Chọn nguồn âm thanh — BlackHole để nghe âm thanh máy tính";
    self.deviceButton.accessibilityLabel=@"Nguồn âm thanh";
    self.commitButton=[self readingButton:@"Chốt câu" action:@selector(commitCurrentQuestionFromSpace)];
    self.commitButton.font=[NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.commitButton.layer.backgroundColor=[[self laneAccent:NO] colorWithAlphaComponent:0.16].CGColor;
    self.commitButton.layer.borderColor=[[self laneAccent:NO] colorWithAlphaComponent:0.35].CGColor;
    self.commitButton.toolTip=@"Bấm Space khi người nói kết thúc câu hỏi";
    self.autoButton=[NSButton checkboxWithTitle:@"AUTO" target:self action:@selector(toggleAutoRecognition:)];
    self.autoButton.translatesAutoresizingMaskIntoConstraints=NO; self.autoButton.state=NSControlStateValueOn; self.autoButton.font=[NSFont systemFontOfSize:13];
    self.status=[self label:@"● Sẵn sàng" size:12 weight:NSFontWeightMedium]; self.status.textColor=[NSColor colorWithWhite:0.80 alpha:1];
    self.status.lineBreakMode=NSLineBreakByTruncatingTail; [self.status setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    self.levelLabel=[self label:@"Chưa có âm thanh" size:12 weight:NSFontWeightMedium]; self.levelLabel.alignment=NSTextAlignmentRight; self.levelLabel.textColor=[NSColor colorWithWhite:0.76 alpha:1];
    self.levelLabel.lineBreakMode=NSLineBreakByTruncatingTail;
    self.moreButton=[[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
    self.moreButton.translatesAutoresizingMaskIntoConstraints=NO; self.moreButton.bordered=NO; self.moreButton.font=[NSFont systemFontOfSize:14 weight:NSFontWeightBold];
    self.moreButton.wantsLayer=YES; self.moreButton.layer.cornerRadius=9; self.moreButton.layer.backgroundColor=[NSColor colorWithWhite:1 alpha:0.075].CGColor;
    self.moreButton.identifier=@"secondaryActionsMenu"; self.moreButton.accessibilityLabel=@"Tuỳ chọn khác"; self.moreButton.toolTip=@"Độ nền, cỡ chữ, trả lời lại, xoá lịch sử, AI và cập nhật";
    [self.moreButton addItemWithTitle:@"•••"];
    NSMenu *secondary=self.moreButton.menu;
    NSMenuItem *about=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"SA Cook Assistant · v%@",version] action:nil keyEquivalent:@""]; about.enabled=NO; [secondary addItem:about];
    [secondary addItem:[NSMenuItem separatorItem]];
    NSMenuItem *smaller=[self secondaryMenuItem:@"Chữ nhỏ hơn" action:@selector(changeReadingFont:) tag:-1]; smaller.keyEquivalent=@"-"; [secondary addItem:smaller];
    NSMenuItem *larger=[self secondaryMenuItem:@"Chữ lớn hơn" action:@selector(changeReadingFont:) tag:1]; larger.keyEquivalent=@"="; [secondary addItem:larger];
    [secondary addItem:[NSMenuItem separatorItem]];
    NSMenuItem *backdropRoot=[[NSMenuItem alloc] initWithTitle:@"Độ nền" action:nil keyEquivalent:@""]; NSMenu *backdropMenu=[[NSMenu alloc] initWithTitle:@"Độ nền"];
    NSMutableArray<NSMenuItem *> *backdropItems=[NSMutableArray array];
    for(NSUInteger i=0;i<3;i++) {
      NSMenuItem *item=[self secondaryMenuItem:@[@"Trong – thấy nền rõ",@"Cân bằng",@"Đậm – chữ rõ hơn"][i] action:@selector(changeBackdropStrength:) tag:(NSInteger)i];
      [backdropMenu addItem:item]; [backdropItems addObject:item];
    }
    backdropRoot.submenu=backdropMenu; self.backdropMenuItems=backdropItems; [secondary addItem:backdropRoot];
    [secondary addItem:[NSMenuItem separatorItem]];
    [secondary addItem:[self secondaryMenuItem:@"Sao chép khung AUTO" action:@selector(copyAutoConversation:) tag:0]];
    [secondary addItem:[self secondaryMenuItem:@"Sao chép khung SPACE" action:@selector(copyManualConversation:) tag:0]];
    [secondary addItem:[NSMenuItem separatorItem]];
    [secondary addItem:[self secondaryMenuItem:@"Trả lời lại AUTO" action:@selector(retryAutoAnswer:) tag:0]];
    [secondary addItem:[self secondaryMenuItem:@"Trả lời lại SPACE" action:@selector(retryManualAnswer:) tag:0]];
    [secondary addItem:[NSMenuItem separatorItem]];
    [secondary addItem:[self secondaryMenuItem:@"Xoá lịch sử AUTO" action:@selector(clearAutoHistory:) tag:0]];
    [secondary addItem:[self secondaryMenuItem:@"Xoá lịch sử SPACE" action:@selector(clearManualHistory:) tag:0]];
    [secondary addItem:[NSMenuItem separatorItem]];
    [secondary addItem:[self secondaryMenuItem:@"Cài đặt OpenAI…" action:@selector(configureAI:) tag:0]];
    [secondary addItem:[self secondaryMenuItem:@"Kiểm tra cập nhật…" action:@selector(checkForUpdates:) tag:0]];
    NSView *automatic=[self buildReadingLane:YES],*manual=[self buildReadingLane:NO];
    NSView *dock=[NSView new]; dock.translatesAutoresizingMaskIntoConstraints=NO; dock.wantsLayer=YES;
    dock.identifier=@"bottomControlBar";
    dock.accessibilityLabel=@"Bottom control bar"; dock.layer.cornerRadius=12; dock.layer.borderWidth=0; dock.layer.masksToBounds=YES;
    dock.layer.backgroundColor=[NSColor colorWithWhite:0.025 alpha:[self dockBackdropAlpha]].CGColor;
    self.controlDock=dock;
    for(NSView *view in @[self.listenButton,self.deviceButton,self.autoButton,self.commitButton,self.status,self.levelLabel,self.moreButton]) [dock addSubview:view];
    for(NSView *view in @[automatic,manual,dock]) [root addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [dock.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],[dock.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],[dock.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-10],[dock.heightAnchor constraintEqualToConstant:54],
        [self.listenButton.leadingAnchor constraintEqualToAnchor:dock.leadingAnchor constant:12],[self.listenButton.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],[self.listenButton.widthAnchor constraintEqualToConstant:108],[self.listenButton.heightAnchor constraintEqualToConstant:30],
        [self.deviceButton.leadingAnchor constraintEqualToAnchor:self.listenButton.trailingAnchor constant:6],[self.deviceButton.centerYAnchor constraintEqualToAnchor:self.listenButton.centerYAnchor],[self.deviceButton.widthAnchor constraintEqualToConstant:155],
        [self.autoButton.leadingAnchor constraintEqualToAnchor:self.deviceButton.trailingAnchor constant:8],[self.autoButton.centerYAnchor constraintEqualToAnchor:self.listenButton.centerYAnchor],[self.autoButton.widthAnchor constraintEqualToConstant:70],
        [self.commitButton.leadingAnchor constraintEqualToAnchor:self.autoButton.trailingAnchor constant:8],[self.commitButton.centerYAnchor constraintEqualToAnchor:self.listenButton.centerYAnchor],[self.commitButton.widthAnchor constraintEqualToConstant:100],[self.commitButton.heightAnchor constraintEqualToConstant:28],
        [self.moreButton.trailingAnchor constraintEqualToAnchor:dock.trailingAnchor constant:-10],[self.moreButton.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],[self.moreButton.widthAnchor constraintEqualToConstant:44],[self.moreButton.heightAnchor constraintEqualToConstant:30],
        [self.levelLabel.trailingAnchor constraintEqualToAnchor:self.moreButton.leadingAnchor constant:-10],[self.levelLabel.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],[self.levelLabel.widthAnchor constraintEqualToConstant:116],
        [self.status.leadingAnchor constraintEqualToAnchor:self.commitButton.trailingAnchor constant:14],[self.status.trailingAnchor constraintLessThanOrEqualToAnchor:self.levelLabel.leadingAnchor constant:-8],[self.status.centerYAnchor constraintEqualToAnchor:dock.centerYAnchor],
        [automatic.topAnchor constraintEqualToAnchor:root.topAnchor constant:34],[automatic.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:14],
        [manual.topAnchor constraintEqualToAnchor:automatic.topAnchor],[manual.leadingAnchor constraintEqualToAnchor:automatic.trailingAnchor constant:12],[manual.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-14],
        [automatic.widthAnchor constraintEqualToAnchor:manual.widthAnchor],[automatic.bottomAnchor constraintEqualToAnchor:dock.topAnchor constant:-8],[manual.bottomAnchor constraintEqualToAnchor:automatic.bottomAnchor]
    ]];
    [self refreshBackdropAppearance]; [self refreshReadingTypography];
}

- (void)loadAudioDevices {
    AudioObjectPropertyAddress listAddress = { kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 size = 0; AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &listAddress, 0, NULL, &size);
    UInt32 count = size / sizeof(AudioDeviceID); AudioDeviceID *devices = calloc(count, sizeof(AudioDeviceID));
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &listAddress, 0, NULL, &size, devices);
    NSMutableArray *ids=[NSMutableArray array]; NSInteger blackHoleIndex=-1;
    for (UInt32 i=0; i<count; i++) {
      AudioObjectPropertyAddress streamAddress = { kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain };
      UInt32 configSize=0; if (AudioObjectGetPropertyDataSize(devices[i], &streamAddress, 0, NULL, &configSize) != noErr) continue;
      AudioBufferList *buffers=malloc(configSize); if (AudioObjectGetPropertyData(devices[i], &streamAddress, 0, NULL, &configSize, buffers) != noErr) { free(buffers); continue; }
      UInt32 channels=0; for (UInt32 b=0;b<buffers->mNumberBuffers;b++) channels += buffers->mBuffers[b].mNumberChannels; free(buffers); if (!channels) continue;
      CFStringRef name=NULL; UInt32 nameSize=sizeof(name); AudioObjectPropertyAddress nameAddress={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
      AudioObjectGetPropertyData(devices[i], &nameAddress, 0, NULL, &nameSize, &name);
      NSString *deviceName = CFBridgingRelease(name) ?: [NSString stringWithFormat:@"Audio device %u",devices[i]];
      [self.deviceButton addItemWithTitle:[NSString stringWithFormat:@"Nguồn: %@",deviceName]]; [ids addObject:@(devices[i])];
      if ([deviceName rangeOfString:@"BlackHole" options:NSCaseInsensitiveSearch].location != NSNotFound) blackHoleIndex=ids.count-1;
    }
    free(devices); self.inputDeviceIDs=ids;
    if (blackHoleIndex >= 0) [self.deviceButton selectItemAtIndex:blackHoleIndex];
}

- (void)importData:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.allowsMultipleSelection = YES; panel.canChooseDirectories = NO;
    panel.message = @"Chọn dữ liệu dùng làm căn cứ trả lời (.txt, .md, .pdf)";
    panel.allowedFileTypes = @[@"txt", @"md", @"pdf"];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
      if (result != NSModalResponseOK) return;
      NSMutableString *all = [NSMutableString string]; NSMutableArray *names = [NSMutableArray array];
      for (NSURL *url in panel.URLs) {
        NSString *text = nil;
        if ([url.pathExtension.lowercaseString isEqualToString:@"pdf"]) text = [[PDFDocument alloc] initWithURL:url].string;
        else text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        if (text.length) { [all appendFormat:@"\n\n=== TÀI LIỆU: %@ ===\n%@", url.lastPathComponent, text]; [names addObject:url.lastPathComponent]; }
      }
      self.knowledge = all; self.knowledgeNames = names;
      [self setStatus:[NSString stringWithFormat:@"✓ Đã nạp %lu tài liệu (%lu ký tự)", (unsigned long)names.count, (unsigned long)all.length] color:NSColor.systemGreenColor];
    }];
}

- (NSString *)relevantContextForQuestion:(NSString *)question {
    if (!self.knowledge.length) return @"CHƯA CÓ DỮ LIỆU ĐƯỢC NẠP.";
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    NSArray *paras = [self.knowledge componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSMutableString *current = [NSMutableString string];
    for (NSString *p in paras) {
      if (p.length == 0) continue;
      if (current.length + p.length > 1400) { [chunks addObject:current.copy]; [current setString:@""]; }
      [current appendFormat:@"%@\n", p];
    }
    if (current.length) [chunks addObject:current.copy];
    NSCharacterSet *split = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    NSMutableArray *terms = [NSMutableArray array];
    for (NSString *w in [question.lowercaseString componentsSeparatedByCharactersInSet:split]) if (w.length > 2) [terms addObject:w];
    NSMutableArray *ranked = [NSMutableArray array];
    for (NSString *chunk in chunks) {
      NSString *lower = chunk.lowercaseString; NSInteger score = 0;
      for (NSString *term in terms) score += [lower componentsSeparatedByString:term].count - 1;
      [ranked addObject:@{@"score":@(score), @"text":chunk}];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"score"] compare:a[@"score"]]; }];
    NSMutableString *selected = [NSMutableString string];
    for (NSUInteger i=0; i<MIN((NSUInteger)6, ranked.count); i++) [selected appendFormat:@"\n---\n%@", ranked[i][@"text"]];
    return selected;
}

- (void)toggleListening:(id)sender { self.listening ? [self stopListening] : [self requestAndStart]; }
- (void)requestAndStart {
    [self setStatus:@"Đang kiểm tra quyền Microphone…" color:NSColor.systemOrangeColor];
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL micGranted) {
      if (!micGranted) { dispatch_async(dispatch_get_main_queue(), ^{ [self showErrorTitle:@"Microphone bị từ chối" detail:@"Mở System Settings → Privacy & Security → Microphone và bật quyền cho Presenter AI."]; }); return; }
      [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) [self startListening];
          else [self showErrorTitle:@"Speech Recognition bị từ chối" detail:@"Mở System Settings → Privacy & Security → Speech Recognition và bật quyền cho Presenter AI."];
        });
      }];
    }];
}
- (void)startListening {
    NSInteger selected=self.deviceButton.indexOfSelectedItem;
    AudioDeviceID device = selected >= 0 && selected < self.inputDeviceIDs.count ? self.inputDeviceIDs[selected].unsignedIntValue : kAudioObjectUnknown;
    if (device == kAudioObjectUnknown) { [self showErrorTitle:@"Không có nguồn âm thanh" detail:@"Không tìm thấy thiết bị đầu vào. Kiểm tra BlackHole 2ch trong Audio MIDI Setup rồi mở lại ứng dụng."]; return; }

    UInt32 oldSize=sizeof(self.originalInputDevice);
    AudioObjectPropertyAddress defaultAddress={kAudioHardwarePropertyDefaultInputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    AudioObjectGetPropertyData(kAudioObjectSystemObject,&defaultAddress,0,NULL,&oldSize,&_originalInputDevice);
    OSStatus selectStatus=AudioObjectSetPropertyData(kAudioObjectSystemObject,&defaultAddress,0,NULL,sizeof(device),&device);
    if (selectStatus != noErr) { [self showErrorTitle:@"Không thể chọn BlackHole" detail:[NSString stringWithFormat:@"Core Audio từ chối đổi input (mã %d). Chọn BlackHole 2ch tại System Settings → Sound → Input rồi thử lại.",(int)selectStatus]]; return; }

    self.audioEngine = [AVAudioEngine new];
    NSString *locale = self.languageButton.indexOfSelectedItem == 0 ? @"en-AU" : @"vi-VN";
    self.recognizer = [[SFSpeechRecognizer alloc] initWithLocale:[[NSLocale alloc] initWithLocaleIdentifier:locale]];
    if (!self.recognizer || !self.recognizer.available) { [self showErrorTitle:@"Nhận diện giọng nói chưa sẵn sàng" detail:@"Kiểm tra Internet, ngôn ngữ đã chọn và thử lại sau vài giây."]; return; }
    AVAudioInputNode *input = self.audioEngine.inputNode;
    AVAudioFormat *format = [input outputFormatForBus:0];
    if (format.sampleRate <= 0 || format.channelCount == 0) { [self showErrorTitle:@"Không tìm thấy tín hiệu micro" detail:@"Chọn một micro trong System Settings → Sound → Input, sau đó mở lại ứng dụng."]; return; }
    self.timeline=[SCSpeechTimeline new];
    self.autoDetector=[SCAutoQuestionDetector new];
    self.manualUntimedBuffer=[SCUntimedTranscriptBuffer new];
    self.enhancedAutoTranscriptBuffer=[SCUntimedTranscriptBuffer new];
    self.autoAudioBuffer=[SCAudioUtteranceBuffer new];
    self.autoTranscriptionQueue=[NSMutableArray array]; self.autoTranscriptionInFlight=NO; self.autoEnhancedUnavailable=NO;
    self.autoTurnParts=[NSMutableArray array]; self.autoTurnChangedAt=0;
    self.recognitionGeneration++;
    self.manualUsesUntimed=NO; self.hasUsableSpeechTiming=YES;
    self.manualCursor=0; self.autoCursor=0;
    self.audioTime=0; self.lastVoiceAudioTime=0; self.taskAudioStart=0; self.lastAutoAsked=nil;
    self.latestTranscript=@""; self.autoTranscript=@""; self.autoPendingSnapshot=@"";
    self.autoPendingChangedAt=NSProcessInfo.processInfo.systemUptime; self.spaceCommitPending=NO;
    self.transcriptView.string=@"Đang nghe… bấm Space khi đã nghe đủ một câu hỏi.";
    self.transcriptView.textColor=[NSColor colorWithWhite:0.82 alpha:1];
    __weak typeof(self) weak = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *b, AVAudioTime *t) {
      // The timestamp counts exactly the PCM submitted to the current speech request.
      @synchronized(weak) {
        if (weak.speechRequest) {
          [weak.speechRequest appendAudioPCMBuffer:b];
          weak.audioTime += (double)b.frameLength/b.format.sampleRate;
        }
      }
      float *const *channels=b.floatChannelData; float rms=0; if (channels && b.frameLength) { double sum=0; for(AVAudioChannelCount c=0;c<b.format.channelCount;c++) for (AVAudioFrameCount i=0;i<b.frameLength;i++) sum += channels[c][i]*channels[c][i]; rms=(float)sqrt(sum/(b.frameLength*b.format.channelCount)); }
      BOOL voiced=rms>0.003;
      if(voiced) weak.lastVoiceAudioTime=weak.audioTime;
      [weak.autoAudioBuffer appendBuffer:b voiced:voiced];
      CFAbsoluteTime now=CFAbsoluteTimeGetCurrent(); if (now-weak.lastLevelUpdate < 0.18) return; weak.lastLevelUpdate=now;
      float db=rms>0?20.0f*log10f(rms):-100.0f; NSInteger bars=(NSInteger)((db+60.0f)/5.0f); bars=MAX(0,MIN(10,bars));
      NSMutableString *meter=[NSMutableString string]; for(NSInteger i=0;i<10;i++) [meter appendString:i<bars?@"▮":@"▯"];
      NSString *detail=bars?[NSString stringWithFormat:@"%@  %.0f dB",meter,db]:@"Không có tín hiệu âm thanh";
      dispatch_async(dispatch_get_main_queue(), ^{ weak.levelLabel.stringValue=bars?@"● Có âm thanh":@"○ Im lặng"; weak.levelLabel.toolTip=detail; weak.levelLabel.textColor=bars?NSColor.systemGreenColor:NSColor.systemOrangeColor; });
    }];
    self.inputTapInstalled=YES;
    self.listening=YES;
    [self beginSpeechTask];
    [self.autoTimer invalidate];
    self.autoTimer=[NSTimer scheduledTimerWithTimeInterval:0.10 target:self selector:@selector(tickAutoRecognition:) userInfo:nil repeats:YES];
    CFAbsoluteTime started=CFAbsoluteTimeGetCurrent(); self.lastLevelUpdate=started;
    NSError *error; [self.audioEngine prepare];
    if (![self.audioEngine startAndReturnError:&error]) {
      NSString *help = error.code == 560227702 ? @"Mã !dev: thiết bị thu âm hiện tại không khả dụng. Vào System Settings → Sound → Input, chọn MacBook Microphone (không chọn thiết bị Bluetooth/Continuity đã ngắt), đóng các app độc quyền âm thanh rồi mở lại Presenter AI." : @"Kiểm tra micro trong System Settings → Sound → Input.";
      [self stopListening];
      [self showErrorTitle:@"Không thể khởi động micro" detail:[NSString stringWithFormat:@"%@\n\n%@ (%@, mã %ld)", help, error.localizedDescription, error.domain, (long)error.code]]; return;
    }
    self.listening = YES; self.listenButton.title = @"Dừng nghe";
    self.listenButton.layer.backgroundColor=[NSColor colorWithRed:0.96 green:0.33 blue:0.40 alpha:0.20].CGColor;
    self.listenButton.layer.borderColor=[NSColor colorWithRed:1 green:0.42 blue:0.48 alpha:0.42].CGColor;
    self.levelLabel.stringValue=@"○ Đang chờ âm thanh"; [self setStatus:@"● Đang nghe • Space để lấy gợi ý" color:NSColor.systemRedColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      if (self.listening && self.lastLevelUpdate <= started) { self.levelLabel.stringValue=@"○ Không có âm thanh"; self.levelLabel.toolTip=@"Không nhận được buffer từ BlackHole"; self.levelLabel.textColor=NSColor.systemRedColor; }
    });
}
- (NSArray<NSString *> *)recognitionContextualStrings {
    // Apple recommends at most 100 short (usually one- or two-word) phrases.
    // Keep high-confusion cooking words first so the useful hint budget is not
    // consumed by full questions that the recognizer is unlikely to match.
    // Keep the vocabulary balanced. v5.38-v5.41 placed so many stock/French
    // variants first that Apple's 100-phrase ceiling pushed out common safety,
    // knife and workplace terms that v4 recognised well.
    NSArray<NSString *> *recognitionPriority=@[
      @"stock",@"grill",@"grilled",@"grilling",@"grill pan",@"stockpot",@"stock rotation",@"beef stock",@"chicken stock",@"fish stock",@"vegetable stock",
      @"mise en place",@"à la carte",@"table d'hôte",@"consommé",@"sous-vide",@"roux",@"béchamel",@"velouté",@"hollandaise",@"béarnaise",@"demi-glace",@"mirepoix",@"bouquet garni",@"bain-marie",@"beurre blanc",@"beurre manié",@"au gratin",@"confit",@"flambé",@"sauté",@"hors d'oeuvre",@"amuse-bouche",@"crème brûlée",@"crème pâtissière",@"julienne",@"brunoise",@"chiffonade",@"duxelles",@"en papillote",@"profiterole",@"vichyssoise",@"vol-au-vent",@"garde manger",@"chef de partie",@"commis chef",
      @"HACCP",@"FIFO",@"food safety plan",@"temperature danger zone",@"two-hour four-hour rule",@"cross-contamination",@"cross-contact",@"potentially hazardous food",@"probe thermometer",@"cleaning and sanitising",@"air-dry",@"allergen",@"anaphylaxis",@"coeliac",@"gluten-free",
      @"chef's knife",@"paring knife",@"boning knife",@"filleting knife",@"serrated knife",@"mandoline",@"colour-coded chopping board",@"personal protective equipment",
      @"standard recipe card",@"portion control",@"food cost percentage",@"yield test",@"cultural sensitivity",@"anti-discrimination"
    ];
    NSMutableOrderedSet<NSString *> *ordered=[NSMutableOrderedSet orderedSetWithArray:recognitionPriority];
    [ordered addObjectsFromArray:self.speechHints ?: @[]];
    NSArray *all=ordered.array;
    return all.count>100?[all subarrayWithRange:NSMakeRange(0,100)]:all;
}
- (NSString *)speechLexiconKey:(NSString *)text {
    NSString *key=[[text ?: @"" lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en"]];
    NSArray<NSString *> *parts=[key componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray<NSString *> *words=[NSMutableArray array];
    for(NSString *part in parts) if(part.length) [words addObject:part];
    return [words componentsJoinedByString:@" "];
}
- (NSSet<NSString *> *)culinaryRecognitionLexicon {
    if(self.speechLexicon.count) return self.speechLexicon;
    NSMutableSet<NSString *> *lexicon=[NSMutableSet set];
    for(NSString *term in [self recognitionContextualStrings]) {
      NSString *key=[self speechLexiconKey:term]; if(key.length) [lexicon addObject:key];
    }
    for(NSString *term in self.speechHints ?: @[]) {
      NSString *key=[self speechLexiconKey:term]; if(key.length) [lexicon addObject:key];
    }
    self.speechLexicon=lexicon.copy;
    return self.speechLexicon;
}
- (NSUInteger)culinaryEvidenceInText:(NSString *)text {
    NSString *normal=[self speechLexiconKey:text];
    if(!normal.length) return 0;
    NSSet<NSString *> *lexicon=[self culinaryRecognitionLexicon];
    NSArray<NSString *> *words=[normal componentsSeparatedByString:@" "];
    NSUInteger evidence=0;
    for(NSUInteger i=0;i<words.count;i++) {
      if([lexicon containsObject:words[i]]) evidence++;
      if(i+1<words.count && [lexicon containsObject:[NSString stringWithFormat:@"%@ %@",words[i],words[i+1]]]) evidence+=2;
      if(i+2<words.count && [lexicon containsObject:[NSString stringWithFormat:@"%@ %@ %@",words[i],words[i+1],words[i+2]]]) evidence+=3;
    }
    return evidence;
}
- (NSString *)preferredCulinaryAlternativeForPrimary:(NSString *)primary alternatives:(NSArray<NSString *> *)alternatives {
    NSString *first=primary ?: @"";
    if(!first.length || alternatives.count<2) return first;
    NSString *correctedPrimary=[self correctCulinaryTerms:first];
    // A canonical Apple alternative is safer than reconstructing a known
    // correction. It retains the recognizer's punctuation and word timing.
    if(![correctedPrimary isEqualToString:first]) {
      for(NSString *candidate in alternatives) {
        NSString *corrected=[self correctCulinaryTerms:candidate];
        if([candidate isEqualToString:corrected] && [corrected isEqualToString:correctedPrimary]) return candidate;
      }
    }
    NSString *best=first;
    NSUInteger bestEvidence=[self culinaryEvidenceInText:first];
    NSString *primaryKey=[self speechLexiconKey:first];
    for(NSString *candidate in alternatives) {
      if(!candidate.length || [candidate isEqualToString:first]) continue;
      NSUInteger evidence=[self culinaryEvidenceInText:candidate];
      if(evidence<=bestEvidence) continue;
      NSString *candidateKey=[self speechLexiconKey:candidate];
      NSUInteger maxLength=MAX(primaryKey.length,candidateKey.length);
      double similarity=maxLength?1.0-(double)[self editDistance:primaryKey other:candidateKey]/maxLength:0;
      if(similarity>=0.72) { best=candidate; bestEvidence=evidence; }
    }
    return best;
}
- (void)beginSpeechTask {
    if (!self.listening) return;
    SFSpeechAudioBufferRecognitionRequest *request=[SFSpeechAudioBufferRecognitionRequest new];
    request.shouldReportPartialResults=YES;
    request.taskHint=SFSpeechRecognitionTaskHintDictation;
    request.contextualStrings=[self recognitionContextualStrings];
    if (@available(macOS 13.0,*)) request.addsPunctuation=YES;
    __block NSTimeInterval offset=0;
    @synchronized(self) {
      offset=self.audioTime;
      self.taskAudioStart=offset;
      self.speechRequest=request;
    }
    __weak typeof(self) weak=self;
    self.speechTask=[self.recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *r,NSError *e) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!weak.listening || request!=weak.speechRequest) return;
        if(r) {
          NSMutableArray *segments=[NSMutableArray array];
          NSArray<SFTranscription *> *alternatives=r.transcriptions.count?r.transcriptions:@[r.bestTranscription];
          NSArray<NSString *> *candidateTexts=[alternatives valueForKey:@"formattedString"];
          NSString *preferred=[weak preferredCulinaryAlternativeForPrimary:r.bestTranscription.formattedString alternatives:candidateTexts];
          SFTranscription *transcription=r.bestTranscription;
          for(SFTranscription *candidate in alternatives) if([candidate.formattedString isEqualToString:preferred]) { transcription=candidate; break; }
          NSString *rawFormatted=transcription.formattedString ?: @"";
          NSMutableString *formatted=[NSMutableString string];
          NSArray<SFTranscriptionSegment *> *words=transcription.segments;
          for(NSUInteger i=0;i<words.count;i++) {
            SFTranscriptionSegment *word=words[i];
            NSString *resolved=[weak preferredCulinaryAlternativeForPrimary:word.substring alternatives:[@[word.substring ?: @""] arrayByAddingObjectsFromArray:word.alternativeSubstrings ?: @[]]];
            NSUInteger suffixStart=NSMaxRange(word.substringRange);
            NSUInteger suffixEnd=i+1<words.count?words[i+1].substringRange.location:rawFormatted.length;
            NSString *suffix=@"";
            if(suffixStart<=suffixEnd && suffixEnd<=rawFormatted.length) suffix=[rawFormatted substringWithRange:NSMakeRange(suffixStart,suffixEnd-suffixStart)];
            NSString *text=[(resolved ?: word.substring ?: @"") stringByAppendingString:suffix];
            [formatted appendString:text];
            [segments addObject:@{@"text":text,@"start":@(offset+word.timestamp),@"end":@(offset+word.timestamp+word.duration)}];
          }
          if(!words.count) [formatted appendString:rawFormatted];
          [weak receiveSpeechSegments:segments text:[weak correctCulinaryTerms:formatted] final:r.isFinal];
        }
        if(r.isFinal || e) {
          if(e && !([e.domain isEqualToString:@"kAFAssistantErrorDomain"] && (e.code==203 || e.code==1110))) {
            NSString *detail=[NSString stringWithFormat:@"%@ (%@, mã %ld)",e.localizedDescription,e.domain,(long)e.code];
            [weak stopListening]; [weak showErrorTitle:@"Speech Recognition gặp lỗi" detail:detail]; return;
          }
          [weak restartSpeechTaskOnly];
        }
      });
    }];
}
- (void)restartSpeechTaskOnly {
    if (!self.listening) return;
    [self.timeline finishCurrentTask];
    [self.manualUntimedBuffer finishTask];
    [self.autoDetector finishTextTask];
    [self.enhancedAutoTranscriptBuffer finishTask];
    SFSpeechRecognitionTask *oldTask=self.speechTask;
    SFSpeechAudioBufferRecognitionRequest *oldRequest=self.speechRequest;
    // Install the next request before closing the old one: no scheduled 350 ms hole.
    [self beginSpeechTask];
    [oldRequest endAudio]; [oldTask cancel];
}
- (void)stopListening {
    self.listening=NO;
    self.recognitionGeneration++;
    [self.silenceTimer invalidate]; [self.autoTimer invalidate];
    [self.spaceSettleTimer invalidate]; [self.spaceDeadlineTimer invalidate];
    if(self.spaceCommitPending) [self finishSpaceCommit];
    if(self.inputTapInstalled) { [self.audioEngine.inputNode removeTapOnBus:0]; self.inputTapInstalled=NO; }
    [self.audioEngine stop];
    @synchronized(self) {
      [self.speechRequest endAudio]; self.speechRequest=nil;
    }
    [self.speechTask cancel]; self.speechTask=nil;
    [self.autoAudioBuffer reset]; [self.enhancedAutoTranscriptBuffer reset];
    [self.autoTranscriptionQueue removeAllObjects]; self.autoTranscriptionInFlight=NO;
    [self.autoTurnParts removeAllObjects]; self.autoTurnChangedAt=0;
    if(self.originalInputDevice!=kAudioObjectUnknown) {
      AudioObjectPropertyAddress address={kAudioHardwarePropertyDefaultInputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
      AudioDeviceID restore=self.originalInputDevice;
      AudioObjectSetPropertyData(kAudioObjectSystemObject,&address,0,NULL,sizeof(restore),&restore);
      self.originalInputDevice=kAudioObjectUnknown;
    }
    self.levelLabel.stringValue=@"○ Đã dừng";
    self.levelLabel.textColor=[NSColor colorWithWhite:0.76 alpha:1];
    self.listenButton.title=@"Bắt đầu nghe";
    self.listenButton.layer.backgroundColor=[NSColor colorWithRed:0.18 green:0.75 blue:0.55 alpha:0.22].CGColor;
    self.listenButton.layer.borderColor=[NSColor colorWithRed:0.30 green:0.92 blue:0.69 alpha:0.40].CGColor;
    [self setStatus:@"● Đã dừng" color:NSColor.secondaryLabelColor];
}
- (NSString *)correctCulinaryTerms:(NSString *)text {
    if (!text.length) return @"";
    NSMutableString *result=[text mutableCopy];
    NSDictionary *aliases=@{
      @"me's in place":@"mise en place",@"mees en place":@"mise en place",@"meez en place":@"mise en place",@"mis en place":@"mise en place",@"mise and place":@"mise en place",@"mise on place":@"mise en place",@"missing place":@"mise en place",@"means in place":@"mise en place",@"meat in place":@"mise en place",@"misan place":@"mise en place",@"mise place":@"mise en place",
      @"ala carte":@"à la carte",@"a la cart":@"à la carte",@"a la card":@"à la carte",@"a la cat":@"à la carte",
      @"sue vide":@"sous-vide",@"sous feed":@"sous-vide",@"sue feed":@"sous-vide",@"soup feed":@"sous-vide",
      @"consume a":@"consommé",@"consomme":@"consommé",@"conso may":@"consommé",
      @"bechamel":@"béchamel",@"bay shamel":@"béchamel",@"veloute":@"velouté",@"velo tay":@"velouté",
      @"bay sham el":@"béchamel",@"besh a mel":@"béchamel",@"velo tea":@"velouté",@"veloo tay":@"velouté",
      @"julian cut":@"julienne cut",@"julian":@"julienne",@"julien":@"julienne",@"julianne":@"julienne",
      @"bruno's":@"brunoise",@"brun noise":@"brunoise",
      @"table dote":@"table d'hôte",@"table de hot":@"table d'hôte",@"table doh":@"table d'hôte",
      @"roo sauce":@"roux sauce",@"make a roo":@"make a roux",@"the roo":@"the roux",@"roo":@"roux",@"make rue":@"make roux",@"the rue":@"the roux",
      @"holland days":@"hollandaise",@"holland day sauce":@"hollandaise",@"hollandiase":@"hollandaise",
      @"bear nays":@"béarnaise",@"bearnaise":@"béarnaise",@"bernese sauce":@"béarnaise",
      @"demi glass":@"demi-glace",@"demi gloss":@"demi-glace",@"demi glaze":@"demi-glace",
      @"mirror paw":@"mirepoix",@"mere poise":@"mirepoix",@"mira pwa":@"mirepoix",
      @"bouquet garney":@"bouquet garni",@"bouquet garnet":@"bouquet garni",
      @"ban marie":@"bain-marie",@"bane marie":@"bain-marie",@"ben marie":@"bain-marie",
      @"bear blank":@"beurre blanc",@"burr blank":@"beurre blanc",@"bear man yay":@"beurre manié",@"burr man yay":@"beurre manié",
      @"oh gratin":@"au gratin",@"o gratin":@"au gratin",@"con fee":@"confit",@"flam bay":@"flambé",@"saute":@"sauté",
      @"horse derv":@"hors d'oeuvre",@"horse divorce":@"hors d'oeuvre",@"or derv":@"hors d'oeuvre",
      @"amuse bush":@"amuse-bouche",@"amuse boosh":@"amuse-bouche",
      @"cream brulee":@"crème brûlée",@"creme brew lay":@"crème brûlée",@"cream anglaise":@"crème anglaise",@"creme anglais":@"crème anglaise",
      @"ganash":@"ganache",@"pate":@"pâté",@"chiffon aid":@"chiffonade",@"chiffon aard":@"chiffonade",
      @"brun wahz":@"brunoise",@"mack say dwon":@"macédoine",@"con cass say":@"concassé",@"kuh nell":@"quenelle",
      @"duke sells":@"duxelles",@"on pap ee oat":@"en papillote",@"cream patisserie":@"crème pâtissière",
      @"guard manger":@"garde manger",@"gard manger":@"garde manger",@"chef de party":@"chef de partie",@"chef duh party":@"chef de partie",@"commie chef":@"commis chef",
      @"eye oli":@"aioli",@"a oli":@"aioli",@"gremolada":@"gremolata",@"vol au vent":@"vol-au-vent",
      @"sanitizing":@"sanitising",@"sanitize":@"sanitise",@"sanitizer":@"sanitiser",
      @"paltry":@"poultry",@"poetry seafood":@"poultry seafood",@"culture identity":@"cultural identity",@"culture background":@"cultural background",
      @"chief knife":@"chef knife",@"chef's nice":@"chef's knife",@"shift knife":@"chef knife",
      @"verseti":@"versatility",@"versa tea":@"versatility",@"versality":@"versatility"
    };
    // Whole phrases, one pass: "julienne" must not grow on each normalization.
    NSArray *keys=[aliases.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b) {
      if(a.length!=b.length) return a.length>b.length?NSOrderedAscending:NSOrderedDescending;
      return [a compare:b];
    }];
    NSMutableArray *patterns=[NSMutableArray array];
    for(NSString *key in keys) [patterns addObject:[NSRegularExpression escapedPatternForString:key]];
    NSString *pattern=[NSString stringWithFormat:@"(?i)(?<![\\p{L}\\p{N}])(?:%@)(?![\\p{L}\\p{N}])",[patterns componentsJoinedByString:@"|"]];
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    for(NSTextCheckingResult *match in [[re matchesInString:text options:0 range:NSMakeRange(0,text.length)] reverseObjectEnumerator]) {
      NSString *word=[[text substringWithRange:match.range] lowercaseString];
      [result replaceCharactersInRange:match.range withString:aliases[word]];
    }
    // Resolve a frequent acoustic error without rewriting a genuine animal
    // question. The grammar around the word tells us whether the intended form
    // is the verb/appliance "grill" or the adjective "grilled".
    void (^replaceCapturedWord)(NSString *,NSString *)=^(NSString *expression,NSString *replacement) {
      NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:expression options:NSRegularExpressionCaseInsensitive error:nil];
      NSArray<NSTextCheckingResult *> *matches=[regex matchesInString:result options:0 range:NSMakeRange(0,result.length)];
      for(NSTextCheckingResult *match in matches.reverseObjectEnumerator) {
        NSRange wordRange=[match rangeAtIndex:1];
        if(wordRange.location!=NSNotFound) [result replaceCharactersInRange:wordRange withString:replacement];
      }
    };
    replaceCapturedWord(@"\\b(?:do|does|did|can|could|would|should|will|may|might|must|to)\\s+(?:(?:you|we|i|they|he|she)\\s+)?(gorilla|guerrilla)\\b",@"grill");
    replaceCapturedWord(@"\\b(?:on|using|use|clean|cleaning|preheat|heat|scrub)\\s+(?:(?:a|the|an)\\s+)?(gorilla|guerrilla)\\b",@"grill");
    replaceCapturedWord(@"\\b(gorilla|guerrilla)\\b(?=\\s+(?:chicken|fish|steak|meat|vegetables?|poultry|seafood|lamb|beef|pork|salmon|barramundi|mushrooms?|sandwich|dish|or\\s+(?:roasted|fried|baked|poached|steamed)))",@"grilled");
    // Apple Speech sometimes confuses the culinary noun “stock” with the
    // similar-sounding verb/noun “stuff”. Correct only stock-shaped phrases;
    // legitimate instructions such as “stuff the chicken” stay untouched.
    static NSRegularExpression *stockContext=nil,*standaloneStuff=nil;
    static dispatch_once_t stockOnce;
    dispatch_once(&stockOnce, ^{
      NSString *context=@"(?i)\\b(?:what\\s+is\\s+(?:a\\s+|the\\s+)?stuff|what\\s+(?:are\\s+)?(?:the\\s+)?(?:[\\p{L}\\p{N}-]+\\s+){0,4}(?:types|kinds)\\s+of\\s+stuff|what\\s+makes\\s+(?:a\\s+)?good\\s+stuff|which\\s+stuff|(?:how\\s+(?:long\\s+)?(?:do|would|can|should)\\s+you\\s+|how\\s+to\\s+)(?:make|prepare|clarify|strain|simmer|cool)\\b[^?.!]{0,40}\\bstuff|(?:beef|chicken|fish|vegetable|veal|brown|white)\\s+stuff|stuff\\s+(?:quality|rotation|levels?|control|pot|take|taking|cubes?|bases?|production|preparation))\\b";
      stockContext=[NSRegularExpression regularExpressionWithPattern:context options:0 error:nil];
      standaloneStuff=[NSRegularExpression regularExpressionWithPattern:@"(?i)\\bstuff\\b" options:0 error:nil];
    });
    NSArray<NSTextCheckingResult *> *stockMatches=[stockContext matchesInString:result options:0 range:NSMakeRange(0,result.length)];
    for(NSTextCheckingResult *contextMatch in stockMatches.reverseObjectEnumerator) {
      NSArray<NSTextCheckingResult *> *wordMatches=[standaloneStuff matchesInString:result options:0 range:contextMatch.range];
      for(NSTextCheckingResult *wordMatch in wordMatches.reverseObjectEnumerator) {
        NSString *heard=[result substringWithRange:wordMatch.range];
        NSString *replacement=[heard isEqualToString:heard.uppercaseString]?@"STOCK":([[heard substringToIndex:1] isEqualToString:[[heard substringToIndex:1] uppercaseString]]?@"Stock":@"stock");
        [result replaceCharactersInRange:wordMatch.range withString:replacement];
      }
    }
    return result;
}
- (BOOL)enhancedAutoTranscriptionEnabled {
    return self.keyField.stringValue.length>=20 && !self.autoEnhancedUnavailable;
}
- (void)receiveSpeechSegments:(NSArray<NSDictionary *> *)segments text:(NSString *)text final:(BOOL)final {
    // Only immutable recognizer output is shared. Each consumer owns its mutable state.
    if(!self.manualUntimedBuffer) self.manualUntimedBuffer=[SCUntimedTranscriptBuffer new];
    if(!self.timeline) self.timeline=[SCSpeechTimeline new];
    if(!self.autoDetector) self.autoDetector=[SCAutoQuestionDetector new];
    NSString *heard=[self correctCulinaryTerms:text ?: @""];
    [self.manualUntimedBuffer updateText:heard];
    [self.enhancedAutoTranscriptBuffer updateText:heard];
    BOOL usable=SCUsableSpeechSegments(segments,self.audioTime);
    self.hasUsableSpeechTiming=usable;
    if(usable) [self.timeline replaceCurrentSegments:segments];
    else if(heard.length && !self.manualUsesUntimed) {
      // A partial transcript may have no usable word timestamps. Never turn
      // zero metadata into an audio boundary and silently discard future words.
      if(self.spaceCommitPending) [self finishSpaceCommit];
      self.manualUsesUntimed=YES;
    }
    [self refreshManualTranscriptFinal:final];
    NSArray *ready=[self.autoDetector updateText:heard now:NSProcessInfo.processInfo.systemUptime final:final];
    if(!self.autoButton || self.autoButton.state==NSControlStateValueOn) {
      [self consumeAutoCandidates:ready];
      [self refreshAutoLiveTranscript];
    } else {
      [self.autoDetector discardPendingText];
      if([self enhancedAutoTranscriptionEnabled]) [self.enhancedAutoTranscriptBuffer consume];
    }
}
- (void)refreshManualTranscriptFinal:(BOOL)final {
    self.manualSnapshotFinal=final;
    NSString *text=self.manualUsesUntimed?self.manualUntimedBuffer.pendingText:[self.timeline textFrom:self.manualCursor to:DBL_MAX];
    text=[self correctCulinaryTerms:text];
    if(![text isEqualToString:self.latestTranscript]) self.lastManualSnapshotChange=NSProcessInfo.processInfo.systemUptime;
    self.latestTranscript=text;
    self.transcriptView.string=text.length?text:@"SPACE: đang nghe câu tiếp theo…";
    if(self.currentAnswerView) [self showCurrentQuestion:self.currentQuestion answer:self.currentAnswer.length?self.currentAnswer:@"Press Space after the question. Your answer will appear here."];
    if(self.spaceCommitPending) {
      NSString *bounded=[self correctCulinaryTerms:[self.timeline textFrom:self.pendingSpaceFrom to:self.pendingSpaceTo]];
      // A short revised tail cannot replace the whole visible question.
      NSUInteger oldWords=[self.spaceTranscriptSnapshot componentsSeparatedByString:@" "].count;
      NSUInteger newWords=[bounded componentsSeparatedByString:@" "].count;
      if(bounded.length && (final || newWords+1>=oldWords)) self.spaceTranscriptSnapshot=bounded;
      BOOL crossed=[self.timeline endTimeFrom:self.pendingSpaceTo to:DBL_MAX]>self.pendingSpaceTo;
      if(final || crossed) {
        [self.spaceSettleTimer invalidate];
        self.spaceSettleTimer=[NSTimer scheduledTimerWithTimeInterval:0.15 target:self selector:@selector(finishSpaceCommit) userInfo:nil repeats:NO];
      }
    }
}
- (void)refreshTranscriptFinal:(BOOL)final {
    // Legacy manual refresh entry point deliberately cannot alter AUTO.
    [self refreshManualTranscriptFinal:final];
}
- (void)refreshAutoLiveTranscript {
    self.autoTranscript=[self enhancedAutoTranscriptionEnabled]?(self.enhancedAutoTranscriptBuffer.pendingText ?: @""):(self.autoDetector.pendingText ?: @"");
    if(![self.autoTranscript isEqualToString:self.autoPendingSnapshot ?: @""]) {
      self.autoPendingSnapshot=self.autoTranscript;
      self.autoPendingChangedAt=NSProcessInfo.processInfo.systemUptime;
    }
    self.autoTranscriptView.string=self.autoTranscript.length?self.autoTranscript:@"AUTO: đang tìm câu hỏi tiếp theo…";
    if(self.autoAnswerView) [self showAutoQuestion:self.autoQuestion answer:self.autoAnswer.length?self.autoAnswer:@""];
}
- (void)stageAutoQuestionTurnText:(NSString *)text {
    if(!self.autoTurnParts) self.autoTurnParts=[NSMutableArray array];
    for(NSString *raw in [text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      NSString *part=[self primaryQuestionFromText:raw];
      if(!part.length) continue;
      NSString *normal=[self normalisedQuestion:part];
      NSSet *terms=[self contentTerms:part];
      BOOL merged=NO;
      for(NSUInteger index=0;index<self.autoTurnParts.count;index++) {
        NSString *existing=self.autoTurnParts[index];
        NSString *existingNormal=[self normalisedQuestion:existing];
        if([normal isEqualToString:existingNormal]) { merged=YES; break; }
        NSSet *existingTerms=[self contentTerms:existing];
        NSUInteger common=0; for(NSString *term in terms) if([existingTerms containsObject:term]) common++;
        NSUInteger shorter=MIN(terms.count,existingTerms.count);
        BOOL extension=[normal containsString:existingNormal] || [existingNormal containsString:normal];
        if((common>=2 && shorter && (double)common/(double)shorter>=0.80) || extension) {
          if(part.length>existing.length) self.autoTurnParts[index]=part;
          merged=YES; break;
        }
      }
      if(!merged) [self.autoTurnParts addObject:part];
    }
    if(self.autoTurnParts.count>8) [self.autoTurnParts removeObjectsInRange:NSMakeRange(0,self.autoTurnParts.count-8)];
    if(self.autoTurnParts.count) {
      self.autoTurnChangedAt=NSProcessInfo.processInfo.systemUptime;
      self.autoLiveLabel.stringValue=self.autoTurnParts.count>1?[NSString stringWithFormat:@"AUTO • Đang nối %lu phần của cùng lượt nói",(unsigned long)self.autoTurnParts.count]:@"AUTO • Đang chờ hết lượt nói";
    }
}
- (void)flushAutoQuestionTurnIfReadyAt:(NSTimeInterval)now force:(BOOL)force {
    if(!self.autoTurnParts.count) return;
    NSTimeInterval quietFor=MAX(0,self.audioTime-self.lastVoiceAudioTime);
    NSTimeInterval settledFor=MAX(0,now-self.autoTurnChangedAt);
    if(!force) {
      if(quietFor<SCAutoTurnSilence || settledFor<SCAutoTurnSettle) return;
    }
    NSString *combined=[self.autoTurnParts componentsJoinedByString:@"\n"];
    [self.autoTurnParts removeAllObjects]; self.autoTurnChangedAt=0;
    if(combined.length) [self autoRecogniseQuestionText:combined fast:NO];
}
- (void)consumeAutoCandidates:(NSArray<NSDictionary *> *)candidates {
    if(!candidates.count) return;
    NSMutableArray<NSString *> *parts=[NSMutableArray array];
    for(NSDictionary *candidate in candidates) {
      NSString *part=[self primaryQuestionFromText:candidate[@"question"]];
      if(part.length && ![parts containsObject:part]) [parts addObject:part];
    }
    if(parts.count) [self stageAutoQuestionTurnText:[parts componentsJoinedByString:@"\n"]];
}
- (void)appendMultipartField:(NSString *)name value:(NSString *)value boundary:(NSString *)boundary data:(NSMutableData *)data {
    NSString *part=[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n",boundary,name,value ?: @""];
    [data appendData:[part dataUsingEncoding:NSUTF8StringEncoding]];
}
- (NSString *)autoTranscriptionPrompt {
    NSString *vocabulary=[[self recognitionContextualStrings] componentsJoinedByString:@", "];
    NSString *recent=[self recentAutoQuestionContext];
    return [NSString stringWithFormat:@"Australian English commercial cookery skills-assessment interview. Preserve the exact question and culinary terminology, including French loanwords. Vocabulary: %@.%@",vocabulary,recent.length?[NSString stringWithFormat:@" Recent conversation: %@",recent]:@""];
}
- (NSMutableURLRequest *)autoTranscriptionRequestForWAV:(NSData *)wav {
    NSString *boundary=[@"PresenterAI-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSMutableData *body=[NSMutableData data];
    [self appendMultipartField:@"model" value:@"gpt-transcribe" boundary:boundary data:body];
    [self appendMultipartField:@"language" value:@"en" boundary:boundary data:body];
    [self appendMultipartField:@"response_format" value:@"json" boundary:boundary data:body];
    [self appendMultipartField:@"prompt" value:[self autoTranscriptionPrompt] boundary:boundary data:body];
    for(NSString *term in [self recognitionContextualStrings])
      [self appendMultipartField:@"keywords[]" value:term boundary:boundary data:body];
    NSString *header=[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.wav\"\r\nContent-Type: audio/wav\r\n\r\n",boundary];
    [body appendData:[header dataUsingEncoding:NSUTF8StringEncoding]]; [body appendData:wav];
    [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n",boundary] dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/audio/transcriptions"]];
    request.HTTPMethod=@"POST"; request.timeoutInterval=10; request.HTTPBody=body;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@",boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:self.keyField.stringValue ?: @""] forHTTPHeaderField:@"Authorization"];
    return request;
}
- (NSString *)questionTurnFromTranscript:(NSString *)transcript {
    NSString *clean=[[self correctCulinaryTerms:transcript ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(clean.length<4) return @"";
    SCAutoQuestionDetector *detector=[SCAutoQuestionDetector new];
    [detector updateText:clean now:10 final:YES];
    NSArray<NSDictionary *> *ready=[detector tickWithAudioTime:0 now:10.2];
    NSMutableArray<NSString *> *parts=[NSMutableArray array];
    for(NSDictionary *candidate in ready) {
      NSString *part=[self primaryQuestionFromText:candidate[@"question"]];
      if(part.length && ![parts containsObject:part]) [parts addObject:part];
    }
    if(parts.count) return [parts componentsJoinedByString:@"\n"];
    if([self looksLikeQuestion:clean]) return clean;
    NSString *starter=@"(?i)\\b(?:what|which|why|how|when|where|who|whose|whom|in what ways|can|could|do|does|did|are|is|was|were|would|will|should|may|might|must|have|tell (?:me|us)|(?:walk|talk|take) (?:me|us) through|share|explain|list|name|describe|identify|give|outline|define|compare|discuss|provide|state|mention|show|design|distinguish|demonstrate)\\b";
    NSRange range=[clean rangeOfString:starter options:NSRegularExpressionSearch];
    if(range.location!=NSNotFound) {
      NSString *candidate=[[clean substringFromIndex:range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if(candidate.length>=6) return candidate;
    }
    return @"";
}
- (void)finishEnhancedAutoTranscriptionJob:(NSDictionary *)job transcript:(NSString *)transcript success:(BOOL)success {
    if(!success) {
      self.autoEnhancedUnavailable=YES;
      [self.autoTranscriptionQueue removeAllObjects]; [self.autoAudioBuffer reset]; [self.autoDetector reset];
      NSString *alreadyHeard=[job[@"fallback"] isKindOfClass:NSString.class]?job[@"fallback"]:@"";
      if(alreadyHeard.length) {
        [self.autoDetector updateText:alreadyHeard now:NSProcessInfo.processInfo.systemUptime final:YES];
        [self.autoDetector discardPendingText];
      }
    }
    if([job[@"generation"] unsignedIntegerValue]==self.recognitionGeneration && self.listening && self.autoButton.state==NSControlStateValueOn) {
      NSString *question=[self questionTurnFromTranscript:transcript];
      if(!question.length) question=[self questionTurnFromTranscript:job[@"fallback"]];
      NSString *identity=[self normalisedQuestion:question];
      if(question.length && ![identity isEqualToString:self.lastAutoAsked ?: @""]) [self stageAutoQuestionTurnText:question];
      else self.autoLiveLabel.stringValue=success?@"AUTO • Đang nghe câu tiếp theo":@"AUTO • Apple Speech dự phòng";
    }
    self.autoTranscriptionInFlight=NO;
    [self drainAutoTranscriptionQueue];
}
- (void)drainAutoTranscriptionQueue {
    if(self.autoTranscriptionInFlight || !self.autoTranscriptionQueue.count) return;
    NSDictionary *job=self.autoTranscriptionQueue.firstObject; [self.autoTranscriptionQueue removeObjectAtIndex:0];
    if([job[@"generation"] unsignedIntegerValue]!=self.recognitionGeneration || !self.listening) { [self drainAutoTranscriptionQueue]; return; }
    self.autoTranscriptionInFlight=YES;
    NSMutableURLRequest *request=[self autoTranscriptionRequestForWAV:job[@"wav"]];
    __weak typeof(self) weak=self;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
      NSInteger code=[(NSHTTPURLResponse *)response statusCode];
      NSString *text=@"";
      if(!error && code>=200 && code<300 && data.length) {
        NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if([json[@"text"] isKindOfClass:NSString.class]) text=json[@"text"];
      }
      BOOL success=!error && code>=200 && code<300 && text.length>0;
      dispatch_async(dispatch_get_main_queue(), ^{ [weak finishEnhancedAutoTranscriptionJob:job transcript:text success:success]; });
    }] resume];
}
- (void)enqueueEnhancedAutoWAV:(NSData *)wav fallback:(NSString *)fallback {
    if(!wav.length) return;
    if(!self.autoTranscriptionQueue) self.autoTranscriptionQueue=[NSMutableArray array];
    [self.autoTranscriptionQueue addObject:@{ @"wav":wav, @"fallback":fallback ?: @"", @"generation":@(self.recognitionGeneration) }];
    self.autoLiveLabel.stringValue=@"AUTO • Đang làm rõ câu hỏi";
    [self drainAutoTranscriptionQueue];
}
- (void)tickAutoRecognition:(NSTimer *)timer {
    if(!self.listening || (self.autoButton && self.autoButton.state!=NSControlStateValueOn)) return;
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    if([self enhancedAutoTranscriptionEnabled]) {
      NSTimeInterval silentFor=MAX(0,self.audioTime-self.lastVoiceAudioTime);
      if(self.autoAudioBuffer.hasActiveUtterance && silentFor>=SCAutoUtteranceSilence) {
        NSData *wav=[self.autoAudioBuffer finishUtteranceWithMinimumDuration:0.55];
        NSString *fallback=[self.enhancedAutoTranscriptBuffer consume];
        if(wav.length) [self enqueueEnhancedAutoWAV:wav fallback:fallback];
      }
      NSArray *ready=[self.autoDetector tickWithAudioTime:self.audioTime now:now];
      [self consumeAutoCandidates:ready];
      [self flushAutoQuestionTurnIfReadyAt:now force:NO];
      [self refreshAutoLiveTranscript];
      return;
    }
    NSArray *ready=[self.autoDetector tickWithAudioTime:self.audioTime now:now];
    [self consumeAutoCandidates:ready];
    // Safety net for natural interview phrasing that ends as a question but
    // does not begin with a textbook interrogative (for example, “I'm curious
    // about your mise en place?”). The grammar detector remains primary; this
    // only commits a stable, clearly question-like pending turn.
    NSString *pending=self.autoDetector.pendingText ?: @"";
    NSTimeInterval stableFor=MAX(0,now-self.autoPendingChangedAt);
    NSTimeInterval fallbackDelay=self.manualSnapshotFinal?0.16:0.90;
    if(!ready.count && pending.length>=8 && stableFor>=fallbackDelay && [self looksLikeQuestion:pending] && [self contentTerms:pending].count) {
      [self.autoDetector discardPendingText];
      self.autoPendingSnapshot=@""; self.autoPendingChangedAt=now;
      [self stageAutoQuestionTurnText:pending];
    }
    [self flushAutoQuestionTurnIfReadyAt:now force:NO];
    [self refreshAutoLiveTranscript];
}
- (void)toggleAutoRecognition:(id)sender {
    if(self.autoButton.state==NSControlStateValueOn) {
      self.autoLiveLabel.stringValue=@"AUTO • Đang nhận diện";
    } else {
      // Turning AUTO off consumes only its own already-heard text.
      [self.autoDetector discardPendingText]; self.autoTranscript=@"";
      [self.enhancedAutoTranscriptBuffer consume]; [self.autoAudioBuffer reset];
      [self.autoTranscriptionQueue removeAllObjects];
      [self.autoTurnParts removeAllObjects]; self.autoTurnChangedAt=0;
      self.autoTranscriptView.string=@"AUTO đang tạm dừng.";
      self.autoLiveLabel.stringValue=@"AUTO • Tạm dừng";
    }
}
- (NSString *)currentBufferedTranscript {
    if(self.manualUsesUntimed) return self.manualUntimedBuffer.pendingText;
    return self.timeline?[self correctCulinaryTerms:[self.timeline textFrom:self.manualCursor to:DBL_MAX]]:(self.latestTranscript ?: @"");
}
- (void)commitCurrentQuestionFromSpace {
    if(!self.listening) { self.manualLiveLabel.stringValue=@"SPACE • Bấm Bắt đầu nghe trước"; return; }
    if(self.spaceCommitPending) [self finishSpaceCommit];
    NSString *visible=[self currentBufferedTranscript];
    if(self.manualUsesUntimed) {
      // Without word timing, Space means exactly the words currently shown.
      NSString *question=[self.manualUntimedBuffer consume];
      if(question.length) [self appendOfflineAnswerForQuestion:question];
      else self.manualLiveLabel.stringValue=@"SPACE • Chưa có câu hỏi để chốt";
      [self refreshManualTranscriptFinal:NO];
      return;
    }
    NSTimeInterval cutoff;
    @synchronized(self) { cutoff=self.audioTime; }
    if(cutoff<=self.manualCursor) return;
    self.pendingSpaceFrom=self.manualCursor; self.pendingSpaceTo=cutoff;
    self.spaceTranscriptSnapshot=visible;
    self.manualCursor=cutoff;
    self.spaceCommitPending=YES;
    [self.manualUntimedBuffer consume];
    self.spaceDeadlineTimer=[NSTimer scheduledTimerWithTimeInterval:1.20 target:self selector:@selector(finishSpaceCommit) userInfo:nil repeats:NO];
    if(self.manualSnapshotFinal) self.spaceSettleTimer=[NSTimer scheduledTimerWithTimeInterval:0.12 target:self selector:@selector(finishSpaceCommit) userInfo:nil repeats:NO];
    self.manualLiveLabel.stringValue=@"SPACE • Đã chốt • đang nhận nốt chữ cuối…";
    [self refreshManualTranscriptFinal:NO];
}
- (void)finishSpaceCommit {
    if(!self.spaceCommitPending) return;
    [self.spaceSettleTimer invalidate]; [self.spaceDeadlineTimer invalidate];
    NSString *q=[self correctCulinaryTerms:self.spaceTranscriptSnapshot ?: @""];
    self.spaceCommitPending=NO; self.spaceTranscriptSnapshot=@"";
    if(q.length) [self appendOfflineAnswerForQuestion:q];
    else self.manualLiveLabel.stringValue=@"SPACE • Chưa nhận được lời nói trước mốc chốt";
    [self.timeline pruneBefore:self.manualCursor];
}
- (BOOL)looksLikeQuestion:(NSString *)s {
    NSString *text=[s stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *pattern=@"(?i)^(?:(?:okay|ok|all right|alright|right|well|so|please|and|now|then|next question|let me ask|i(?:'d| would) like to (?:ask|know)|i want to know|i(?:'m| am) curious(?: about)?)[,.: ]+)*(?:what|which|why|how|when|where|who|whose|whom|in what ways|can|could|do|does|did|are|is|was|were|would|will|should|may|might|must|have|tell (?:me|us)|(?:walk|talk|take) (?:me|us) through|share|explain|list|name|describe|identify|give|outline|define|compare|discuss|provide|state|mention|show|design|distinguish|demonstrate)\\b";
    return [text rangeOfString:pattern options:NSRegularExpressionSearch].location!=NSNotFound ||
      [text hasSuffix:@"?"];
}
- (void)silenceReached:(NSTimer *)t { [self tickAutoRecognition:t]; }
- (void)autoSilenceReached:(NSTimer *)t { [self tickAutoRecognition:t]; }
- (void)processPendingQuestions {
    [self processQuestionText:[self currentBufferedTranscript]];
}
- (void)processQuestionText:(NSString *)text {
    NSString *q=[self primaryQuestionFromText:text];
    if(q.length) [self appendOfflineAnswerForQuestion:q];
}
- (NSSet<NSString *> *)contentTerms:(NSString *)text {
    text=[self correctCulinaryTerms:text ?: @""];
    NSSet *stop=[NSSet setWithArray:@[@"what",@"when",@"where",@"which",@"would",@"could",@"should",@"please",@"your",@"you",@"about",@"tell",@"have",@"with",@"that",@"this",@"from",@"they",@"them",@"think",@"important",@"does",@"into",@"are",@"the",@"and",@"for",@"um",@"uh",@"ah",@"yeah",@"okay",@"ok"]];
    NSCharacterSet *split=[[NSCharacterSet alphanumericCharacterSet] invertedSet]; NSMutableSet *terms=[NSMutableSet set];
    for (NSString *word in [text.lowercaseString componentsSeparatedByCharactersInSet:split]) if (word.length>2 && ![stop containsObject:word]) {
      NSString *w=word;
      if(w.length>5&&[w hasSuffix:@"ies"])w=[[w substringToIndex:w.length-3] stringByAppendingString:@"y"];
      else if(w.length>4&&[w hasSuffix:@"ing"])w=[w substringToIndex:w.length-3];
      else if(w.length>4&&[w hasSuffix:@"ed"])w=[w substringToIndex:w.length-2];
      else if(w.length>4&&[w hasSuffix:@"es"])w=[w substringToIndex:w.length-2];
      else if(w.length>3&&[w hasSuffix:@"s"]&&![w hasSuffix:@"ss"])w=[w substringToIndex:w.length-1];
      [terms addObject:w];
    }
    return terms;
}
- (NSString *)normalisedQuestion:(NSString *)text {
    NSString *canonical=[[self correctCulinaryTerms:text ?: @""] lowercaseString];
    canonical=[canonical stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en"]];
    NSArray *parts=[canonical componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    NSMutableArray *words=[NSMutableArray array];
    NSDictionary *spellings=@{@"organization":@"organisation",@"organizing":@"organising",@"organized":@"organised",@"color":@"colour",@"appetizer":@"appetiser"};
    for(NSString *word in parts) if(word.length) [words addObject:spellings[word] ?: word];
    return [words componentsJoinedByString:@" "];
}
- (NSUInteger)editDistance:(NSString *)a other:(NSString *)b {
    NSUInteger n=a.length,m=b.length; NSUInteger *prev=calloc(m+1,sizeof(NSUInteger)),*cur=calloc(m+1,sizeof(NSUInteger));
    for(NSUInteger j=0;j<=m;j++) prev[j]=j;
    for(NSUInteger i=1;i<=n;i++){cur[0]=i;unichar ca=[a characterAtIndex:i-1];for(NSUInteger j=1;j<=m;j++){NSUInteger cost=ca==[b characterAtIndex:j-1]?0:1;cur[j]=MIN(MIN(cur[j-1]+1,prev[j]+1),prev[j-1]+cost);}NSUInteger *tmp=prev;prev=cur;cur=tmp;}
    NSUInteger result=prev[m];free(prev);free(cur);return result;
}
- (NSArray<NSDictionary *> *)candidateSearchEntriesForQuestion:(NSString *)question {
    NSSet *terms=[self contentTerms:question];NSMutableOrderedSet *candidates=[NSMutableOrderedSet orderedSet];
    for(NSString *term in terms){NSArray *bucket=self.qaTermIndex[term];if(bucket.count)[candidates addObjectsFromArray:bucket];}
    return candidates.count?candidates.array:self.qaSearchEntries;
}
- (NSArray<NSDictionary *> *)rankedQuestionMatchesForQuestion:(NSString *)question {
    NSString *clean=[self correctCulinaryTerms:question ?: @""];
    NSSet *queryTerms=[self contentTerms:clean]; NSString *normalQuery=[self normalisedQuestion:clean];
    if(!normalQuery.length || !queryTerms.count) return @[];
    NSMutableArray *ranked=[NSMutableArray array];
    NSDictionary *exact=self.exactQAMemory[normalQuery];
    if(exact) [ranked addObject:@{@"entry":exact,@"score":@1.0,@"recall":@1.0,@"precision":@1.0,@"edit":@1.0,@"common":@(queryTerms.count),@"exact":@YES}];
    for(NSDictionary *searchEntry in [self candidateSearchEntriesForQuestion:clean]){
      NSDictionary *entry=searchEntry[@"entry"]; if(exact && [entry[@"question"] isEqualToString:exact[@"question"]]) continue;
      NSSet *candidateTerms=searchEntry[@"qterms"]; NSInteger common=0; for(NSString *term in queryTerms) if([candidateTerms containsObject:term]) common++;
      double recall=queryTerms.count?(double)common/queryTerms.count:0, precision=candidateTerms.count?(double)common/candidateTerms.count:0;
      double f1=(recall+precision)>0?2*recall*precision/(recall+precision):0; NSString *normalCandidate=searchEntry[@"normal"] ?: @"";
      NSUInteger maxLen=MAX(normalQuery.length,normalCandidate.length); double edit=maxLen?1.0-(double)[self editDistance:normalQuery other:normalCandidate]/maxLen:0;
      double score=(f1*0.58)+(edit*0.42); if([normalCandidate isEqualToString:normalQuery]) score=1;
      [ranked addObject:@{@"entry":entry,@"score":@(score),@"recall":@(recall),@"precision":@(precision),@"edit":@(edit),@"common":@(common),@"exact":@NO}];
    }
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[b[@"score"] compare:a[@"score"]];}];
    return ranked;
}
- (NSDictionary *)bestDisplayMatchForQuestion:(NSString *)question {
    NSArray *ranked=[self rankedQuestionMatchesForQuestion:question]; if(!ranked.count) return nil;
    NSDictionary *top=ranked.firstObject; double score=[top[@"score"] doubleValue], edit=[top[@"edit"] doubleValue]; NSInteger common=[top[@"common"] integerValue]; BOOL exact=[top[@"exact"] boolValue];
    double second=ranked.count>1?[ranked[1][@"score"] doubleValue]:0; double margin=score-second;
    BOOL confident=exact || score>=0.56 || (score>=0.42&&common>=2&&margin>=0.03) || (edit>=0.66&&common>=2);
    return confident?top[@"entry"]:nil;
}
- (NSString *)bestLocalAnswerForQuestion:(NSString *)question {
    self.lastMatchedQuestion=nil; self.lastMatchConfidence=0;
    if (!self.qaEntries.count) return @"TRẢ LỜI EN: The structured SA Cook Study question index is unavailable.";
    NSString *normalQuestion=[self normalisedQuestion:question];
    if ([@[@"what skills do you think are important for a prep cook",@"what skills are important for a prep cook",@"what are the important skills for a prep cook"] containsObject:normalQuestion]) { self.lastMatchedQuestion=@"Synthesis: prep cook skills from SA Cook Study"; self.lastMatchConfidence=1; return @"TRẢ LỜI EN: A prep cook needs strong knife skills, food-safety knowledge, organisation, time management, attention to detail, teamwork, and the ability to follow recipes consistently."; }
    if ([@[@"how do you ensure food safety in the kitchen",@"how do you maintain food safety in the kitchen"] containsObject:normalQuestion]) { self.lastMatchedQuestion=@"Synthesis: food safety procedures from SA Cook Study"; self.lastMatchConfidence=1; return @"TRẢ LỜI EN: I maintain personal hygiene, control food temperatures, prevent cross-contamination, store and label food correctly, clean and sanitise work areas, follow HACCP, and report hazards immediately."; }
    NSArray *ranked=[self rankedQuestionMatchesForQuestion:question]; NSDictionary *top=ranked.firstObject; if(!top) return @"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data.";
    NSDictionary *best=top[@"entry"]; double bestScore=[top[@"score"] doubleValue], bestRecall=[top[@"recall"] doubleValue], bestPrecision=[top[@"precision"] doubleValue], bestEdit=[top[@"edit"] doubleValue]; NSInteger bestCommon=[top[@"common"] integerValue]; BOOL exact=[top[@"exact"] boolValue];
    double second=ranked.count>1?[ranked[1][@"score"] doubleValue]:0; double margin=bestScore-second;
    BOOL clearWinner=exact || margin>=0.03 || bestScore>=0.72 || bestEdit>=0.78;
    BOOL reliable=best && (exact || (clearWinner && bestCommon>=2 && bestRecall>=0.80 && bestPrecision>=0.65 && bestScore>=0.76));
    // A missing/extra negation changes the meaning even when the wording is almost identical.
    BOOL queryNegative=[normalQuestion rangeOfString:@"\\b(?:not|never|avoid|without)\\b" options:NSRegularExpressionSearch].location!=NSNotFound;
    BOOL candidateNegative=[[self normalisedQuestion:best[@"question"]] rangeOfString:@"\\b(?:not|never|avoid|without)\\b" options:NSRegularExpressionSearch].location!=NSNotFound;
    if(queryNegative!=candidateNegative) reliable=NO;
    if (!reliable) { if(best){self.lastMatchedQuestion=best[@"question"]; self.lastMatchConfidence=bestScore;} return @"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data."; }
    self.lastMatchedQuestion=best[@"question"]; self.lastMatchConfidence=bestScore;
    return [@"TRẢ LỜI EN: " stringByAppendingString:best[@"answer"] ?: @""];
}
- (NSString *)displayQuestionForHeardQuestion:(NSString *)heard {
    // Make the on-screen wording quick to scan without ever substituting a
    // database question. The untouched heard text remains the answer query.
    NSString *corrected=[[self correctCulinaryTerms:heard ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!corrected.length) return @"";
    NSMutableArray<NSString *> *lines=[NSMutableArray array];
    for(NSString *sourceLine in [corrected componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *line=[sourceLine stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0,sourceLine.length)];
        line=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        while([line rangeOfString:@"^(?:okay|ok|alright|right|well|so|then|please|um|uh)[\\s,.:;!?-]+" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch].location!=NSNotFound)
            line=[line stringByReplacingOccurrencesOfString:@"^(?:okay|ok|alright|right|well|so|then|please|um|uh)[\\s,.:;!?-]+" withString:@"" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch range:NSMakeRange(0,line.length)];
        NSArray<NSString *> *clauses=[line componentsSeparatedByString:@"?"];
        if(clauses.count>1) {
            NSMutableArray<NSString *> *meaningful=[NSMutableArray array];
            NSMutableSet<NSString *> *seen=[NSMutableSet set];
            NSMutableSet<NSString *> *seenTopics=[NSMutableSet set];
            for(NSString *rawClause in clauses) {
                NSString *clause=[rawClause stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ,.:;!-\t\n"]];
                clause=[clause stringByReplacingOccurrencesOfString:@"^(?:okay|ok|alright|right|well|so|then|please|um|uh)[\\s,.:;!?-]+" withString:@"" options:NSRegularExpressionSearch|NSCaseInsensitiveSearch range:NSMakeRange(0,clause.length)];
                NSString *normal=[self normalisedQuestion:clause];
                NSArray *topicTerms=[[[self contentTerms:clause] allObjects] sortedArrayUsingSelector:@selector(compare:)];
                NSString *topic=[topicTerms componentsJoinedByString:@" "];
                if(!normal.length || !topic.length || [seen containsObject:normal] || [seenTopics containsObject:topic]) continue;
                [seen addObject:normal]; [seenTopics addObject:topic]; [meaningful addObject:clause];
            }
            if(meaningful.count) line=[[meaningful componentsJoinedByString:@"? "] stringByAppendingString:@"?"];
        }
        line=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if(line.length) {
            NSString *first=[[line substringToIndex:1] uppercaseString];
            line=[first stringByAppendingString:[line substringFromIndex:1]];
            unichar last=[line characterAtIndex:line.length-1];
            if(last!='?' && last!='.' && last!='!') line=[line stringByAppendingString:@"?"];
            [lines addObject:line];
        }
    }
    return [lines componentsJoinedByString:@"\n"];
}
- (NSString *)primaryQuestionFromText:(NSString *)text {
    return [[self correctCulinaryTerms:text ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
- (void)autoRecogniseCurrentQuestion {
    [self autoRecogniseQuestionText:self.autoTranscript ?: @""];
}
- (void)autoRecogniseQuestionText:(NSString *)text {
    [self autoRecogniseQuestionText:text fast:NO];
}
- (void)autoRecogniseQuestionText:(NSString *)text fast:(BOOL)fast {
    // The AUTO detector already established a question endpoint. Do not wait
    // for total sound silence or demand an exact database match a second time.
    NSString *q=[self primaryQuestionFromText:text];
    if(!q.length) return;
    NSString *displayQuestion=[self displayQuestionForHeardQuestion:q];
    [self ensureAnswerState];
    BOOL multipart=[q containsString:@"\n"];
    BOOL contextual=[self questionNeedsConversationContext:q];
    NSString *recent=[self recentAutoQuestionContext];
    BOOL synthesis=[self questionNeedsInterviewSynthesis:q] && self.keyField.stringValue.length>=20;
    NSString *raw=(multipart || contextual || synthesis)?@"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data.":[self bestLocalAnswerForQuestion:q];
    BOOL weak=multipart || contextual || synthesis || [raw containsString:@"No reliable match"] || !self.qaEntries.count;
    NSString *answer=[self conciseLocalAnswerFromResult:raw question:q];
    NSMutableDictionary *record=[@{@"question":displayQuestion.length?displayQuestion:q,@"answer":weak?@"Preparing an answer…":answer,@"state":weak?@"waiting":@"complete",@"lane":@"auto"} mutableCopy];
    if(weak && recent.length) {
      record[@"requestQuestion"]=[self contextualRequestForQuestion:q recentQuestions:recent];
      record[@"usedContext"]=@YES;
    } else if(![displayQuestion isEqualToString:q]) record[@"requestQuestion"]=q;
    [self.autoRecords addObject:record];
    self.lastAutoAsked=[self normalisedQuestion:q];
    [self refreshAutoAnswerPanel];
    if(weak) [self askAutoAIFallback:q heard:q];
}
- (BOOL)questionNeedsConversationContext:(NSString *)question {
    NSString *normal=[self normalisedQuestion:question];
    if(!normal.length) return NO;
    NSRegularExpression *reference=[NSRegularExpression regularExpressionWithPattern:@"\\b(?:that|this|those|these|them|there|its|same|former|latter|previous|above)\\b|\\b(?:store|cook|prepare|make|use|with|about|from|to)\\s+it\\b" options:NSRegularExpressionCaseInsensitive error:nil];
    if([reference firstMatchInString:normal options:0 range:NSMakeRange(0,normal.length)]) return YES;
    NSString *withoutFillers=[normal stringByReplacingOccurrencesOfString:@"^(?:okay|ok|so|and|please|right|well|then)\\s+" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,normal.length)];
    NSArray *vague=@[@"what are the ingredients",@"what ingredients",@"what do you have",@"do you have",@"what about",@"how about",@"and what",@"anything else",@"what else",@"why",@"and why",@"why is that",@"how so",@"and how",@"tell me more",@"can you explain more",@"what do you mean",@"what happens next"];
    for(NSString *phrase in vague) if([withoutFillers isEqualToString:phrase]) return YES;
    if([withoutFillers rangeOfString:@"^(?:what|which|how)\\s+(?:are|is|about|do you (?:have|use|put))?\\s*(?:the\\s+)?(?:ingredients?|sauce|dressing|method|temperature|time)\\b" options:NSRegularExpressionSearch].location!=NSNotFound && [self contentTerms:withoutFillers].count<=1) return YES;
    return NO;
}
- (BOOL)questionNeedsInterviewSynthesis:(NSString *)question {
    NSString *normal=[self normalisedQuestion:question];
    if(!normal.length) return NO;
    NSRegularExpression *behavioral=[NSRegularExpression regularExpressionWithPattern:@"\\b(?:tell me about|describe|give (?:me )?an example|have you ever|what would you do|how do you handle|how did you handle|how have you handled|why should we hire|why do you want|your (?:strengths?|weaknesses?))\\b" options:NSRegularExpressionCaseInsensitive error:nil];
    return [behavioral firstMatchInString:normal options:0 range:NSMakeRange(0,normal.length)]!=nil;
}
- (NSString *)recentQuestionContextForRecords:(NSArray<NSDictionary *> *)records {
    if(!records.count) return @"";
    NSMutableArray<NSString *> *turns=[NSMutableArray array];
    NSInteger start=MAX(0,(NSInteger)records.count-4);
    for(NSInteger i=start;i<(NSInteger)records.count;i++) {
      NSDictionary *record=records[(NSUInteger)i];
      NSString *request=[record[@"requestQuestion"] isKindOfClass:NSString.class]?record[@"requestQuestion"]:record[@"question"];
      NSString *question=[self heardQuestionFromRequest:request ?: @""];
      NSString *answer=[record[@"state"] isEqual:@"complete"]?record[@"answer"]:@"";
      if(answer.length>360) answer=[[answer substringToIndex:360] stringByAppendingString:@"…"];
      if(question.length) [turns addObject:answer.length?[NSString stringWithFormat:@"Previous question: %@\nPrevious answer: %@",question,answer]:[NSString stringWithFormat:@"Previous question: %@",question]];
    }
    return [turns componentsJoinedByString:@"\n---\n"];
}
- (NSString *)recentAutoQuestionContext { return [self recentQuestionContextForRecords:self.autoRecords]; }
- (NSString *)recentManualQuestionContext { return [self recentQuestionContextForRecords:self.manualRecords]; }
- (NSString *)contextualRequestForQuestion:(NSString *)question recentQuestions:(NSString *)recent {
    return [NSString stringWithFormat:@"<heard_question>\n%@\n</heard_question>\n<recent_questions>\n%@\n</recent_questions>",question,recent];
}
- (NSString *)textBetween:(NSString *)start and:(NSString *)end inString:(NSString *)text {
    NSRange first=[text rangeOfString:start]; if(first.location==NSNotFound) return nil;
    NSUInteger from=NSMaxRange(first); NSRange second=[text rangeOfString:end options:0 range:NSMakeRange(from,text.length-from)];
    if(second.location==NSNotFound) return nil;
    return [[text substringWithRange:NSMakeRange(from,second.location-from)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
- (NSString *)heardQuestionFromRequest:(NSString *)request {
    return [self textBetween:@"<heard_question>" and:@"</heard_question>" inString:request] ?: request;
}
- (NSString *)recentQuestionsFromRequest:(NSString *)request {
    return [self textBetween:@"<recent_questions>" and:@"</recent_questions>" inString:request] ?: @"";
}
- (NSString *)aiContextForQuestion:(NSString *)question {
    NSSet *query=[self contentTerms:question]; NSMutableArray *ranked=[NSMutableArray array];
    NSString *normalQuery=[self normalisedQuestion:question];
    for(NSDictionary *searchEntry in [self candidateSearchEntriesForQuestion:question]){NSDictionary *entry=searchEntry[@"entry"];NSSet *terms=searchEntry[@"qterms"];NSInteger common=0;for(NSString *t in query)if([terms containsObject:t])common++;
      double lexical=(query.count&&terms.count)?(double)common/sqrt((double)query.count*(double)terms.count):0;NSString *normal=searchEntry[@"normal"];NSUInteger maxLen=MAX(normalQuery.length,normal.length);double edit=maxLen?1.0-(double)[self editDistance:normalQuery other:normal]/maxLen:0;double score=lexical*0.75+edit*0.25;[ranked addObject:@{@"entry":entry,@"score":@(score)}];}
    [ranked sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[b[@"score"] compare:a[@"score"]];}];
    NSMutableString *context=[NSMutableString stringWithString:@"<context_questions>\n"];for(NSUInteger i=0;i<MIN((NSUInteger)2,ranked.count);i++){NSDictionary *e=ranked[i][@"entry"];NSString *a=e[@"answer"]?:@"";if(a.length>700)a=[a substringToIndex:700];[context appendFormat:@"Q: %@\nA: %@\n\n",e[@"question"],a];}[context appendString:@"</context_questions>\n<reference_docs>\n"];
    NSMutableArray *docs=[NSMutableArray array];for(NSDictionary *chunk in self.docChunks){NSSet *terms=chunk[@"terms"];NSInteger common=0;for(NSString *t in query)if([terms containsObject:t])common++;double score=(query.count&&terms.count)?(double)common/sqrt((double)query.count*(double)terms.count):0;[docs addObject:@{@"text":chunk[@"text"],@"score":@(score)}];}
    [docs sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){return[b[@"score"] compare:a[@"score"]];}];double topScore=ranked.count?[ranked[0][@"score"] doubleValue]:0;if(topScore<0.65&&docs.count&&[docs[0][@"score"] doubleValue]>0){NSString *text=docs[0][@"text"]?:@"";if(text.length>600)text=[text substringToIndex:600];[context appendFormat:@"%@\n\n",text];}[context appendString:@"</reference_docs>"];return context;
}
- (NSArray<NSString *> *)questionPartsForSynthesis:(NSString *)question {
    NSMutableArray *parts=[NSMutableArray array];
    for(NSString *line in [question componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
      NSString *clean=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if(clean.length) [parts addObject:clean];
    }
    return parts.count?parts:@[question ?: @""];
}
- (BOOL)questionPartsAreLinked:(NSArray<NSString *> *)parts {
    if(parts.count<2) return NO;
    for(NSUInteger index=1;index<parts.count;index++) {
      NSString *current=parts[index],*previous=parts[index-1];
      NSString *normal=[self normalisedQuestion:current],*previousNormal=[self normalisedQuestion:previous];
      if(!normal.length || [normal isEqualToString:previousNormal] || [self questionNeedsConversationContext:current]) return YES;
      NSSet *terms=[self contentTerms:current],*previousTerms=[self contentTerms:previous];
      NSUInteger common=0; for(NSString *term in terms) if([previousTerms containsObject:term]) common++;
      NSUInteger shorter=MIN(terms.count,previousTerms.count);
      if(common>=2 && shorter && (double)common/(double)shorter>=0.70) return YES;
      if([normal rangeOfString:@"\\b(?:ingredients?|sauce|dressing|method|temperature|time)\\b" options:NSRegularExpressionSearch].location!=NSNotFound && terms.count<=3 && common>=1) return YES;
    }
    return NO;
}
- (NSString *)aiContextForAllQuestionParts:(NSString *)question {
    return [self aiContextForAllQuestionParts:question relatedContext:@""];
}
- (NSString *)aiContextForAllQuestionParts:(NSString *)question relatedContext:(NSString *)related {
    NSArray<NSString *> *parts=[self questionPartsForSynthesis:question];
    if(parts.count<2) return [self aiContextForQuestion:related.length?[NSString stringWithFormat:@"%@ %@",question,related]:question];
    NSMutableString *context=[NSMutableString string];
    [parts enumerateObjectsUsingBlock:^(NSString *part,NSUInteger index,BOOL *stop) {
      NSString *query=related.length?[NSString stringWithFormat:@"%@ %@",part,related]:part;
      [context appendFormat:@"<part_%lu_reference>\n%@\n</part_%lu_reference>\n",(unsigned long)index+1,[self aiContextForQuestion:query],(unsigned long)index+1];
    }];
    return context;
}
- (NSAttributedString *)linkedText:(NSString *)text attributes:(NSDictionary *)attributes {
    NSMutableAttributedString *result=[[NSMutableAttributedString alloc] initWithString:text ?: @"" attributes:attributes ?: @{}];
    NSDataDetector *detector=[NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    for(NSTextCheckingResult *match in [detector matchesInString:result.string options:0 range:NSMakeRange(0,result.length)]) if(match.URL) {
      [result addAttributes:@{NSLinkAttributeName:match.URL,NSForegroundColorAttributeName:NSColor.systemBlueColor,NSUnderlineStyleAttributeName:@(NSUnderlineStyleSingle)} range:match.range];
    }
    return result;
}
- (void)showPanelQuestion:(NSString *)question answer:(NSString *)answer inTextView:(NSTextView *)view accentColor:(NSColor *)accent answerSize:(CGFloat)answerSize {
    if(!view) return;
    NSString *q=question ?: @"", *a=answer ?: @"";
    BOOL automatic=view==self.autoAnswerView;
    NSArray<NSDictionary *> *records=automatic?self.autoRecords:self.manualRecords;
    NSString *live=automatic?self.autoTranscriptView.string:self.transcriptView.string;
    // Keep the live interview readable without wasting vertical space. Section
    // breaks carry the hierarchy; individual speaker and body rows stay tight.
    NSMutableParagraphStyle *sectionStyle=[NSMutableParagraphStyle new]; sectionStyle.paragraphSpacing=3; sectionStyle.paragraphSpacingBefore=2;
    NSMutableParagraphStyle *questionStyle=[NSMutableParagraphStyle new]; questionStyle.lineSpacing=1.5; questionStyle.paragraphSpacing=5;
    NSMutableParagraphStyle *answerStyle=[NSMutableParagraphStyle new]; answerStyle.lineSpacing=MAX(1.5,answerSize*0.08); answerStyle.paragraphSpacing=6;
    NSMutableParagraphStyle *compactStyle=[NSMutableParagraphStyle new]; compactStyle.lineSpacing=1.5; compactStyle.paragraphSpacing=5;
    NSShadow *textShadow=[NSShadow new]; textShadow.shadowColor=[NSColor colorWithWhite:0 alpha:0.96]; textShadow.shadowBlurRadius=3.0; textShadow.shadowOffset=NSZeroSize;
    NSMutableAttributedString *display=[NSMutableAttributedString new];
    NSDictionary *sectionAttributes=@{NSFontAttributeName:[NSFont systemFontOfSize:10 weight:NSFontWeightBold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.66 alpha:1],NSKernAttributeName:@1.35,NSParagraphStyleAttributeName:sectionStyle,NSShadowAttributeName:textShadow};
    if(q.length) {
        [display appendAttributedString:[[NSAttributedString alloc] initWithString:[q stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:MAX(18,answerSize*0.76) weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[accent colorWithAlphaComponent:1],NSParagraphStyleAttributeName:questionStyle,NSShadowAttributeName:textShadow}]];
    }
    if(a.length) [display appendAttributedString:[self answerText:a attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:answerSize weight:NSFontWeightMedium],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.97 alpha:1],NSParagraphStyleAttributeName:answerStyle,NSShadowAttributeName:textShadow} question:q]];
    if(display.length) [display appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n" attributes:sectionAttributes]];
    [display appendAttributedString:[[NSAttributedString alloc] initWithString:@"LISTENING  •  " attributes:sectionAttributes]];
    [display appendAttributedString:[[NSAttributedString alloc] initWithString:(live.length?live:@"Waiting for the next question…") attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightRegular],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.82 alpha:1],NSParagraphStyleAttributeName:compactStyle,NSShadowAttributeName:textShadow}]];
    if(records.count>1) {
        CGFloat previousSize=MAX(15,answerSize*0.62);
        NSInteger first=MAX(0,(NSInteger)records.count-51);
        BOOL appendedHistory=NO;
        for(NSInteger i=(NSInteger)records.count-2;i>=first;i--) {
            NSDictionary *record=records[(NSUInteger)i];
            NSString *previousQuestion=[record[@"question"] isKindOfClass:NSString.class]?record[@"question"]:@"";
            NSString *previousAnswer=[record[@"answer"] isKindOfClass:NSString.class]?record[@"answer"]:@"";
            if(!previousQuestion.length || !previousAnswer.length) continue;
            if(!appendedHistory) {
                [display appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n\n" attributes:sectionAttributes]];
                appendedHistory=YES;
            }
            [display appendAttributedString:[[NSAttributedString alloc] initWithString:[previousQuestion stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:previousSize weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[accent colorWithAlphaComponent:0.92],NSParagraphStyleAttributeName:compactStyle,NSShadowAttributeName:textShadow}]];
            [display appendAttributedString:[self answerText:[previousAnswer stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:previousSize weight:NSFontWeightRegular],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.94 alpha:1],NSParagraphStyleAttributeName:compactStyle,NSShadowAttributeName:textShadow} question:previousQuestion]];
        }
    }
    if([view.textStorage isEqualToAttributedString:display]) return;
    BOOL sameQuestion=q.length && [view.string hasPrefix:[q stringByAppendingString:@"\n"]];
    NSPoint previous=view.enclosingScrollView.contentView.bounds.origin;
    [view.textStorage setAttributedString:display];
    [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    [view scrollPoint:sameQuestion?previous:NSZeroPoint];
    if(!sameQuestion && view.window.isVisible) {
      view.alphaValue=0.84;
      [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration=0.16;
        view.animator.alphaValue=1;
      } completionHandler:nil];
    }
}
- (void)appendHistoryQuestion:(NSString *)question answer:(NSString *)answer toTextView:(NSTextView *)view {
    if(!question.length || !answer.length || !view) return;
    if([answer.lowercaseString hasPrefix:@"preparing"] || [answer.lowercaseString containsString:@"waiting for a clearer"]) return;
    if([view.string hasPrefix:@"No previous conversation"] || [view.string hasPrefix:@"Chưa có lịch sử"]) view.string=@"";
    NSMutableParagraphStyle *style=[NSMutableParagraphStyle new]; style.lineSpacing=3; style.paragraphSpacing=10;
    CGFloat size=MAX(16,[self effectiveReadingFontSize]*0.68);
    NSColor *accent=[self laneAccent:view==self.autoHistoryView];
    NSMutableAttributedString *entry=[NSMutableAttributedString new];
    [entry appendAttributedString:[[NSAttributedString alloc] initWithString:[question stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[accent colorWithAlphaComponent:0.88],NSParagraphStyleAttributeName:style}]];
    [entry appendAttributedString:[self answerText:[answer stringByAppendingString:@"\n\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size weight:NSFontWeightRegular],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.96 alpha:1],NSParagraphStyleAttributeName:style} question:question]];
    [view.textStorage insertAttributedString:entry atIndex:0];
}
- (void)showCurrentQuestion:(NSString *)question answer:(NSString *)answer {
    [self showPanelQuestion:question answer:answer inTextView:self.currentAnswerView accentColor:[self laneAccent:NO] answerSize:[self effectiveReadingFontSize]];
}
- (void)showAutoQuestion:(NSString *)question answer:(NSString *)answer {
    [self showPanelQuestion:question answer:answer inTextView:self.autoAnswerView accentColor:[self laneAccent:YES] answerSize:[self effectiveReadingFontSize]];
}
- (void)ensureAnswerState {
    if(!self.manualRecords) self.manualRecords=[NSMutableArray array];
    if(!self.autoRecords) self.autoRecords=[NSMutableArray array];
    __weak typeof(self) weak=self;
    if(!self.manualAnswerLane) {
      self.manualAnswerLane=[[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question,SCAnswerCompletion completion) {
        [weak performAnswerRequest:question completion:completion];
      }];
      self.manualAnswerLane.onChange=^{ [weak refreshManualAnswerPanel]; };
      self.manualAnswerLane.onCacheChange=^{ [weak persistAnswerCache]; };
    }
    if(!self.autoAnswerLane) {
      self.autoAnswerLane=[[SCAnswerLane alloc] initWithRequestBlock:^(NSString *question,SCAnswerCompletion completion) {
        [weak performAnswerRequest:question completion:completion];
      }];
      self.autoAnswerLane.onChange=^{ [weak refreshAutoAnswerPanel]; };
      self.autoAnswerLane.onCacheChange=^{ [weak persistAnswerCache]; };
    }
}
- (NSString *)answerTextFromLocalResult:(NSString *)raw {
    NSString *prefix=@"TRẢ LỜI EN:";
    return [raw hasPrefix:prefix]?[[raw substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]:raw;
}
- (NSString *)effectiveAnswerPolicy {
    if(self.answerPolicy.length) return self.answerPolicy;
    // Keep this fallback in lockstep with Shared/answer-policy.txt.  The file is
    // bundled in release builds, while unit tests and damaged bundles exercise
    // this literal instead.
    return @"Use clear, natural CEFR B2 English with varied vocabulary and useful detail. Keep the answer easy to say aloud and focused on the exact question. Keep necessary cooking, food-safety, workplace, legal, and French culinary terms; explain uncommon technical words briefly when helpful. Use I, my, we, or our for actions, choices, experience, and opinions; state factual definitions directly. Provide two versions when the app asks for them: Short is normally under 28 words, and Full is normally under 85 words with the useful details. Do not invent past experience; when no real example is supplied, say what I would do.";
}
- (NSString *)answerByReplacingComplexPhrases:(NSString *)text {
    NSArray<NSArray<NSString *> *> *replacements=@[
      @[@"due to the fact that",@"because"],@[@"in order to",@"to"],@[@"prior to",@"before"],
      @[@"subsequently",@"then"],@[@"utilisation",@"use"],@[@"utilization",@"use"],
      @[@"utilising",@"using"],@[@"utilizing",@"using"],@[@"utilised",@"used"],@[@"utilized",@"used"],
      @[@"utilise",@"use"],@[@"utilize",@"use"],@[@"commence",@"start"],@[@"terminate",@"stop"],
      @[@"adhering to",@"following"],@[@"adhered to",@"followed"],@[@"adhere to",@"follow"],
      @[@"complying with",@"following"],@[@"complied with",@"followed"],@[@"comply with",@"follow"],
      @[@"dispose of",@"throw away"],@[@"discard",@"throw away"],@[@"facilitate",@"help"],
      @[@"at this point in time",@"now"]
    ];
    NSString *result=text ?: @"";
    for(NSArray<NSString *> *pair in replacements) {
      NSString *pattern=[NSString stringWithFormat:@"(?i)\\b%@\\b",[NSRegularExpression escapedPatternForString:pair[0]]];
      result=[result stringByReplacingOccurrencesOfString:pattern withString:pair[1] options:NSRegularExpressionSearch range:NSMakeRange(0,result.length)];
    }
    result=[result stringByReplacingOccurrencesOfString:@"[ \\t]+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0,result.length)];
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
- (NSArray<NSString *> *)answerWords:(NSString *)text {
    NSMutableArray<NSString *> *words=[NSMutableArray array];
    for(NSString *word in [(text ?: @"") componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]) if(word.length) [words addObject:word];
    return words;
}
- (NSUInteger)answerWordCount:(NSString *)text { return [self answerWords:text].count; }
- (BOOL)isCriticalAnswerToken:(NSString *)token {
    NSString *lower=[token.lowercaseString stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]];
    if([token rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet].location!=NSNotFound || [token containsString:@"°"] || [lower containsString:@"celsius"] || [lower containsString:@"fahrenheit"] || [lower hasPrefix:@"degree"]) return YES;
    NSSet<NSString *> *negation=[NSSet setWithArray:@[@"no",@"not",@"never",@"without",@"cannot",@"can't",@"don't",@"doesn't",@"didn't",@"isn't",@"aren't",@"wasn't",@"weren't",@"won't",@"wouldn't",@"shouldn't",@"mustn't"]];
    return [negation containsObject:lower];
}
- (BOOL)answerFragmentContainsCriticalFact:(NSString *)fragment {
    for(NSString *word in [self answerWords:fragment]) if([self isCriticalAnswerToken:word]) return YES;
    return NO;
}
- (NSString *)answerByRemovingOptionalCommaPhrases:(NSString *)content limit:(NSUInteger)limit {
    NSMutableArray<NSString *> *parts=[[[content componentsSeparatedByString:@","] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *part,NSDictionary *bindings) {
        (void)bindings;
        return [part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length>0;
    }]] mutableCopy];
    if(parts.count<3) return content;
    while([self answerWordCount:[parts componentsJoinedByString:@", "]]>limit && parts.count>2) {
      NSInteger choice=-1; NSUInteger shortest=NSUIntegerMax;
      for(NSUInteger index=1;index+1<parts.count;index++) {
        NSString *part=parts[index];
        if([self answerFragmentContainsCriticalFact:part]) continue;
        NSUInteger count=[self answerWordCount:part];
        if(count<shortest) { shortest=count; choice=(NSInteger)index; }
      }
      if(choice<0) break;
      [parts removeObjectAtIndex:(NSUInteger)choice];
    }
    NSString *result=[parts componentsJoinedByString:@", "];
    result=[result stringByReplacingOccurrencesOfString:@",\\s*(?:and|or)\\s*," withString:@", " options:NSRegularExpressionSearch range:NSMakeRange(0,result.length)];
    return result;
}
- (NSString *)answerByKeepingCompleteSentences:(NSString *)content limit:(NSUInteger)limit {
    if([self answerWordCount:content]<=limit) return content;
    NSMutableArray<NSString *> *sentences=[NSMutableArray array];
    [content enumerateSubstringsInRange:NSMakeRange(0,content.length) options:NSStringEnumerationBySentences usingBlock:^(NSString *substring,NSRange substringRange,NSRange enclosingRange,BOOL *stop) {
      (void)substringRange; (void)enclosingRange; (void)stop;
      NSString *sentence=[substring stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      if(sentence.length) [sentences addObject:sentence];
    }];
    if(sentences.count<2) return content;
    NSMutableArray<NSString *> *chosen=[NSMutableArray array];
    for(NSUInteger index=0;index<sentences.count;index++) {
      NSString *sentence=sentences[index];
      BOOL critical=[self answerFragmentContainsCriticalFact:sentence];
      NSString *candidate=[[chosen arrayByAddingObject:sentence] componentsJoinedByString:@" "];
      if([self answerWordCount:candidate]<=limit) [chosen addObject:sentence];
      else if(critical) {
        while(chosen.count && [self answerWordCount:[[chosen arrayByAddingObject:sentence] componentsJoinedByString:@" "]]>limit) [chosen removeLastObject];
        if([self answerWordCount:sentence]<=limit) [chosen addObject:sentence];
      }
    }
    return chosen.count?[chosen componentsJoinedByString:@" "]:content;
}
- (NSString *)answerUnitLimitedToPolicyWords:(NSString *)unit {
    NSString *prefix=@"",*content=[unit stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRegularExpression *number=[NSRegularExpression regularExpressionWithPattern:@"^(\\d+[.)])\\s*" options:0 error:nil];
    NSTextCheckingResult *match=[number firstMatchInString:content options:0 range:NSMakeRange(0,content.length)];
    if(match) { prefix=[[content substringWithRange:[match rangeAtIndex:1]] stringByAppendingString:@" "]; content=[content substringFromIndex:NSMaxRange(match.range)]; }
    content=[self answerByReplacingComplexPhrases:content];
    // Remove whole optional comma phrases before any hard cap.  This keeps the
    // sentence's grammar and avoids the old first-words-plus-late-number splice.
    content=[self answerByRemovingOptionalCommaPhrases:content limit:45];
    content=[self answerByKeepingCompleteSentences:content limit:45];
    NSMutableArray<NSString *> *words=[[self answerWords:content] mutableCopy];
    if(words.count>45) {
      // Last resort is one contiguous prefix, never non-adjacent word shards.
      // The semantic reducers above retain complete critical clauses whenever
      // the source can fit them within the spoken limit.
      words=[[words subarrayWithRange:NSMakeRange(0,45)] mutableCopy];
      NSString *last=words.lastObject ?: @"";
      if(![last hasSuffix:@"."] && ![last hasSuffix:@"?"] && ![last hasSuffix:@"!"]) {
        last=[last stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;:"]];
        if(last.length) words[words.count-1]=[last stringByAppendingString:@"."];
      }
    }
    NSString *answer=[words componentsJoinedByString:@" "];
    if(answer.length) {
      NSRange first=[answer rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet];
      if(first.location!=NSNotFound) answer=[answer stringByReplacingCharactersInRange:NSMakeRange(first.location,1) withString:[[answer substringWithRange:NSMakeRange(first.location,1)] uppercaseString]];
    }
    return [prefix stringByAppendingString:answer];
}
- (NSUInteger)requestedListItemCountForQuestion:(NSString *)question {
    NSString *normal=[self normalisedQuestion:question ?: @""];
    NSDictionary<NSString *,NSNumber *> *values=@{@"one":@1,@"two":@2,@"three":@3,@"four":@4,@"five":@5,@"six":@6,@"seven":@7,@"eight":@8,@"nine":@9,@"ten":@10};
    NSString *kinds=@"ways|signs|steps|principles|examples|types|things|methods|reasons|rules|points|indicators|parts|components|cuts|practices";
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:[NSString stringWithFormat:@"\\b(one|two|three|four|five|six|seven|eight|nine|ten|10|[1-9])\\s+(?:(?:main|quality|common|basic|important|different)\\s+){0,2}(?:%@)\\b",kinds] options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match=[pattern firstMatchInString:normal options:0 range:NSMakeRange(0,normal.length)];
    if(!match) return 0;
    NSString *token=[normal substringWithRange:[match rangeAtIndex:1]].lowercaseString;
    return values[token]?[values[token] unsignedIntegerValue]:(NSUInteger)token.integerValue;
}
- (NSString *)numberedAnswerFromItems:(NSArray<NSString *> *)sourceItems requestedCount:(NSUInteger)requestedCount {
    if(!requestedCount || sourceItems.count<requestedCount) return nil;
    NSMutableArray<NSMutableArray<NSString *> *> *items=[NSMutableArray arrayWithCapacity:requestedCount];
    NSCharacterSet *edge=[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n,;:.–—-"];
    for(NSUInteger index=0;index<requestedCount;index++) {
      NSString *item=[sourceItems[index] stringByTrimmingCharactersInSet:edge];
      item=[item stringByReplacingOccurrencesOfString:@"^(?i:and|or)\\s+" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,item.length)];
      NSMutableArray *words=[[self answerWords:item] mutableCopy];
      if(!words.count) return nil;
      [items addObject:words];
    }
    NSUInteger total=requestedCount;
    for(NSArray *words in items) total+=words.count;
    NSSet<NSString *> *optional=[NSSet setWithArray:@[@"very",@"really",@"properly",@"clearly",@"carefully",@"always",@"also",@"main",@"different",@"good"]];
    NSSet<NSString *> *listVerbs=[NSSet setWithArray:@[@"conduct",@"identify",@"establish",@"use",@"give",@"provide",@"include",@"includes"]];
    while(total>45) {
      BOOL removed=NO;
      for(NSMutableArray<NSString *> *words in items) if(words.count>2) {
        NSString *first=[words.firstObject.lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
        if([listVerbs containsObject:first]) { [words removeObjectAtIndex:0]; total--; removed=YES; break; }
      }
      if(removed) continue;
      for(NSMutableArray<NSString *> *words in items) {
        for(NSUInteger index=0;index<words.count && words.count>1;index++) {
          NSString *word=[words[index].lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
          if([optional containsObject:word]) { [words removeObjectAtIndex:index]; total--; removed=YES; break; }
        }
        if(removed) break;
      }
      if(removed) continue;
      NSMutableArray<NSString *> *longest=nil;
      for(NSMutableArray<NSString *> *words in items) if(words.count>1 && (!longest || words.count>longest.count)) longest=words;
      if(!longest) break;
      [longest removeLastObject]; total--;
    }
    NSMutableArray<NSString *> *numbered=[NSMutableArray arrayWithCapacity:requestedCount];
    for(NSUInteger index=0;index<items.count;index++) {
      NSString *item=[items[index] componentsJoinedByString:@" "];
      item=[item stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;:. "]];
      if(item.length) {
        NSRange first=[item rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet];
        if(first.location!=NSNotFound) item=[item stringByReplacingCharactersInRange:NSMakeRange(first.location,1) withString:[[item substringWithRange:NSMakeRange(first.location,1)] uppercaseString]];
      }
      [numbered addObject:[NSString stringWithFormat:@"%lu. %@%@",(unsigned long)(index+1),item,index+1==items.count?@".":@";"]];
    }
    NSString *result=[numbered componentsJoinedByString:@" "];
    return [self answerWordCount:result]<=45?result:nil;
}
- (NSString *)compactFreshFishAnswer:(NSString *)answer count:(NSUInteger)count {
    NSString *lower=answer.lowercaseString;
    if(![lower containsString:@"eyes"] || ![lower containsString:@"gills"] || ![lower containsString:@"flesh"]) return nil;
    NSMutableArray<NSString *> *items=[NSMutableArray array];
    if([lower containsString:@"clear"] && [lower containsString:@"eyes"]) [items addObject:@"clear, bright eyes"];
    if([lower containsString:@"gills"]) [items addObject:@"bright red or pink gills"];
    if([lower containsString:@"firm"] && [lower containsString:@"flesh"]) [items addObject:@"firm flesh that springs back"];
    if([lower containsString:@"smell"] || [lower containsString:@"scent"]) [items addObject:@"a mild, clean ocean smell"];
    NSRegularExpression *temperature=[NSRegularExpression regularExpressionWithPattern:@"-?\\d+(?:\\.\\d+)?\\s*[–—-]\\s*-?\\d+(?:\\.\\d+)?\\s*°?\\s*C" options:NSRegularExpressionCaseInsensitive error:nil];
    NSTextCheckingResult *match=[temperature firstMatchInString:answer options:0 range:NSMakeRange(0,answer.length)];
    if(match) {
      NSString *value=[answer substringWithRange:match.range];
      value=[value stringByReplacingOccurrencesOfString:@"\\s+" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,value.length)];
      [items addObject:[NSString stringWithFormat:@"%@ on arrival",value]];
    }
    if([lower containsString:@"shiny"] || [lower containsString:@"sheen"] || [lower containsString:@"scales"]) [items addObject:@"shiny skin with tight scales"];
    return [self numberedAnswerFromItems:items requestedCount:count];
}
- (NSString *)compactRequestedListAnswer:(NSString *)answer question:(NSString *)question count:(NSUInteger)count {
    NSString *normal=[self normalisedQuestion:question ?: @""];
    if(count==7 && [normal containsString:@"haccp"]) return [self numberedAnswerFromItems:@[@"hazard analysis",@"critical control points",@"critical limits",@"monitoring procedures",@"corrective actions",@"record keeping",@"verification procedures"] requestedCount:7];
    if([normal containsString:@"fish"]) {
      NSString *fish=[self compactFreshFishAnswer:answer count:count];
      if(fish.length) return fish;
    }
    NSString *content=[self answerByReplacingComplexPhrases:answer];
    NSRegularExpression *numberedPattern=[NSRegularExpression regularExpressionWithPattern:@"(?:^|\\s)\\d+[.)]\\s+" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *numberedMatches=[numberedPattern matchesInString:content options:0 range:NSMakeRange(0,content.length)];
    if(numberedMatches.count>=count) {
      NSMutableArray<NSString *> *numberedItems=[NSMutableArray arrayWithCapacity:count];
      for(NSUInteger index=0;index<count;index++) {
        NSUInteger start=NSMaxRange(numberedMatches[index].range);
        NSUInteger end=index+1<numberedMatches.count?numberedMatches[index+1].range.location:content.length;
        if(end>start) [numberedItems addObject:[content substringWithRange:NSMakeRange(start,end-start)]];
      }
      NSString *numbered=[self numberedAnswerFromItems:numberedItems requestedCount:count];
      if(numbered.length) return numbered;
    }
    NSRegularExpression *intro=[NSRegularExpression regularExpressionWithPattern:@"^(?i:.{0,80}?\\b(?:are|include|includes)\\b)\\s*:?[ \\t]*" options:0 error:nil];
    NSTextCheckingResult *introMatch=[intro firstMatchInString:content options:0 range:NSMakeRange(0,content.length)];
    if(introMatch && NSMaxRange(introMatch.range)<content.length) content=[content substringFromIndex:NSMaxRange(introMatch.range)];
    NSArray<NSString *> *parts=[content componentsSeparatedByString:@";"];
    if(parts.count<count) parts=[content componentsSeparatedByString:@","];
    if(parts.count<count) {
      NSString *expanded=[content stringByReplacingOccurrencesOfString:@",?\\s+and\\s+" withString:@", " options:NSRegularExpressionSearch range:NSMakeRange(0,content.length)];
      parts=[expanded componentsSeparatedByString:@","];
    }
    return [self numberedAnswerFromItems:parts requestedCount:count];
}
- (BOOL)questionNeedsFirstPersonAnswer:(NSString *)question {
    NSString *normal=[NSString stringWithFormat:@" %@ ",[self normalisedQuestion:question ?: @""]];
    return [normal containsString:@" you "] || [normal containsString:@" your "] || [normal containsString:@" yourself "] || [normal containsString:@" tell me "] || [normal containsString:@" describe a time "];
}
- (NSString *)firstPersonSentenceWhenSafe:(NSString *)sentence {
    NSString *trimmed=[sentence stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!trimmed.length) return trimmed;
    NSRegularExpression *prefixPattern=[NSRegularExpression regularExpressionWithPattern:@"^(\\d+[.)]\\s*)?" options:0 error:nil];
    NSTextCheckingResult *prefixMatch=[prefixPattern firstMatchInString:trimmed options:0 range:NSMakeRange(0,trimmed.length)];
    NSString *prefix=prefixMatch.range.length?[trimmed substringWithRange:prefixMatch.range]:@"";
    NSString *body=[trimmed substringFromIndex:prefixMatch.range.length];
    NSArray<NSString *> *words=[self answerWords:body];
    if(!words.count) return trimmed;
    NSUInteger verbIndex=0;
    NSString *first=[words[0].lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
    NSSet<NSString *> *adverbs=[NSSet setWithArray:@[@"always",@"never",@"first",@"then",@"next",@"finally"]];
    if([adverbs containsObject:first] && words.count>1) verbIndex=1;
    NSString *verb=[words[verbIndex].lowercaseString stringByTrimmingCharactersInSet:NSCharacterSet.punctuationCharacterSet];
    NSSet<NSString *> *imperatives=[NSSet setWithArray:@[@"participate",@"use",@"promote",@"develop",@"provide",@"give",@"show",@"explain",@"demonstrate",@"train",@"check",@"monitor",@"encourage",@"wash",@"clean",@"sanitise",@"sanitize",@"keep",@"store",@"label",@"wear",@"report",@"remove",@"separate",@"avoid",@"ask",@"listen",@"stay",@"follow",@"prepare",@"cook",@"place",@"put",@"stop",@"tell",@"inform",@"help",@"support",@"handle",@"treat",@"respect",@"organise",@"organize",@"prioritise",@"prioritize",@"make",@"do"]];
    if(![imperatives containsObject:verb]) return trimmed;
    NSRange letter=[body rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet];
    if(letter.location!=NSNotFound) body=[body stringByReplacingCharactersInRange:NSMakeRange(letter.location,1) withString:[[body substringWithRange:NSMakeRange(letter.location,1)] lowercaseString]];
    NSString *result=[NSString stringWithFormat:@"%@I %@",prefix,body];
    result=[result stringByReplacingOccurrencesOfString:@"(?i)^(\\d+[.)]\\s*)?I wash (?:the )?hands\\b" withString:[prefix stringByAppendingString:@"I wash my hands"] options:NSRegularExpressionSearch range:NSMakeRange(0,result.length)];
    return result;
}
- (NSString *)answerByUsingFirstPersonWhenSafe:(NSString *)answer question:(NSString *)question {
    if(![self questionNeedsFirstPersonAnswer:question]) return answer;
    NSMutableArray<NSString *> *sentences=[NSMutableArray array];
    [answer enumerateSubstringsInRange:NSMakeRange(0,answer.length) options:NSStringEnumerationBySentences usingBlock:^(NSString *substring,NSRange substringRange,NSRange enclosingRange,BOOL *stop) {
      (void)substringRange; (void)enclosingRange; (void)stop;
      NSString *ready=[self firstPersonSentenceWhenSafe:substring];
      if(ready.length) [sentences addObject:ready];
    }];
    return sentences.count?[sentences componentsJoinedByString:@" "]:answer;
}
- (NSString *)presenterReadyB1Answer:(NSString *)text {
    NSString *source=text ?: @"";
    NSString *normalised=[source stringByReplacingOccurrencesOfString:@"\\s+(?=\\d+[.)]\\s+)" withString:@"\n" options:NSRegularExpressionSearch range:NSMakeRange(0,source.length)];
    NSArray<NSString *> *lines=[normalised componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSRegularExpression *number=[NSRegularExpression regularExpressionWithPattern:@"^\\s*\\d+[.)]\\s+" options:0 error:nil];
    BOOL multipart=NO; for(NSString *line in lines) if([number firstMatchInString:line options:0 range:NSMakeRange(0,line.length)]) { multipart=YES; break; }
    NSMutableArray<NSString *> *units=[NSMutableArray array]; NSMutableString *current=[NSMutableString string];
    for(NSString *rawLine in lines) {
      NSString *line=[rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!line.length) continue;
      BOOL startsNumber=[number firstMatchInString:line options:0 range:NSMakeRange(0,line.length)]!=nil;
      if(multipart && startsNumber && current.length) { [units addObject:current.copy]; [current setString:@""]; }
      if(current.length) [current appendString:@" "]; [current appendString:line];
    }
    if(current.length) [units addObject:current.copy];
    if(!units.count) return @"";
    NSMutableArray<NSString *> *answers=[NSMutableArray arrayWithCapacity:units.count];
    for(NSString *unit in units) { NSString *limited=[self answerUnitLimitedToPolicyWords:unit]; if(limited.length) [answers addObject:limited]; }
    return [answers componentsJoinedByString:multipart?@"\n":@" "];
}
- (NSString *)presenterReadyB1Answer:(NSString *)text forQuestion:(NSString *)question {
    NSString *answer=[self answerByReplacingComplexPhrases:text ?: @""];
    NSString *normal=[self normalisedQuestion:question ?: @""];
    if([normal containsString:@"problems or misunderstandings"] && [normal containsString:@"cultural backgrounds"])
      return @"I communicate openly, ask respectful questions, avoid assumptions, and adapt my approach to each customer's or colleague's cultural needs.";
    if([normal containsString:@"sensitive"] && [normal containsString:@"cultural groups"])
      return @"It respects each person's dignity, creates an inclusive workplace, reduces misunderstandings, and supports anti-discrimination law.";
    if([normal containsString:@"train"] && [normal containsString:@"staff"] && ([normal containsString:@"safety"] || [normal containsString:@"hygiene"]))
      return @"I explain and demonstrate safe procedures, use checklists, observe staff, give constructive feedback, and encourage immediate hazard reporting.";
    answer=[self answerByUsingFirstPersonWhenSafe:answer question:question];
    NSUInteger requested=[self requestedListItemCountForQuestion:question];
    if(requested==3 && [normal containsString:@"cultural identity"])
      return [self numberedAnswerFromItems:@[@"ethnicity or nationality",@"language and traditions",@"religion or beliefs"] requestedCount:3];
    if(requested) {
      NSString *list=[self compactRequestedListAnswer:answer question:question count:requested];
      if(list.length) return list;
    }
    return [self presenterReadyB1Answer:answer];
}
- (NSString *)conciseLocalAnswerFromResult:(NSString *)raw question:(NSString *)question {
    NSString *answer=[self answerTextFromLocalResult:raw] ?: @"";
    return [self answerVariantsFromText:answer question:question];
}
- (NSString *)textByLimitingToWords:(NSString *)text count:(NSUInteger)limit {
    NSString *clean=[[text ?: @"" stringByReplacingOccurrencesOfString:@"\\s+" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0,(text ?: @"").length)] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!clean.length || !limit) return @"";
    NSArray<NSString *> *words=[clean componentsSeparatedByString:@" "];
    if(words.count<=limit) {
      unichar last=[clean characterAtIndex:clean.length-1];
      return [[NSCharacterSet characterSetWithCharactersInString:@".!?"] characterIsMember:last]?clean:[clean stringByAppendingString:@"."];
    }
    NSArray *kept=[words subarrayWithRange:NSMakeRange(0,limit)];
    NSString *out=[[kept componentsJoinedByString:@" "] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    out=[out stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@",;:"]];
    return [out stringByAppendingString:@"."];
}
- (NSDictionary<NSString *,NSString *> *)parseAnswerVariants:(NSString *)text {
    NSString *clean=[text ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!clean.length) return @{};
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"(?is)(?:^|\\n)\\s*(?:short(?:\\s+answer)?|short)\\s*:\\s*(.*?)(?:\\n\\s*(?:full(?:\\s+answer)?|full)\\s*:\\s*(.*))$" options:0 error:nil];
    NSTextCheckingResult *match=[regex firstMatchInString:clean options:0 range:NSMakeRange(0,clean.length)];
    if(match && match.numberOfRanges>=3) {
      NSString *shortText=[[clean substringWithRange:[match rangeAtIndex:1]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      NSString *fullText=[[clean substringWithRange:[match rangeAtIndex:2]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
      return @{@"short":shortText ?: @"",@"full":fullText ?: @""};
    }
    return @{@"full":clean};
}
- (NSString *)answerVariantsFromText:(NSString *)text question:(NSString *)question {
    NSDictionary *parsed=[self parseAnswerVariants:text];
    NSString *fullSource=([parsed[@"full"] length]?parsed[@"full"]:([parsed[@"short"] length]?parsed[@"short"]:(text ?: @"")));
    NSString *shortSource=([parsed[@"short"] length]?parsed[@"short"]:fullSource);
    NSString *shortAnswer=[self presenterReadyB1Answer:shortSource forQuestion:question];
    shortAnswer=[self textByLimitingToWords:shortAnswer count:28];
    NSString *fullAnswer=[self answerByReplacingComplexPhrases:fullSource ?: @""];
    fullAnswer=[self answerByUsingFirstPersonWhenSafe:fullAnswer question:question];
    fullAnswer=[self textByLimitingToWords:fullAnswer count:85];
    if(!shortAnswer.length && !fullAnswer.length) return @"";
    if(!fullAnswer.length || [[self normalisedQuestion:shortAnswer] isEqualToString:[self normalisedQuestion:fullAnswer]])
      return [NSString stringWithFormat:@"Short: %@",shortAnswer.length?shortAnswer:fullAnswer];
    return [NSString stringWithFormat:@"Short: %@\n\nFull: %@",shortAnswer,fullAnswer];
}
- (NSArray<NSString *> *)highlightTermsForQuestion:(NSString *)question answer:(NSString *)answer {
    NSMutableOrderedSet<NSString *> *terms=[NSMutableOrderedSet orderedSetWithArray:@[@"HACCP",@"FIFO",@"mise en place",@"à la carte",@"sous-vide",@"roux",@"béchamel",@"velouté",@"hollandaise",@"béarnaise",@"mirepoix",@"julienne",@"brunoise",@"bain-marie",@"cross-contamination",@"sanitising",@"sanitiser",@"stock",@"temperature",@"danger zone",@"chef's knife",@"grill",@"grilled",@"poultry",@"seafood"]];
    NSString *answerText=answer ?: @"";
    for(NSString *term in [self contentTerms:question ?: @""]) if(term.length>=4 && [answerText rangeOfString:term options:NSCaseInsensitiveSearch].location!=NSNotFound) [terms addObject:term];
    NSRegularExpression *numbers=[NSRegularExpression regularExpressionWithPattern:@"\\b\\d+(?:\\.\\d+)?\\s*(?:°\\s*)?[CF]\\b|\\b\\d+\\s*(?:minutes?|hours?)\\b" options:NSRegularExpressionCaseInsensitive error:nil];
    for(NSTextCheckingResult *match in [numbers matchesInString:[NSString stringWithFormat:@"%@ %@",question ?: @"",answer ?: @""] options:0 range:NSMakeRange(0,[[NSString stringWithFormat:@"%@ %@",question ?: @"",answer ?: @""] length])]) {
      [terms addObject:[[NSString stringWithFormat:@"%@ %@",question ?: @"",answer ?: @""] substringWithRange:match.range]];
    }
    NSMutableArray *present=[NSMutableArray array];
    for(NSString *term in terms) if(term.length && [answerText rangeOfString:term options:NSCaseInsensitiveSearch].location!=NSNotFound) [present addObject:term];
    [present sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){ return a.length<b.length?NSOrderedDescending:a.length>b.length?NSOrderedAscending:NSOrderedSame; }];
    return [present subarrayWithRange:NSMakeRange(0,MIN((NSUInteger)12,present.count))];
}
- (NSAttributedString *)answerText:(NSString *)text attributes:(NSDictionary *)attributes question:(NSString *)question {
    NSMutableAttributedString *result=[[self linkedText:text attributes:attributes] mutableCopy];
    NSFont *font=attributes[NSFontAttributeName] ?: [NSFont systemFontOfSize:18];
    NSFont *bold=[NSFont systemFontOfSize:font.pointSize weight:NSFontWeightBold];
    for(NSString *term in [self highlightTermsForQuestion:question answer:text]) {
      NSString *pattern=[NSString stringWithFormat:@"(?i)(^|[^\\p{L}\\p{N}])(%@)(?=$|[^\\p{L}\\p{N}])",[NSRegularExpression escapedPatternForString:term]];
      NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
      NSArray *matches=[regex matchesInString:result.string options:0 range:NSMakeRange(0,result.length)];
      for(NSTextCheckingResult *match in matches) if(match.numberOfRanges>2) [result addAttributes:@{NSFontAttributeName:bold,NSForegroundColorAttributeName:NSColor.whiteColor} range:[match rangeAtIndex:2]];
    }
    NSRegularExpression *labels=[NSRegularExpression regularExpressionWithPattern:@"(?m)^(Short|Full):" options:0 error:nil];
    for(NSTextCheckingResult *match in [labels matchesInString:result.string options:0 range:NSMakeRange(0,result.length)])
      [result addAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:MAX(10,font.pointSize*0.62) weight:NSFontWeightBold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.72 alpha:1],NSKernAttributeName:@1.0} range:match.range];
    return result;
}
- (void)renderHistoryRecords:(NSArray<NSDictionary *> *)records inView:(NSTextView *)view {
    if(!view) return;
    BOOL automatic=view==self.autoHistoryView;
    [self updateReadingHistoryButton:automatic];
    NSMutableArray *entries=[NSMutableArray array];
    for(NSInteger i=MAX(0,(NSInteger)records.count-51);i<(NSInteger)records.count-1;i++) {
        NSDictionary *record=records[(NSUInteger)i];
        [entries addObject:@{@"question":[record[@"question"] copy]?:@"",@"answer":[record[@"answer"] copy]?:@""}];
    }
    NSDictionary *state=@{@"entries":entries.copy,@"font":@([self effectiveReadingFontSize])};
    NSDictionary *previousState=automatic?self.autoHistoryRenderState:self.manualHistoryRenderState;
    if([state isEqual:previousState]) return;
    if(automatic) self.autoHistoryRenderState=state; else self.manualHistoryRenderState=state;
    // A new answer must not pull a reader away from an older answer in this lane.
    BOOL nativeView=[view isKindOfClass:NSTextView.class];
    NSPoint position=nativeView?view.enclosingScrollView.contentView.bounds.origin:NSZeroPoint;
    NSString *oldText=view.string.copy;
    view.string=@"";
    if(!entries.count) { view.string=@"No previous conversation yet."; return; }
    for(NSDictionary *record in entries) [self appendHistoryQuestion:record[@"question"] answer:record[@"answer"] toTextView:view];
    if(nativeView) {
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
        if(position.y>1 && oldText.length && ![oldText hasPrefix:@"No previous conversation"] && ![oldText hasPrefix:@"Chưa có lịch sử"]) {
            NSRange oldRange=[view.string rangeOfString:oldText];
            if(oldRange.location!=NSNotFound && oldRange.location>0) {
                NSUInteger glyph=[view.layoutManager glyphIndexForCharacterAtIndex:oldRange.location];
                position.y+=[view.layoutManager lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL].origin.y;
            }
        }
        [view scrollPoint:position];
    }
}
- (void)refreshManualAnswerPanel {
    NSDictionary *record=self.manualRecords.lastObject;
    if(record) {
      self.currentQuestion=record[@"question"]; self.currentAnswer=record[@"answer"];
      self.manualLiveLabel.stringValue=[record[@"state"] isEqual:@"complete"]?@"SPACE • Đã trả lời":[record[@"state"] isEqual:@"failed"]?@"SPACE • Lỗi AI — bấm Thử lại":@"SPACE • AI đang trả lời…";
      [self showCurrentQuestion:self.currentQuestion answer:self.currentAnswer];
    }
    [self renderHistoryRecords:self.manualRecords inView:self.answerView];
}
- (void)refreshAutoAnswerPanel {
    NSDictionary *record=self.autoRecords.lastObject;
    if(record) {
      self.autoQuestion=record[@"question"]; self.autoAnswer=record[@"answer"];
      BOOL contextual=[record[@"usedContext"] boolValue];
      self.autoLiveLabel.stringValue=[record[@"state"] isEqual:@"complete"]?(contextual?@"AUTO • Đã trả lời theo ngữ cảnh • tiếp tục nghe":@"AUTO • Đã trả lời • tiếp tục nghe"):[record[@"state"] isEqual:@"failed"]?@"AUTO • Lỗi AI — bấm Thử lại":(contextual?@"AUTO • Đang nối với câu trước…":@"AUTO • AI đang trả lời • tiếp tục nghe");
      [self showAutoQuestion:self.autoQuestion answer:self.autoAnswer];
    }
    [self renderHistoryRecords:self.autoRecords inView:self.autoHistoryView];
}
- (void)refreshAnswerPanels {
    [self refreshManualAnswerPanel]; [self refreshAutoAnswerPanel];
}
- (void)askAutoAIFallback:(NSString *)question heard:(NSString *)heard {
    [self startAnswerForRecord:self.autoRecords.lastObject];
}
- (void)askAIFallback:(NSString *)question {
    [self startAnswerForRecord:self.manualRecords.lastObject];
}
- (void)startAnswerForRecord:(NSMutableDictionary *)record {
    if(!record) return;
    [self ensureAnswerState];
    BOOL automatic=[record[@"lane"] isEqual:@"auto"];
    SCAnswerLane *lane=automatic?self.autoAnswerLane:self.manualAnswerLane;
    NSString *cacheKey=[self answerCacheKeyForRecord:record];
    if(self.keyField.stringValue.length<20 && ![lane.cache[cacheKey] length]) {
      record[@"answer"]=@"No reliable local answer. Add an active OpenAI API key using “AI key” to answer from your study data.";
      record[@"state"]=@"failed";
      if(automatic) [self refreshAutoAnswerPanel]; else [self refreshManualAnswerPanel];
      return;
    }
    [lane enqueueRecord:record cacheKey:cacheKey];
}
- (NSString *)answerCacheKeyForRecord:(NSDictionary *)record {
    NSString *request=[record[@"requestQuestion"] isKindOfClass:NSString.class]?record[@"requestQuestion"]:record[@"question"];
    return [self normalisedQuestion:request ?: @""];
}
- (void)persistAnswerCache {
    [[NSUserDefaults standardUserDefaults] setObject:self.manualAnswerLane.cache forKey:@"PresenterAI.answerCache.manual.v15"];
    [[NSUserDefaults standardUserDefaults] setObject:self.autoAnswerLane.cache forKey:@"PresenterAI.answerCache.auto.v15"];
}
- (void)retryManualAnswer:(id)sender {
    NSMutableDictionary *record=self.manualRecords.lastObject;
    if(!record || [@[@"waiting",@"loading"] containsObject:record[@"state"]]) return;
    [self.manualAnswerLane.cache removeObjectForKey:[self answerCacheKeyForRecord:record]];
    [self startAnswerForRecord:record];
}
- (void)retryAutoAnswer:(id)sender {
    NSMutableDictionary *record=self.autoRecords.lastObject;
    if(!record || [@[@"waiting",@"loading"] containsObject:record[@"state"]]) return;
    [self.autoAnswerLane.cache removeObjectForKey:[self answerCacheKeyForRecord:record]];
    [self startAnswerForRecord:record];
}
- (NSDictionary *)parsedAnswerData:(NSData *)data status:(NSInteger)code error:(NSError *)error {
    id parsed=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSDictionary *json=[parsed isKindOfClass:NSDictionary.class]?parsed:nil;
    NSDictionary *apiError=[json[@"error"] isKindOfClass:NSDictionary.class]?json[@"error"]:nil;
    NSString *errorText=[apiError[@"message"] isKindOfClass:NSString.class]?apiError[@"message"]:nil;
    if(error || code<200 || code>=300 || apiError) {
      NSString *detail=error.localizedDescription ?: errorText ?: @"The service could not complete the request.";
      return @{@"success":@NO,@"answer":[NSString stringWithFormat:@"AI request failed (HTTP %ld): %@",(long)code,detail]};
    }
    NSMutableArray *texts=[NSMutableArray array]; NSString *refusal=nil;
    id output=json[@"output"];
    if([output isKindOfClass:NSArray.class]) for(id item in output) if([item isKindOfClass:NSDictionary.class]) {
      id content=item[@"content"];
      if([content isKindOfClass:NSArray.class]) for(id part in content) if([part isKindOfClass:NSDictionary.class]) {
        if([part[@"type"] isEqual:@"output_text"] && [part[@"text"] isKindOfClass:NSString.class]) [texts addObject:part[@"text"]];
        if([part[@"type"] isEqual:@"refusal"] && [part[@"refusal"] isKindOfClass:NSString.class]) refusal=part[@"refusal"];
      }
    }
    NSString *answer=[[texts componentsJoinedByString:@"\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if([json[@"status"] isEqual:@"incomplete"]) return @{@"success":@NO,@"answer":answer.length?[answer stringByAppendingString:@"\n[Incomplete AI response — please retry.]"]:@"AI could not finish the answer. Please retry."};
    if([json[@"status"] isEqual:@"failed"] || !answer.length)
      return @{@"success":@NO,@"answer":refusal ?: @"AI returned no answer. Please retry; check the API connection if this continues."};
    return @{@"success":@YES,@"answer":answer};
}
- (NSDictionary *)answerRequestBodyForQuestion:(NSString *)question includeWebSearch:(BOOL)includeWebSearch {
    NSString *heard=[self heardQuestionFromRequest:question];
    NSString *recent=[self recentQuestionsFromRequest:question];
    NSArray<NSString *> *parts=[self questionPartsForSynthesis:heard];
    BOOL multipart=parts.count>1;
    BOOL linkedMultipart=multipart && [self questionPartsAreLinked:parts];
    NSString *multipartInstructions=linkedMultipart?@"Help with cook interview practice and presentation questions. Answer in English. The HEARD TURN contains linked, repeated, or clarifying question fragments from one speaking turn. Infer the single underlying request from all lines and RECENT CONVERSATION, then give ONE direct answer without numbering. Later fragments may clarify the subject instead of creating a new question.":@"Help with cook interview practice and presentation questions. Answer in English. The HEARD TURN contains multiple independent questions, one per line. Answer EVERY line in the same order, clearly numbered 1 and 2 (and onward). Do not merge, omit, or replace any subject.";
    NSMutableString *instructions=[NSMutableString stringWithString:multipart?multipartInstructions:@"Help with cook interview practice and presentation questions. Answer in English. The HEARD QUESTION is authoritative; a similar reference question must not replace its subject."];
    [instructions appendString:@" Return exactly two labelled sections: Short: and Full:. Short must be one direct answer the presenter can say immediately, normally under 28 words. Full must be a fuller answer with the useful details, normally under 85 words. Return only the words the presenter can say aloud after each label. Write actions, experience, choices, and opinions in the presenter's first person using I/my or we/our; state factual definitions directly. Never say 'you can say', 'I suggest', 'the answer is', 'according to the references', or explain how to answer. Use the provided local study references first. If they are insufficient, answer from reliable general culinary and workplace knowledge. Use web search only for a missing, niche, uncertain, or current fact. Never say that the references do not provide information when the question can be answered reliably. Correct or briefly clarify an obvious speech-recognition error when context makes the intended term clear. Do not invent uncertain details. No source labels in the answer text."];
    [instructions replaceOccurrencesOfString:@"Use one short sentence per numbered answer, with no more than 30 words per answer." withString:@"Use up to three concise sentences per numbered answer, with no more than 45 words per answer. Use clear, natural B2 vocabulary and enough relevant detail to make the answer complete." options:0 range:NSMakeRange(0,instructions.length)];
    [instructions replaceOccurrencesOfString:@"Give the direct answer in 1–2 short sentences and no more than 30 words." withString:@"Give the direct answer in two or three concise sentences and no more than 45 words. Use clear, natural B2 vocabulary and enough relevant detail to make the answer complete." options:0 range:NSMakeRange(0,instructions.length)];
    [instructions appendString:@" For a behavioral question, use the strongest concrete example supported by the local references or recent conversation and compress situation, task, action, and result into the same short limit. For a technical or role-specific question, answer the concept directly and mention a tradeoff only when the question asks for one or it is essential. When wording is vague, infer the competency or signal being evaluated and answer it confidently without sounding arrogant or robotic. If a crucial detail is genuinely missing, ask one short clarifying question; otherwise state one reasonable assumption and answer. When explicitly asked to suggest questions for the interviewer, offer two or three concise questions about the role, team, success criteria, product, or company."];
    // Both independent AUTO and SPACE lanes use this same request builder, so
    // the bundled cross-platform policy is mandatory on both AI paths.
    [instructions appendFormat:@"\n\nSHARED ANSWER POLICY — MANDATORY FOR AUTO AND SPACE:\n%@",[self effectiveAnswerPolicy]];
    if(recent.length) [instructions appendString:@" RECENT CONVERSATION is context only. Use its questions and answers to resolve words such as it, that, this, they, ingredients, or an omitted dish name. Prefer the most recent explicit subject, but look back through all supplied exchanges if the immediately previous question is also vague. Previous answers may be imperfect: use them only to identify the subject, and use REFERENCE DATA for factual content. Answer only the current HEARD QUESTION; never repeat the earlier questions."];
    NSString *conversation=recent.length?[NSString stringWithFormat:@"\n\nRECENT CONVERSATION — CONTEXT ONLY:\n%@",recent]:@"";
    NSNumber *outputLimit=linkedMultipart?@170:@(150*MAX((NSUInteger)1,parts.count));
    NSString *heardLabel=linkedMultipart?@"HEARD TURN — LINKED QUESTION FRAGMENTS":multipart?@"HEARD TURN — INDEPENDENT QUESTIONS":@"HEARD QUESTION";
    NSMutableDictionary *body=[@{@"model":@"gpt-4.1-mini",@"instructions":instructions,@"input":[NSString stringWithFormat:@"%@:\n%@%@\n\nLOCAL REFERENCE DATA:\n%@",heardLabel,heard,conversation,[self aiContextForAllQuestionParts:heard relatedContext:recent]],@"max_output_tokens":outputLimit,@"store":@NO} mutableCopy];
    if(includeWebSearch) {
      body[@"tools"]=@[@{@"type":@"web_search",@"search_context_size":@"low"}];
      body[@"tool_choice"]=@"auto";
      body[@"max_tool_calls"]=@1;
    }
    return body;
}
- (void)performAnswerRequest:(NSString *)question completion:(void (^)(NSString *,BOOL))completion {
    // This method is reached only after the instant local retrieval path was
    // unable to produce a reliable answer (or synthesis/context was required).
    NSDictionary *body=[self answerRequestBodyForQuestion:question includeWebSearch:NO];
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];
    request.HTTPMethod=@"POST"; request.timeoutInterval=25;
    request.HTTPBody=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:self.keyField.stringValue] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
      NSDictionary *parsed=[self parsedAnswerData:data status:[(NSHTTPURLResponse *)response statusCode] error:error];
      BOOL success=[parsed[@"success"] boolValue];
      NSString *answer=success?[self answerVariantsFromText:parsed[@"answer"] question:[self heardQuestionFromRequest:question]]:parsed[@"answer"];
      dispatch_async(dispatch_get_main_queue(), ^{ completion(answer,success); });
    }] resume];
}
- (void)appendOfflineAnswerForQuestion:(NSString *)question {
    [self ensureAnswerState];
    NSString *heard=[[self correctCulinaryTerms:question ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *displayQuestion=[self displayQuestionForHeardQuestion:heard];
    if(!heard.length || !displayQuestion.length) return;
    self.lastAsked=heard; self.historyCount++;
    BOOL contextual=[self questionNeedsConversationContext:heard];
    NSString *recent=[self recentManualQuestionContext];
    BOOL synthesis=[self questionNeedsInterviewSynthesis:heard] && self.keyField.stringValue.length>=20;
    NSString *raw=(contextual || synthesis)?@"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data.":[self bestLocalAnswerForQuestion:heard];
    BOOL weak=contextual || synthesis || [raw containsString:@"No reliable match"] || !self.qaEntries.count;
    NSString *answer=[self conciseLocalAnswerFromResult:raw question:heard];
    NSMutableDictionary *record=[@{@"question":displayQuestion,@"answer":weak?@"Preparing an answer…":answer,@"state":weak?@"waiting":@"complete",@"lane":@"manual"} mutableCopy];
    if(weak && recent.length) {
      record[@"requestQuestion"]=[self contextualRequestForQuestion:heard recentQuestions:recent];
      record[@"usedContext"]=@YES;
    } else if(![displayQuestion isEqualToString:heard]) record[@"requestQuestion"]=heard;
    [self.manualRecords addObject:record];
    [self refreshManualAnswerPanel];
    if(weak) [self askAIFallback:heard];
    else self.manualLiveLabel.stringValue=@"SPACE • Đã trả lời • chờ câu tiếp theo";
}
- (void)clearManualHistory:(id)sender {
    if(self.manualRecords.count>1) [self.manualRecords removeObjectsInRange:NSMakeRange(0,self.manualRecords.count-1)];
    [self refreshManualAnswerPanel];
}
- (void)copyConversationView:(NSTextView *)view name:(NSString *)name {
    NSString *text=view.string ?: @"";
    NSString *visible=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!visible.length) { [self setStatus:[NSString stringWithFormat:@"Chưa có nội dung %@ để sao chép",name] color:NSColor.systemOrangeColor]; return; }
    NSPasteboard *pasteboard=NSPasteboard.generalPasteboard;
    [pasteboard clearContents]; BOOL copied=[pasteboard setString:text forType:NSPasteboardTypeString];
    [self setStatus:copied?[NSString stringWithFormat:@"✓ Đã sao chép khung %@",name]:@"Không thể ghi vào clipboard" color:copied?NSColor.systemGreenColor:NSColor.systemRedColor];
}
- (void)copyAutoConversation:(id)sender { [self copyConversationView:self.autoAnswerView name:@"AUTO"]; }
- (void)copyManualConversation:(id)sender { [self copyConversationView:self.currentAnswerView name:@"SPACE"]; }
- (void)clearAutoHistory:(id)sender {
    if(self.autoRecords.count>1) [self.autoRecords removeObjectsInRange:NSMakeRange(0,self.autoRecords.count-1)];
    [self refreshAutoAnswerPanel];
}
- (void)clearHistory:(id)sender {
    [self clearManualHistory:sender]; [self clearAutoHistory:sender];
}
- (void)showErrorTitle:(NSString *)title detail:(NSString *)detail {
    [self setStatus:title color:NSColor.systemRedColor]; [self showUpdateAlert:title detail:detail];
}
- (void)setStatus:(NSString *)s color:(NSColor *)c { self.status.stringValue=s; self.status.toolTip=s; self.status.textColor=c; }
- (void)buildMenu {
    NSMenu *bar=[NSMenu new];
    NSMenuItem *appRoot=[[NSMenuItem alloc] initWithTitle:@"Presenter AI" action:nil keyEquivalent:@""]; NSMenu *appMenu=[NSMenu new]; appRoot.submenu=appMenu; [bar addItem:appRoot];
    [appMenu addItemWithTitle:@"Thoát Presenter AI" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *editRoot=[[NSMenuItem alloc] initWithTitle:@"Sửa" action:nil keyEquivalent:@""]; NSMenu *editMenu=[[NSMenu alloc] initWithTitle:@"Sửa"];
    editRoot.submenu=editMenu; [bar addItem:editRoot];
    [editMenu addItemWithTitle:@"Sao chép" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Chọn tất cả" action:@selector(selectAll:) keyEquivalent:@"a"];
    NSApp.mainMenu=bar;
}
- (void)applicationWillTerminate:(NSNotification *)n { if (self.spaceKeyMonitor) [NSEvent removeMonitor:self.spaceKeyMonitor]; if (self.listening) [self stopListening]; }
@end

int main(int argc,const char *argv[]){ @autoreleasepool { NSApplication *a=NSApplication.sharedApplication; [a setActivationPolicy:NSApplicationActivationPolicyAccessory]; AppDelegate *d=[AppDelegate new]; a.delegate=d; [a run]; } return 0; }
