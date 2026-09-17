#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <PDFKit/PDFKit.h>
#import <Security/Security.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#import <math.h>
#import <NaturalLanguage/NaturalLanguage.h>
#import <unistd.h>

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
@property NSMutableDictionary<NSString *,NSString *> *answerCache;
@property id spaceKeyMonitor;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMenu]; [self buildUI]; [self loadAudioDevices]; [self loadSavedAPIKey]; [self loadBundledKnowledge];
    __weak typeof(self) weakSelf=self;
    self.spaceKeyMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
      NSEventModifierFlags blocked = NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl;
      if (event.window == weakSelf.window && event.keyCode == 49 && (event.modifierFlags & blocked) == 0) {
        [weakSelf commitCurrentQuestionFromSpace];
        return nil;
      }
      return event;
    }];
    self.window.sharingType = NSWindowSharingNone;
    [NSApp activateIgnoringOtherApps:YES]; [self.window makeKeyAndOrderFront:nil];
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

- (void)checkForUpdates:(id)sender {
    NSString *current=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"0";
    NSString *updatesPath=@"/Users/trunghuy/Documents/Codex/2026-07-05/to/outputs";
    NSString *bestVersion=nil,*bestFile=nil;
    for(NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:updatesPath error:nil]){
      if(![name hasPrefix:@"SA-Cook-Assistant-v"]||![name.pathExtension.lowercaseString isEqualToString:@"zip"])continue;
      NSString *version=[[name stringByDeletingPathExtension] substringFromIndex:@"SA-Cook-Assistant-v".length];
      if([version compare:current options:NSNumericSearch]==NSOrderedDescending&&(!bestVersion||[version compare:bestVersion options:NSNumericSearch]==NSOrderedDescending)){bestVersion=version;bestFile=[updatesPath stringByAppendingPathComponent:name];}
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
        NSString *latest=[release[@"tag_name"] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"vV"]];
        if([latest compare:current options:NSNumericSearch]!=NSOrderedDescending){[self setStatus:@"✓ Ứng dụng đang ở bản mới nhất" color:NSColor.systemGreenColor];[self showUpdateAlert:@"Đã cập nhật" detail:[NSString stringWithFormat:@"Bạn đang dùng phiên bản %@.",current]];return;}
        NSURL *assetURL=nil;for(NSDictionary *asset in release[@"assets"]){NSString *name=asset[@"name"];if([name.pathExtension.lowercaseString isEqualToString:@"zip"]){assetURL=[NSURL URLWithString:asset[@"browser_download_url"]];break;}}
        if(!assetURL){[self showUpdateAlert:@"Release thiếu file ZIP" detail:@"Release mới phải có một asset .zip chứa SA Cook Assistant.app."];return;}
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

- (void)loadBundledKnowledge {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"sa-cook-knowledge" ofType:@"txt"];
    if (!path) return;
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!text.length) return;
    self.knowledge = text; self.knowledgeNames = @[@"SA Cook Study"];
    NSString *qaPath=[[NSBundle mainBundle] pathForResource:@"sa-cook-qa" ofType:@"json"];
    NSData *qaData=qaPath?[NSData dataWithContentsOfFile:qaPath]:nil; if (qaData) self.qaEntries=[NSJSONSerialization JSONObjectWithData:qaData options:0 error:nil];
    NSMutableArray *qa=[self.qaEntries mutableCopy]?:[NSMutableArray array];
    NSString *internetPath=[[NSBundle mainBundle] pathForResource:@"internet-qa" ofType:@"json"];NSData *internetData=internetPath?[NSData dataWithContentsOfFile:internetPath]:nil;id internetQA=internetData?[NSJSONSerialization JSONObjectWithData:internetData options:0 error:nil]:nil;if([internetQA isKindOfClass:NSArray.class])[qa addObjectsFromArray:internetQA];
    NSString *hintsPath=[[NSBundle mainBundle] pathForResource:@"speech-hints" ofType:@"txt"];NSString *hints=hintsPath?[NSString stringWithContentsOfFile:hintsPath encoding:NSUTF8StringEncoding error:nil]:nil;if(hints.length){NSMutableArray *items=[NSMutableArray array];for(NSString *line in [hints componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *item=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(item.length)[items addObject:item];}self.speechHints=items;}
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
    NSDictionary *savedCache=[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"PresenterAI.answerCache.v5"];self.answerCache=savedCache?[savedCache mutableCopy]:[NSMutableDictionary dictionary];
    self.englishEmbedding=[NLEmbedding sentenceEmbeddingForLanguage:NLLanguageEnglish];
    NSString *handbookPath=[[NSBundle mainBundle] pathForResource:@"sa-cook-handbook" ofType:@"txt"];
    NSString *handbook=handbookPath?[NSString stringWithContentsOfFile:handbookPath encoding:NSUTF8StringEncoding error:nil]:nil;
    if(handbook.length){NSMutableArray *chunks=[NSMutableArray array];NSMutableString *buffer=[NSMutableString string];for(NSString *line in [handbook componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){NSString *clean=[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(!clean.length)continue;[buffer appendFormat:@"%@ ",clean];if(buffer.length>=600){[chunks addObject:@{@"text":buffer.copy,@"terms":[self contentTerms:buffer]}];[buffer setString:@""];}}if(buffer.length)[chunks addObject:@{@"text":buffer.copy,@"terms":[self contentTerms:buffer]}];self.docChunks=chunks;}
    [self setStatus:[NSString stringWithFormat:@"✓ Bộ nhớ sẵn sàng • %lu câu • %lu biến thể • %lu thuật ngữ nghe",(unsigned long)self.qaEntries.count,(unsigned long)self.exactQAMemory.count,(unsigned long)self.speechHints.count] color:NSColor.systemGreenColor];
    self.topicField.stringValue = @"Phỏng vấn đánh giá kỹ năng nghề Cook/Chef, trả lời theo bộ SA Cook Study";
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)s { return YES; }

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *v = [NSTextField labelWithString:text];
    v.font = [NSFont systemFontOfSize:size weight:weight]; v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}
- (NSScrollView *)textBox:(NSTextView **)out editable:(BOOL)editable {
    NSScrollView *s = [[NSScrollView alloc] init]; s.translatesAutoresizingMaskIntoConstraints = NO;
    s.hasVerticalScroller = YES; s.borderType = NSNoBorder; s.wantsLayer=YES; s.layer.cornerRadius=13; s.layer.borderWidth=1; s.layer.borderColor=[NSColor colorWithWhite:0.32 alpha:0.65].CGColor; s.layer.masksToBounds=YES;
    NSTextView *t = [[NSTextView alloc] init]; t.editable = editable; t.richText = NO;
    t.font = [NSFont systemFontOfSize:16]; t.textContainerInset = NSMakeSize(12, 12);
    t.drawsBackground=YES; t.backgroundColor=[NSColor colorWithRed:0.085 green:0.07 blue:0.06 alpha:1]; t.textColor=[NSColor colorWithWhite:0.94 alpha:1]; t.insertionPointColor=NSColor.whiteColor;
    s.documentView = t; *out = t; return s;
}
- (void)buildUI {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1120,760)
      styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
      backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"SA Cook Assistant"; self.window.minSize = NSMakeSize(980,680); [self.window center];
    self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    NSView *root = [NSView new]; self.window.contentView = root;
    root.wantsLayer=YES; root.layer.backgroundColor=[NSColor colorWithRed:0.055 green:0.045 blue:0.04 alpha:1].CGColor;

    NSTextField *title = [self label:@"Gợi ý trả lời" size:24 weight:NSFontWeightBold];
    NSTextField *subtitle = [self label:@"2 bảng độc lập: AUTO tự nghe liên tục • SPACE để bạn tự chốt và so sánh" size:12 weight:NSFontWeightRegular]; subtitle.textColor=NSColor.secondaryLabelColor;
    NSTextField *version = [self label:[NSString stringWithFormat:@"v%@",[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@""] size:11 weight:NSFontWeightSemibold];version.textColor=[NSColor colorWithWhite:0.55 alpha:1];
    self.deviceButton = [[NSPopUpButton alloc] init]; self.deviceButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.status = [self label:@"● Sẵn sàng" size:12 weight:NSFontWeightSemibold];
    self.status.textColor = NSColor.secondaryLabelColor;self.status.drawsBackground=YES;self.status.backgroundColor=[NSColor colorWithRed:0.10 green:0.085 blue:0.075 alpha:1];self.status.wantsLayer=YES;self.status.layer.cornerRadius=10;
    self.levelLabel = [self label:@"Âm thanh: chưa đo" size:12 weight:NSFontWeightSemibold]; self.levelLabel.alignment=NSTextAlignmentRight; self.levelLabel.textColor=NSColor.secondaryLabelColor;
    self.keyField=[NSSecureTextField new]; self.topicField=[NSTextField new];
    self.listenButton = [NSButton buttonWithTitle:@"▶  Bắt đầu nghe" target:self action:@selector(toggleListening:)]; self.listenButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.listenButton.bezelStyle=NSBezelStyleRounded;self.listenButton.controlSize=NSControlSizeLarge;self.listenButton.bezelColor=NSColor.systemGreenColor;self.listenButton.font=[NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    self.commitButton = [NSButton buttonWithTitle:@"␣  Lấy gợi ý" target:self action:@selector(commitCurrentQuestionFromSpace)]; self.commitButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.commitButton.bezelStyle=NSBezelStyleRounded;self.commitButton.controlSize=NSControlSizeLarge;self.commitButton.bezelColor=NSColor.systemOrangeColor;self.commitButton.font=[NSFont systemFontOfSize:16 weight:NSFontWeightBold];
    self.autoButton = [NSButton new]; self.autoButton.state = NSControlStateValueOn;
    self.languageButton = [[NSPopUpButton alloc] init]; [self.languageButton addItemWithTitle:@"English (Australia)"];
    NSButton *clear = [NSButton buttonWithTitle:@"Xoá" target:self action:@selector(clearHistory:)]; clear.translatesAutoresizingMaskIntoConstraints=NO;
    NSButton *aiKey = [NSButton buttonWithTitle:@"AI key" target:self action:@selector(configureAI:)]; aiKey.translatesAutoresizingMaskIntoConstraints=NO;
    NSButton *update = [NSButton buttonWithTitle:@"Update" target:self action:@selector(checkForUpdates:)]; update.translatesAutoresizingMaskIntoConstraints=NO;
    NSTextField *spaceHelp = [self label:@"" size:1 weight:NSFontWeightRegular]; spaceHelp.textColor=NSColor.clearColor;
    NSTextField *heard = [self label:@"Đang nghe được" size:10 weight:NSFontWeightBold]; heard.textColor=[NSColor colorWithWhite:0.50 alpha:1];
    NSTextField *autoNow = [self label:@"AUTO - HỆ THỐNG TỰ NHẬN DIỆN" size:13 weight:NSFontWeightBold]; autoNow.textColor=[NSColor colorWithRed:0.52 green:0.74 blue:1.0 alpha:1];
    NSTextField *answerNow = [self label:@"SPACE - CÂU HỎI BẠN CHỐT" size:13 weight:NSFontWeightBold]; answerNow.textColor=NSColor.systemGreenColor;
    NSTextField *autoHistory = [self label:@"Lịch sử AUTO" size:11 weight:NSFontWeightBold]; autoHistory.textColor=[NSColor colorWithRed:0.52 green:0.74 blue:1.0 alpha:1];
    NSTextField *spaceHistory = [self label:@"Lịch sử SPACE" size:11 weight:NSFontWeightBold]; spaceHistory.textColor=NSColor.systemGreenColor;
    NSTextView *transcript = nil, *currentText=nil, *autoText=nil, *autoHistoryText=nil, *answerText = nil;
    NSScrollView *ts = [self textBox:&transcript editable:NO]; self.transcriptView = transcript; self.transcriptView.font=[NSFont systemFontOfSize:13 weight:NSFontWeightMedium]; self.transcriptView.string=@"Khi app nghe được câu hỏi, đoạn text sẽ hiện ở đây."; self.transcriptView.textColor=NSColor.secondaryLabelColor;
    NSScrollView *autoAS=[self textBox:&autoText editable:NO];autoAS.layer.borderColor=[NSColor colorWithRed:0.26 green:0.56 blue:1.0 alpha:0.80].CGColor;autoAS.layer.borderWidth=2; self.autoAnswerView=autoText;self.autoAnswerView.textContainerInset=NSMakeSize(18,18);self.autoAnswerView.backgroundColor=[NSColor colorWithRed:0.035 green:0.060 blue:0.120 alpha:1]; self.autoAnswerView.font=[NSFont systemFontOfSize:21 weight:NSFontWeightSemibold]; self.autoAnswerView.string=@"AUTO is listening independently.\n\nWhen it hears a full question, its answer appears here.";
    NSScrollView *currentAS=[self textBox:&currentText editable:NO];currentAS.layer.borderColor=[NSColor colorWithRed:0.24 green:0.78 blue:0.42 alpha:0.95].CGColor;currentAS.layer.borderWidth=2; self.currentAnswerView=currentText;self.currentAnswerView.textContainerInset=NSMakeSize(22,22);self.currentAnswerView.backgroundColor=[NSColor colorWithRed:0.035 green:0.115 blue:0.060 alpha:1]; self.currentAnswerView.font=[NSFont systemFontOfSize:24 weight:NSFontWeightSemibold]; self.currentAnswerView.string=@"Press Space to lock the current question.\n\nYour manual answer appears here.";
    NSScrollView *autoHS = [self textBox:&autoHistoryText editable:NO]; self.autoHistoryView=autoHistoryText; self.autoHistoryView.font=[NSFont systemFontOfSize:13]; self.autoHistoryView.backgroundColor=[NSColor colorWithRed:0.030 green:0.050 blue:0.090 alpha:1]; self.autoHistoryView.string=@"Chưa có lịch sử AUTO.\n";
    NSScrollView *as = [self textBox:&answerText editable:NO]; self.answerView = answerText; self.answerView.font=[NSFont systemFontOfSize:13]; self.answerView.backgroundColor=[NSColor colorWithRed:0.035 green:0.085 blue:0.050 alpha:1]; self.answerView.string = @"Chưa có lịch sử SPACE.\n";
    NSTextField *privacy = [self label:@"🔒 Private window • Local database + OpenAI synthesis" size:10 weight:NSFontWeightRegular]; privacy.textColor = NSColor.secondaryLabelColor;
    for (NSView *v in @[title,subtitle,version,self.deviceButton,update,aiKey,self.listenButton,clear,self.status,self.levelLabel,self.commitButton,heard,ts,autoNow,autoAS,answerNow,currentAS,autoHistory,autoHS,spaceHistory,as,privacy]) [root addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
      [title.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],[title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:22],
      [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:2],[subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [version.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[version.leadingAnchor constraintEqualToAnchor:title.trailingAnchor constant:8],
      [aiKey.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[aiKey.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[aiKey.widthAnchor constraintEqualToConstant:70],
      [update.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[update.trailingAnchor constraintEqualToAnchor:aiKey.leadingAnchor constant:-6],[update.widthAnchor constraintEqualToConstant:70],
      [self.deviceButton.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],[self.deviceButton.trailingAnchor constraintEqualToAnchor:update.leadingAnchor constant:-6],[self.deviceButton.widthAnchor constraintEqualToConstant:155],
      [self.status.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:12],[self.status.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.status.heightAnchor constraintEqualToConstant:28],[self.status.trailingAnchor constraintEqualToAnchor:self.levelLabel.leadingAnchor constant:-10],
      [self.levelLabel.centerYAnchor constraintEqualToAnchor:self.status.centerYAnchor],[self.levelLabel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[self.levelLabel.widthAnchor constraintEqualToConstant:220],
      [autoNow.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:14],[autoNow.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [answerNow.topAnchor constraintEqualToAnchor:autoNow.topAnchor],[answerNow.leadingAnchor constraintEqualToAnchor:autoAS.trailingAnchor constant:16],
      [autoAS.topAnchor constraintEqualToAnchor:autoNow.bottomAnchor constant:7],[autoAS.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[autoAS.widthAnchor constraintEqualToAnchor:currentAS.widthAnchor],
      [currentAS.topAnchor constraintEqualToAnchor:answerNow.bottomAnchor constant:7],[currentAS.leadingAnchor constraintEqualToAnchor:autoAS.trailingAnchor constant:16],[currentAS.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[currentAS.heightAnchor constraintEqualToConstant:300],
      [autoAS.heightAnchor constraintEqualToAnchor:currentAS.heightAnchor],
      [self.listenButton.topAnchor constraintEqualToAnchor:currentAS.bottomAnchor constant:12],[self.listenButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[self.listenButton.widthAnchor constraintEqualToConstant:220],[self.listenButton.heightAnchor constraintEqualToConstant:42],
      [self.commitButton.topAnchor constraintEqualToAnchor:self.listenButton.topAnchor],[self.commitButton.leadingAnchor constraintEqualToAnchor:self.listenButton.trailingAnchor constant:12],[self.commitButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[self.commitButton.heightAnchor constraintEqualToConstant:42],
      [heard.topAnchor constraintEqualToAnchor:self.listenButton.bottomAnchor constant:12],[heard.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [ts.topAnchor constraintEqualToAnchor:heard.bottomAnchor constant:5],[ts.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[ts.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-16],[ts.heightAnchor constraintEqualToConstant:42],
      [autoHistory.topAnchor constraintEqualToAnchor:ts.bottomAnchor constant:9],[autoHistory.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
      [spaceHistory.topAnchor constraintEqualToAnchor:autoHistory.topAnchor],[spaceHistory.leadingAnchor constraintEqualToAnchor:autoHS.trailingAnchor constant:16],
      [clear.centerYAnchor constraintEqualToAnchor:spaceHistory.centerYAnchor],[clear.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
      [autoHS.topAnchor constraintEqualToAnchor:autoHistory.bottomAnchor constant:6],[autoHS.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[autoHS.widthAnchor constraintEqualToAnchor:as.widthAnchor],[autoHS.bottomAnchor constraintEqualToAnchor:privacy.topAnchor constant:-12],
      [as.topAnchor constraintEqualToAnchor:spaceHistory.bottomAnchor constant:6],[as.leadingAnchor constraintEqualToAnchor:autoHS.trailingAnchor constant:16],[as.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],[as.bottomAnchor constraintEqualToAnchor:privacy.topAnchor constant:-12],
      [privacy.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],[privacy.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],[privacy.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-15]
    ]];
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
    self.speechCarry=@""; self.taskTranscript=@""; self.latestTranscript=@""; self.autoTranscript=@""; self.processedTranscriptLength=0;
    self.transcriptView.string=@"Đang nghe… bấm Space khi đã nghe đủ một câu hỏi.";
    self.transcriptView.textColor=NSColor.secondaryLabelColor;
    __weak typeof(self) weak = self;
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *b, AVAudioTime *t) {
      [weak.speechRequest appendAudioPCMBuffer:b];
      CFAbsoluteTime now=CFAbsoluteTimeGetCurrent(); if (now-weak.lastLevelUpdate < 0.18) return; weak.lastLevelUpdate=now;
      float **channels=b.floatChannelData; float rms=0; if (channels && b.frameLength) { float *samples=channels[0]; double sum=0; for (AVAudioFrameCount i=0;i<b.frameLength;i++) sum += samples[i]*samples[i]; rms=(float)sqrt(sum/b.frameLength); }
      float db=rms>0?20.0f*log10f(rms):-100.0f; NSInteger bars=(NSInteger)((db+60.0f)/5.0f); bars=MAX(0,MIN(10,bars));
      NSMutableString *meter=[NSMutableString string]; for(NSInteger i=0;i<10;i++) [meter appendString:i<bars?@"▮":@"▯"];
      NSString *level=bars? [NSString stringWithFormat:@"Âm thanh: %@ %.0f dB",meter,db] : @"Âm thanh: im lặng ▯▯▯▯▯▯▯▯▯▯";
      dispatch_async(dispatch_get_main_queue(), ^{ weak.levelLabel.stringValue=level; weak.levelLabel.textColor=bars?NSColor.systemGreenColor:NSColor.systemOrangeColor; });
    }];
    [self beginSpeechTask];
    CFAbsoluteTime started=CFAbsoluteTimeGetCurrent(); self.lastLevelUpdate=started;
    NSError *error; [self.audioEngine prepare];
    if (![self.audioEngine startAndReturnError:&error]) {
      NSString *help = error.code == 560227702 ? @"Mã !dev: thiết bị thu âm hiện tại không khả dụng. Vào System Settings → Sound → Input, chọn MacBook Microphone (không chọn thiết bị Bluetooth/Continuity đã ngắt), đóng các app độc quyền âm thanh rồi mở lại Presenter AI." : @"Kiểm tra micro trong System Settings → Sound → Input.";
      [self showErrorTitle:@"Không thể khởi động micro" detail:[NSString stringWithFormat:@"%@\n\n%@ (%@, mã %ld)", help, error.localizedDescription, error.domain, (long)error.code]]; return;
    }
    self.listening = YES; self.listenButton.title = @"■  Dừng nghe";self.listenButton.bezelColor=NSColor.systemRedColor; self.levelLabel.stringValue=@"Âm thanh: đang chờ BlackHole…"; [self setStatus:@"● Đang nghe • Space để lấy gợi ý" color:NSColor.systemRedColor];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      if (self.listening && self.lastLevelUpdate <= started) { self.levelLabel.stringValue=@"Âm thanh: không nhận được buffer từ BlackHole"; self.levelLabel.textColor=NSColor.systemRedColor; }
    });
}
- (void)beginSpeechTask {
    SFSpeechAudioBufferRecognitionRequest *request=[SFSpeechAudioBufferRecognitionRequest new]; request.shouldReportPartialResults=YES; request.taskHint=SFSpeechRecognitionTaskHintDictation;
    NSArray *defaultHints=@[@"mise en place",@"à la carte",@"consommé",@"sous-vide",@"julienne",@"brunoise",@"HACCP",@"FIFO"];
    NSArray *hints=self.speechHints.count?self.speechHints:defaultHints;
    if(hints.count>220) hints=[hints subarrayWithRange:NSMakeRange(0,220)];
    request.contextualStrings=hints;
    self.speechRequest=request; __weak typeof(self) weak=self;
    self.speechTask=[self.recognizer recognitionTaskWithRequest:request resultHandler:^(SFSpeechRecognitionResult *r, NSError *e) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (request != weak.speechRequest) return;
        if (r) [weak received:r.bestTranscription.formattedString final:r.isFinal];
        if (r.isFinal && weak.listening) { [weak carryCurrentSpeechSegment]; [weak restartSpeechTaskOnly]; return; }
        if (e && weak.listening) {
          if ([e.domain isEqualToString:@"kAFAssistantErrorDomain"] && e.code == 203) {
            [weak carryCurrentSpeechSegment];
            [weak setStatus:@"Speech timeout — đã giữ câu vừa nghe, đang nối lại…" color:NSColor.systemOrangeColor];
            [weak restartSpeechTaskOnly];
          } else {
            NSString *detail=[NSString stringWithFormat:@"%@ (%@, mã %ld)", e.localizedDescription, e.domain, (long)e.code];
            [weak stopListening]; [weak showErrorTitle:@"Speech Recognition gặp lỗi" detail:detail];
          }
        }
      });
    }];
}
- (void)restartSpeechTaskOnly {
    SFSpeechRecognitionTask *oldTask=self.speechTask; SFSpeechAudioBufferRecognitionRequest *oldRequest=self.speechRequest;
    self.speechRequest=nil; self.speechTask=nil; self.processedTranscriptLength=0; [oldRequest endAudio]; [oldTask cancel];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ if (self.listening) [self beginSpeechTask]; });
}
- (void)restartRecognition {
    NSString *preserved = self.latestTranscript;
    [self stopListening];
    self.latestTranscript = preserved;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 800*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [self startListening]; });
}
- (void)stopListening {
    self.listening = NO; [self.silenceTimer invalidate]; [self.autoTimer invalidate]; [self.audioEngine.inputNode removeTapOnBus:0]; [self.audioEngine stop]; [self.speechRequest endAudio]; [self.speechTask cancel];
    if (self.originalInputDevice != kAudioObjectUnknown) {
      AudioObjectPropertyAddress address={kAudioHardwarePropertyDefaultInputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
      AudioDeviceID restore=self.originalInputDevice; AudioObjectSetPropertyData(kAudioObjectSystemObject,&address,0,NULL,sizeof(restore),&restore); self.originalInputDevice=kAudioObjectUnknown;
    }
    self.levelLabel.stringValue=@"Âm thanh: đã dừng"; self.levelLabel.textColor=NSColor.secondaryLabelColor;
    self.listenButton.title = @"▶  Bắt đầu nghe";self.listenButton.bezelColor=NSColor.systemGreenColor; [self setStatus:@"● Đã dừng" color:NSColor.secondaryLabelColor];
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
      @"julian cut":@"julienne cut",@"julian":@"julienne",@"julien":@"julienne",@"julianne":@"julienne",
      @"bruno's":@"brunoise",@"brun noise":@"brunoise",
      @"sanitizing":@"sanitising",@"sanitize":@"sanitise",@"sanitizer":@"sanitiser",
      @"paltry":@"poultry",@"poetry seafood":@"poultry seafood",@"culture identity":@"cultural identity",@"culture background":@"cultural background",
      @"chief knife":@"chef knife",@"chef's nice":@"chef's knife",@"shift knife":@"chef knife"
    };
    for(NSString *wrong in aliases)[result replaceOccurrencesOfString:wrong withString:aliases[wrong] options:NSCaseInsensitiveSearch range:NSMakeRange(0,result.length)];
    return result;
}
- (void)received:(NSString *)text final:(BOOL)final {
    text=[self correctCulinaryTerms:text];
    self.taskTranscript = text ?: @"";
    NSString *carry=[self.speechCarry ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *task=[self.taskTranscript ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *combined = nil;
    if(carry.length && task.length){
      NSString *normalCarry=[self normalisedQuestion:carry], *normalTask=[self normalisedQuestion:task];
      if(normalTask.length && [normalTask hasPrefix:normalCarry]) combined=task;
      else if(normalCarry.length && [normalCarry hasSuffix:normalTask]) combined=carry;
      else combined=[NSString stringWithFormat:@"%@ %@",carry,task];
    } else combined=task.length?task:carry;
    combined = [[self correctCulinaryTerms:combined] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.latestTranscript = combined;
    self.transcriptView.string = combined.length ? combined : @"Đang nghe… bấm Space khi đã nghe đủ một câu hỏi.";
	    self.transcriptView.textColor = NSColor.secondaryLabelColor;
	    self.autoTranscript = combined;
	    [self.silenceTimer invalidate];
	    [self.autoTimer invalidate];
	    NSString *lower=combined.lowercaseString;NSUInteger words=[[combined componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count];
	    BOOL complex=words>10;for(NSString *start in @[@"in what ways",@"what are two things",@"how would you",@"describe how",@"explain how",@"tell me about",@"what steps",@"what factors",@"difference between"])if([lower containsString:start]){complex=YES;break;}
	    NSTimeInterval delay=final?0.25:(complex?1.45:0.95);
	    self.silenceTimer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(silenceReached:) userInfo:nil repeats:NO];
	    NSTimeInterval fastDelay=final?0.12:(complex?0.70:0.45);
	    self.autoTimer = [NSTimer scheduledTimerWithTimeInterval:fastDelay target:self selector:@selector(autoSilenceReached:) userInfo:nil repeats:NO];
	    if(words>=4) [self autoRecogniseQuestionText:combined fast:YES];
		}
- (void)carryCurrentSpeechSegment {
    NSString *segment = [self.taskTranscript ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!segment.length) return;
    NSString *carry = [self.speechCarry ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *normalCarry = [self normalisedQuestion:carry], *normalSegment = [self normalisedQuestion:segment];
    if (normalSegment.length && [normalCarry hasSuffix:normalSegment]) {
      self.taskTranscript = @""; self.latestTranscript = carry; return;
    }
    self.speechCarry = carry.length ? [NSString stringWithFormat:@"%@ %@", carry, segment] : segment;
    self.taskTranscript = @"";
    self.latestTranscript = [self.speechCarry stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	    if (self.latestTranscript.length) self.transcriptView.string = self.latestTranscript;
	}
- (NSString *)currentBufferedTranscript {
    NSString *carry=[self.speechCarry ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *task=[self.taskTranscript ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(carry.length && task.length){
      NSString *normalCarry=[self normalisedQuestion:carry], *normalTask=[self normalisedQuestion:task];
      if(normalTask.length && [normalCarry hasSuffix:normalTask]) return carry;
      if(normalCarry.length && [normalTask hasPrefix:normalCarry]) return task;
      return [[self correctCulinaryTerms:[NSString stringWithFormat:@"%@ %@",carry,task]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
    NSString *candidate=task.length?task:(carry.length?carry:(self.latestTranscript ?: @""));
    return [[self correctCulinaryTerms:candidate] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
- (double)questionScoreForTranscript:(NSString *)text {
    NSString *q=[self primaryQuestionFromText:text ?: @""]; if(!q.length) return 0;
    NSArray *ranked=[self rankedQuestionMatchesForQuestion:q]; double score=ranked.count?[ranked[0][@"score"] doubleValue]:0;
    if([self looksLikeQuestion:q]) score += 0.12;
    NSUInteger words=[[q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count];
    if(words>=3) score += 0.03; if(words>32) score -= 0.08;
    return score;
}
- (NSString *)betterTranscriptFromImmediate:(NSString *)immediate delayed:(NSString *)delayed {
    NSString *a=[[self correctCulinaryTerms:immediate ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *b=[[self correctCulinaryTerms:delayed ?: @""] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if(!a.length) return b; if(!b.length) return a;
    double sa=[self questionScoreForTranscript:a], sb=[self questionScoreForTranscript:b];
    if(sb>=sa+0.06) return b;
    if(sa>=sb+0.03) return a;
    NSString *na=[self normalisedQuestion:a], *nb=[self normalisedQuestion:b];
    NSUInteger aw=[[a componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count], bw=[[b componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count];
    if([nb hasPrefix:na] && bw<=aw+8) return b;
    if(bw>aw+8) return a;
    return b.length>=a.length?b:a;
}
- (void)commitCurrentQuestionFromSpace {
    if (self.spaceCommitPending) return;
    self.spaceCommitPending=YES;
    NSString *visible=[self.transcriptView.string ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    BOOL placeholder=(!visible.length || [visible hasPrefix:@"Đang nghe"] || [visible hasPrefix:@"Đã chốt"] || [visible hasPrefix:@"Khi app"]);
    self.spaceTranscriptSnapshot=placeholder?[self currentBufferedTranscript]:visible;
    [self finishSpaceCommit];
}
- (void)finishSpaceCommit {
    self.spaceCommitPending=NO;
    [self.silenceTimer invalidate];
    [self.autoTimer invalidate];
    NSString *q = [[self correctCulinaryTerms:self.spaceTranscriptSnapshot ?: [self currentBufferedTranscript]] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.spaceTranscriptSnapshot=@"";
    if (!q.length || [q isEqualToString:@"Đang nghe… bấm Space khi đã nghe đủ một câu hỏi."]) {
      [self setStatus:self.listening?@"Chưa nghe được câu hỏi nào để chốt":@"Bấm Bắt đầu trước, rồi dùng Space để chốt câu hỏi" color:NSColor.systemOrangeColor];
      return;
    }
    BOOL looksLikeQuestion=[self looksLikeQuestion:q];
    if (!looksLikeQuestion) [self setStatus:@"Đoạn vừa nghe chưa rõ dạng câu hỏi — vẫn đang tìm đáp án" color:NSColor.systemOrangeColor];
    if(looksLikeQuestion) [self processQuestionText:q];
    else [self appendOfflineAnswerForQuestion:q];
    self.speechCarry=@""; self.taskTranscript=@""; self.latestTranscript=@""; self.autoTranscript=@""; self.processedTranscriptLength=0;
    self.transcriptView.string=@"Đã chốt câu hỏi. Đang nghe câu tiếp theo…";
    self.transcriptView.textColor=NSColor.secondaryLabelColor;
    if (self.listening) [self restartSpeechTaskOnly];
}
- (BOOL)looksLikeQuestion:(NSString *)s {
    NSString *x = s.lowercaseString; if ([x hasSuffix:@"?"]) return YES;
    for (NSString *w in @[@"tại sao",@"vì sao",@"như thế nào",@"bao nhiêu",@"khi nào",@"ở đâu",@"là gì",@"có thể",@"bạn nghĩ",@"cho biết",@"what ",@"why ",@"how ",@"when ",@"where ",@"who ",@"can you",@"could you",@"do you",@"did you",@"are you",@"would you",@"tell me",@"explain",@"list ",@"name ",@"describe ",@"identify ",@"give ",@"outline ",@"define ",@"compare ",@"discuss ",@"provide ",@"state ",@"mention ",@"show ",@"design "]) if ([x containsString:w]) return YES;
    return NO;
}
- (void)silenceReached:(NSTimer *)t {
    [self.autoTimer invalidate];
    [self carryCurrentSpeechSegment];
    [self autoRecogniseCurrentQuestion];
}
- (void)autoSilenceReached:(NSTimer *)t {
    NSString *source = self.autoTranscript.length ? self.autoTranscript : (self.latestTranscript ?: @"");
    NSString *candidate=[source stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self autoRecogniseQuestionText:candidate fast:YES];
}
- (void)processPendingQuestions {
    NSString *full=self.latestTranscript ?: @""; if (!full.length) return;
    [self processQuestionText:full];
}
- (void)processQuestionText:(NSString *)text {
    NSString *fresh=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!fresh.length) return;
    NSArray *parts=[fresh componentsSeparatedByString:@"?"]; BOOL hadQuestionMark=[fresh containsString:@"?"];
    if(!hadQuestionMark){
      NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"(?i)\\b(?:what|which|why|how|when|where|who|can you|could you|do you|did you|are you|would you|list|name|describe|explain|identify|give|outline|define|compare|discuss|provide|state)\\b" options:0 error:nil];
      NSArray<NSTextCheckingResult *> *matches=[re matchesInString:fresh options:0 range:NSMakeRange(0,fresh.length)];
      if(matches.count>1){NSMutableArray *split=[NSMutableArray array];NSUInteger start=matches[0].range.location;for(NSUInteger m=1;m<matches.count;m++){NSUInteger next=matches[m].range.location;NSString *candidate=[fresh substringWithRange:NSMakeRange(start,next-start)];NSUInteger words=[[candidate componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count];if(words>=4){[split addObject:candidate];start=next;}}[split addObject:[fresh substringFromIndex:start]];parts=split;}
    }
    for (NSUInteger i=0;i<parts.count;i++) {
      NSString *q=[parts[i] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if (!q.length) continue;
      if (hadQuestionMark && i<parts.count-1) q=[q stringByAppendingString:@"?"];
      if ([self looksLikeQuestion:q] && ![q isEqualToString:self.lastAsked]) [self appendOfflineAnswerForQuestion:q];
    }
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
    NSMutableString *canonical=[[self correctCulinaryTerms:text ?: @""] mutableCopy];
    [canonical setString:canonical.lowercaseString];
    NSDictionary *aliases=@{@"sanitizing":@"sanitising",@"sanitize":@"sanitise",@"sanitized":@"sanitised",@"organization":@"organisation",@"organizing":@"organising",@"organized":@"organised",@"color":@"colour",@"appetizer":@"appetiser",@"mise and place":@"mise en place",@"missing place":@"mise en place",@"means in place":@"mise en place",@"meat in place":@"mise en place",@"mise place":@"mise en place",@"a la cart":@"a la carte",@"sue vide":@"sous vide",@"sous-vide":@"sous vide",@"julian":@"julienne",@"julien":@"julienne",@"julianne":@"julienne",@"paltry":@"poultry",@"culture identity":@"cultural identity",@"culture background":@"cultural background",@"chief knife":@"chef knife",@"chef s knife":@"chef knife",@"chef's knife":@"chef knife"};
    for(NSString *from in aliases)[canonical replaceOccurrencesOfString:from withString:aliases[from] options:NSCaseInsensitiveSearch range:NSMakeRange(0,canonical.length)];
    NSArray *parts=[canonical componentsSeparatedByCharactersInSet:[[NSCharacterSet alphanumericCharacterSet] invertedSet]];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *s,NSDictionary *b){return s.length>0;}]] componentsJoinedByString:@" "];
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
    NSString *lowerQuestion=question.lowercaseString;
    if ([lowerQuestion containsString:@"prep cook"] && [lowerQuestion containsString:@"skill"]) { self.lastMatchedQuestion=@"Synthesis: prep cook skills from SA Cook Study"; self.lastMatchConfidence=1; return @"TRẢ LỜI EN: Important skills for a prep cook include good knife skills, food safety and hygiene, mise en place, time management, organisation, attention to detail, teamwork, and the ability to follow standard recipes and instructions."; }
    if ([lowerQuestion containsString:@"food safety"] && ([lowerQuestion containsString:@"ensure"]||[lowerQuestion containsString:@"look after"]||[lowerQuestion containsString:@"maintain"]||[lowerQuestion containsString:@"kitchen"])) { self.lastMatchedQuestion=@"Synthesis: food safety procedures from SA Cook Study"; self.lastMatchConfidence=1; return @"TRẢ LỜI EN: I ensure food safety by maintaining good personal hygiene, keeping cold food below 5°C and hot food above 60°C, cooking food to safe internal temperatures, preventing cross-contamination with separate colour-coded equipment, storing and labelling food correctly, cleaning and sanitising work areas, following HACCP procedures, and reporting hazards immediately."; }
    NSSet *queryTerms=[self contentTerms:question]; NSArray *ranked=[self rankedQuestionMatchesForQuestion:question]; NSDictionary *top=ranked.firstObject; if(!top) return @"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data.";
    NSDictionary *best=top[@"entry"]; double bestScore=[top[@"score"] doubleValue], bestRecall=[top[@"recall"] doubleValue], bestPrecision=[top[@"precision"] doubleValue], bestEdit=[top[@"edit"] doubleValue]; NSInteger bestCommon=[top[@"common"] integerValue]; BOOL exact=[top[@"exact"] boolValue];
    double second=ranked.count>1?[ranked[1][@"score"] doubleValue]:0; double margin=bestScore-second;
    BOOL shortUsefulPartial=best && queryTerms.count<=3 && bestCommon>=2 && bestRecall>=0.66 && bestScore>=0.42;
    BOOL clearWinner=exact || margin>=0.03 || bestScore>=0.72 || bestEdit>=0.78;
    BOOL reliable=best && clearWinner && (bestEdit>=0.76 || (bestCommon>=2&&bestRecall>=0.65&&bestPrecision>=0.45) || (bestCommon>=3&&bestScore>=0.60) || shortUsefulPartial);
    if (!reliable) { if(best){self.lastMatchedQuestion=best[@"question"]; self.lastMatchConfidence=bestScore;} return @"TRẢ LỜI EN: No reliable match was found in the SA Cook Study data."; }
    self.lastMatchedQuestion=best[@"question"]; self.lastMatchConfidence=bestScore;
    return [@"TRẢ LỜI EN: " stringByAppendingString:best[@"answer"] ?: @""];
}
- (NSString *)displayQuestionForHeardQuestion:(NSString *)heard {
    NSString *matched=self.lastMatchedQuestion ?: @"";
    NSString *lower=heard.lowercaseString ?: @"";
    if ([matched hasPrefix:@"Synthesis: prep cook"]) return @"What skills do you think are important for a prep cook?";
    if ([matched hasPrefix:@"Synthesis: food safety"]) return @"How do you ensure food safety in the kitchen?";
    if (matched.length && ![matched hasPrefix:@"Synthesis:"] && self.lastMatchConfidence>=0.42) return matched;
    if ([lower containsString:@"prep cook"] && [lower containsString:@"skill"]) return @"What skills do you think are important for a prep cook?";
    if ([lower containsString:@"food safety"]) return @"How do you ensure food safety in the kitchen?";
    return heard;
}
- (NSString *)primaryQuestionFromText:(NSString *)text {
    NSString *fresh=[text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!fresh.length) return @"";
    NSArray *parts=[fresh componentsSeparatedByString:@"?"];
    NSMutableArray *candidates=[NSMutableArray array];
    for(NSString *part in parts){NSString *q=[part stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];if(q.length)[candidates addObject:q];}
    if(candidates.count>1) return candidates.lastObject;
    NSRegularExpression *re=[NSRegularExpression regularExpressionWithPattern:@"(?i)\\b(?:in what ways|what|which|why|how|when|where|who|can you|could you|do you|did you|are you|would you|list|name|describe|explain|identify|give|outline|define|compare|discuss|provide|state)\\b" options:0 error:nil];
    NSArray<NSTextCheckingResult *> *matches=[re matchesInString:fresh options:0 range:NSMakeRange(0,fresh.length)];
    if(matches.count>1){NSTextCheckingResult *last=matches.lastObject;return [[fresh substringFromIndex:last.range.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];}
    return fresh;
}
- (void)autoRecogniseCurrentQuestion {
    [self autoRecogniseQuestionText:self.latestTranscript ?: @""];
}
- (void)autoRecogniseQuestionText:(NSString *)text {
    [self autoRecogniseQuestionText:text fast:NO];
}
- (void)autoRecogniseQuestionText:(NSString *)text fast:(BOOL)fast {
    NSString *q=[self primaryQuestionFromText:text ?: @""];
    if(q.length<8) return;
    NSUInteger qWords=[[q componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] count];
    NSUInteger termCount=[self contentTerms:q].count;
    BOOL looks=[self looksLikeQuestion:q];
    if(looks && qWords<3) return;
    if(!looks && (qWords<5 || termCount<2)) return;
    if(fast && (!looks || qWords<4)) return;
    NSString *normal=[self normalisedQuestion:q]; if(!normal.length || [normal isEqualToString:self.lastAutoAsked]) return;
    NSString *raw=[self bestLocalAnswerForQuestion:q]; NSString *prefix=@"TRẢ LỜI EN:"; NSString *answer=nil;
    for(NSString *line in [raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) if([line hasPrefix:prefix]){answer=[[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];break;}
    if(!answer.length) answer=raw;
    BOOL weak=[answer containsString:@"No reliable match"];
    if(fast && (weak || self.lastMatchConfidence<0.72)) return;
    if(weak) {
      NSString *displayQuestion=[self displayQuestionForHeardQuestion:q];
      if (self.autoQuestion.length && ![self.autoQuestion isEqualToString:displayQuestion]) [self appendHistoryQuestion:self.autoQuestion answer:self.autoAnswer toTextView:self.autoHistoryView];
      self.lastAutoAsked=normal; self.autoQuestion=displayQuestion; self.autoAnswer=@"ChatGPT is preparing an answer from your SA Cook data…";
      [self showAutoQuestion:displayQuestion answer:self.autoAnswer];
      [self askAutoAIFallback:displayQuestion heard:q];
      return;
    } else {
      self.lastAutoAsked=normal;
    }
    NSString *displayQuestion=[self displayQuestionForHeardQuestion:q];
    if (self.autoQuestion.length) [self appendHistoryQuestion:self.autoQuestion answer:self.autoAnswer toTextView:self.autoHistoryView];
    self.autoQuestion=displayQuestion; self.autoAnswer=answer;
    [self showAutoQuestion:displayQuestion answer:answer];
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
- (void)showPanelQuestion:(NSString *)question answer:(NSString *)answer inTextView:(NSTextView *)view accentColor:(NSColor *)accent answerSize:(CGFloat)answerSize {
    NSString *q = question.length ? question : @"";
    NSString *a = answer.length ? answer : @"";
    NSMutableAttributedString *display = [NSMutableAttributedString new];
    if (q.length) {
      [display appendAttributedString:[[NSAttributedString alloc] initWithString:@"Question\n" attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightBold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.55 alpha:1]}]];
      [display appendAttributedString:[[NSAttributedString alloc] initWithString:[q stringByAppendingString:@"\n\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:18 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.84 alpha:1]}]];
    }
    [display appendAttributedString:[[NSAttributedString alloc] initWithString:@"Answer\n" attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13 weight:NSFontWeightBold],NSForegroundColorAttributeName:accent}]];
    [display appendAttributedString:[[NSAttributedString alloc] initWithString:a attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:answerSize weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.98 alpha:1]}]];
    [view.textStorage setAttributedString:display];
}
- (void)appendHistoryQuestion:(NSString *)question answer:(NSString *)answer toTextView:(NSTextView *)view {
    if (!question.length || !answer.length || !view) return;
    if ([answer containsString:@"preparing"] || [answer containsString:@"waiting for a clearer"]) return;
    if ([view.string hasPrefix:@"Chưa có lịch sử"]) view.string=@"";
    NSMutableAttributedString *entry=[NSMutableAttributedString new];
    [entry appendAttributedString:[[NSAttributedString alloc] initWithString:[question stringByAppendingString:@"\n\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.68 alpha:1]}]];
    [entry appendAttributedString:[[NSAttributedString alloc] initWithString:[answer stringByAppendingString:@"\n\n"] attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:15 weight:NSFontWeightSemibold],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.96 alpha:1]}]];
    [entry appendAttributedString:[[NSAttributedString alloc] initWithString:@"────────────────────────────\n\n" attributes:@{NSFontAttributeName:[NSFont systemFontOfSize:12],NSForegroundColorAttributeName:[NSColor colorWithWhite:0.30 alpha:1]}]];
    [view.textStorage insertAttributedString:entry atIndex:0];
}
- (void)showCurrentQuestion:(NSString *)question answer:(NSString *)answer {
    [self showPanelQuestion:question answer:answer inTextView:self.currentAnswerView accentColor:NSColor.systemGreenColor answerSize:24];
}
- (void)showAutoQuestion:(NSString *)question answer:(NSString *)answer {
    [self showPanelQuestion:question answer:answer inTextView:self.autoAnswerView accentColor:[NSColor colorWithRed:0.52 green:0.74 blue:1.0 alpha:1] answerSize:21];
}
- (void)askAutoAIFallback:(NSString *)question heard:(NSString *)heard {
    NSString *key=self.keyField.stringValue;
    NSString *cacheKey=[self normalisedQuestion:question]; NSString *cached=self.answerCache[cacheKey];
    if(cached.length){self.autoAnswer=cached;[self showAutoQuestion:question answer:cached];return;}
    if(key.length<20){self.autoAnswer=@"AUTO heard this question, but no reliable database answer was found. Add an active OpenAI API key to let ChatGPT synthesize an answer from your SA Cook data.";[self showAutoQuestion:question answer:self.autoAnswer];return;}
    if(self.autoRequestInFlight) return;
    self.autoRequestInFlight=YES;
    NSString *system=@"Answer a live cook interview practice question in English. Use the supplied SA Cook Study context, correct obvious transcript errors, and speak as the candidate using I/my/we. If the exact question is not in the context, synthesize a safe practical cook answer from the closest context. Give one short natural answer. No markdown.";
    NSString *context=[self aiContextForQuestion:heard.length?heard:question];
    NSString *user=[NSString stringWithFormat:@"HEARD TRANSCRIPT:\n%@\n\nBEST QUESTION:\n%@\n\n%@",heard?:@"",question?:@"",context];
    NSDictionary *body=@{@"model":@"gpt-4.1-mini",@"instructions":system,@"input":user,@"max_output_tokens":@90};
    NSData *data=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];
    req.HTTPMethod=@"POST"; req.HTTPBody=data; [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    NSString *questionCopy=question.copy;
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){
      NSString *result=nil; NSInteger code=[(NSHTTPURLResponse *)r statusCode];
      if(d){id parsed=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if([parsed isKindOfClass:NSDictionary.class]){NSDictionary *j=parsed;id output=j[@"output"];if([output isKindOfClass:NSArray.class])for(id item in (NSArray *)output)if([item isKindOfClass:NSDictionary.class]){id content=[(NSDictionary *)item objectForKey:@"content"];if([content isKindOfClass:NSArray.class])for(id part in (NSArray *)content)if([part isKindOfClass:NSDictionary.class]&&[[part objectForKey:@"type"] isEqual:@"output_text"]){id text=[part objectForKey:@"text"];if([text isKindOfClass:NSString.class]&&[text length]){result=text;break;}}if(result)break;}if(!result){id errorObject=j[@"error"];if([errorObject isKindOfClass:NSDictionary.class]){id apiMessage=[errorObject objectForKey:@"message"];if([apiMessage isKindOfClass:NSString.class])result=apiMessage;}}}}
      BOOL hasOutput=result.length>0; if(!result) result=e.localizedDescription?:[NSString stringWithFormat:@"OpenAI returned no text (HTTP %ld).",(long)code];
      dispatch_async(dispatch_get_main_queue(),^{self.autoRequestInFlight=NO;if([self.autoQuestion isEqualToString:questionCopy]){self.autoAnswer=result;[self showAutoQuestion:questionCopy answer:result];}if(code>=200&&code<300&&hasOutput){self.answerCache[cacheKey]=result;[[NSUserDefaults standardUserDefaults] setObject:self.answerCache forKey:@"PresenterAI.answerCache.v5"];}});
    }] resume];
}
- (void)askAIFallback:(NSString *)question {
    NSString *key=self.keyField.stringValue;
    NSString *cacheKey=[self normalisedQuestion:question];NSString *cached=self.answerCache[cacheKey];if(cached.length){self.currentAnswer=cached;[self showCurrentQuestion:question answer:cached];[self setStatus:@"✓ Đáp án lấy từ cache" color:NSColor.systemGreenColor];return;}
    if(key.length<20){self.currentAnswer=@"No reliable offline match. Click ‘Thiết lập AI…’ and enter an active OpenAI API key to use ChatGPT synthesis.";[self showCurrentQuestion:question answer:self.currentAnswer];[self setStatus:@"OpenAI key is required for AI synthesis" color:NSColor.systemOrangeColor];return;}
    self.requestInFlight=YES; BOOL hasImmediateAnswer=self.currentAnswer.length&&![self.currentAnswer containsString:@"No reliable"];
    if(!hasImmediateAnswer){self.currentAnswer=@"ChatGPT is preparing an answer…";[self showCurrentQuestion:question answer:self.currentAnswer];}
    [self setStatus:hasImmediateAnswer?@"✓ Đã trả lời • AI đang kiểm tra ngầm":@"ChatGPT is preparing an answer…" color:hasImmediateAnswer?NSColor.systemGreenColor:NSColor.systemOrangeColor];
    NSString *system=@"Answer a live Australian Cook Skill Assessment question in English. Use the supplied SA Cook context, correct obvious transcript errors, and speak as the candidate using I/my/we. Give one short natural sentence, or exactly the requested number of brief items. No markdown or explanation.";
    NSString *user=[NSString stringWithFormat:@"INTERVIEW QUESTION:\n%@\n\n%@",question,[self aiContextForQuestion:question]];
    NSDictionary *body=@{@"model":@"gpt-4.1-mini",@"instructions":system,@"input":user,@"max_output_tokens":@100};NSData *data=[NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]];req.HTTPMethod=@"POST";req.HTTPBody=data;[req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];[req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d,NSURLResponse *r,NSError *e){NSString *result=nil;NSInteger code=[(NSHTTPURLResponse *)r statusCode];if(d){id parsed=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];if([parsed isKindOfClass:NSDictionary.class]){NSDictionary *j=parsed;id output=j[@"output"];if([output isKindOfClass:NSArray.class])for(id item in (NSArray *)output)if([item isKindOfClass:NSDictionary.class]){id content=[(NSDictionary *)item objectForKey:@"content"];if([content isKindOfClass:NSArray.class])for(id part in (NSArray *)content)if([part isKindOfClass:NSDictionary.class]&&[[part objectForKey:@"type"] isEqual:@"output_text"]){id text=[part objectForKey:@"text"];if([text isKindOfClass:NSString.class]&&[text length]){result=text;break;}}if(result)break;}if(!result){id errorObject=j[@"error"];if([errorObject isKindOfClass:NSDictionary.class]){id apiMessage=[errorObject objectForKey:@"message"];if([apiMessage isKindOfClass:NSString.class])result=apiMessage;}}}}BOOL hasOutput=result.length>0;if(!result)result=e.localizedDescription?:[NSString stringWithFormat:@"OpenAI returned no text (HTTP %ld).",(long)code];dispatch_async(dispatch_get_main_queue(),^{self.requestInFlight=NO;if([self.currentQuestion isEqualToString:question]){self.currentAnswer=result;[self showCurrentQuestion:question answer:result];}if(code>=200&&code<300&&hasOutput){self.answerCache[cacheKey]=result;[[NSUserDefaults standardUserDefaults] setObject:self.answerCache forKey:@"PresenterAI.answerCache.v5"];}BOOL failed=(code<200||code>=300||!hasOutput);if([self.currentQuestion isEqualToString:question])[self setStatus:failed?@"OpenAI request failed":@"✓ ChatGPT đã chuẩn bị câu trả lời" color:failed?NSColor.systemRedColor:NSColor.systemGreenColor];});}] resume];
}
- (void)appendOfflineAnswerForQuestion:(NSString *)question {
    self.lastAsked=question; self.historyCount++;
    NSString *raw=[self bestLocalAnswerForQuestion:question]; NSString *prefix=@"TRẢ LỜI EN:"; NSString *answer=nil;
    for (NSString *line in [raw componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) if ([line hasPrefix:prefix]) { answer=[[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]; break; }
    if (!answer.length) answer=raw;
    NSString *displayQuestion=[self displayQuestionForHeardQuestion:question];
    if (self.currentQuestion.length) [self appendHistoryQuestion:self.currentQuestion answer:self.currentAnswer toTextView:self.answerView];
    BOOL needsAI=[answer containsString:@"No reliable match"];
    self.currentQuestion=displayQuestion; self.currentAnswer=answer; self.transcriptView.string=displayQuestion; self.transcriptView.textColor=NSColor.secondaryLabelColor;
    [self showCurrentQuestion:displayQuestion answer:answer];
    BOOL confident=!needsAI&&self.lastMatchConfidence>=0.82;
    if(needsAI||(self.keyField.stringValue.length>20&&!confident))[self askAIFallback:displayQuestion];
    else [self setStatus:[NSString stringWithFormat:@"✓ Đã lưu câu hỏi %02lu • khớp database%@",(unsigned long)self.historyCount,[displayQuestion isEqualToString:question]?@"":@" từ đoạn nghe thiếu"] color:NSColor.systemGreenColor];
}
- (void)clearHistory:(id)sender { self.autoHistoryView.string=@"Chưa có lịch sử AUTO.\n"; self.answerView.string=@"Chưa có lịch sử SPACE.\n"; }
- (void)askNow:(id)sender { NSString *q = self.transcriptView.string; if (q.length) [self askAI:q]; }
- (void)askAI:(NSString *)question {
    if (self.requestInFlight) return; NSString *key = self.keyField.stringValue;
    if (key.length < 20) { [self setStatus:@"Hãy nhập OpenAI API key" color:NSColor.systemOrangeColor]; return; }
    if (![self saveAPIKeyToKeychain:key]) { [self showErrorTitle:@"Không thể lưu API key" detail:@"App không lưu được key vào local settings. Key vẫn chỉ được dùng trong phiên hiện tại."]; }
    self.requestInFlight = YES; self.lastAsked = question; self.answerView.string = @"AI đang suy nghĩ…";
    NSString *context = self.topicField.stringValue.length ? self.topicField.stringValue : @"Buổi thuyết trình chuyên nghiệp";
    NSString *evidence = [self relevantContextForQuestion:question];
    NSString *prompt = [NSString stringWithFormat:@"Bạn là trợ lý teleprompter cho diễn giả. Bối cảnh: %@\nCâu hỏi vừa nghe: %@\n\nDỮ LIỆU THAM CHIẾU:\n%@\n\nChỉ trả lời dựa trên dữ liệu tham chiếu. Không tự thêm sự thật bên ngoài. Nếu dữ liệu không đủ hoặc chưa được nạp, nói ngắn gọn rằng chưa đủ dữ liệu và đề xuất một câu trả lời trì hoãn lịch sự. Trả lời bằng tiếng Việt, tự nhiên, tự tin, tối đa 5 gạch đầu dòng ngắn.", context, question, evidence];
    NSDictionary *body = @{@"model":@"gpt-5.5", @"input":prompt}; NSData *data = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.openai.com/v1/responses"]]; req.HTTPMethod=@"POST"; req.HTTPBody=data;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"]; [req setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
      NSString *result = nil; NSInteger httpCode = [(NSHTTPURLResponse *)r statusCode]; if (d) { NSDictionary *j=[NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
        for (NSDictionary *o in j[@"output"]) for (NSDictionary *c in o[@"content"]) if ([c[@"type"] isEqual:@"output_text"]) { result=c[@"text"]; break; }
        if (!result) result = j[@"error"][@"message"];
      }
      if (!result && e) result=[NSString stringWithFormat:@"Lỗi kết nối OpenAI: %@ (%@, mã %ld)", e.localizedDescription, e.domain, (long)e.code];
      if (!result) result=[NSString stringWithFormat:@"OpenAI không trả nội dung (HTTP %ld).", (long)httpCode];
      NSString *finalResult=result;
      dispatch_async(dispatch_get_main_queue(), ^{ self.requestInFlight=NO; self.answerView.string=finalResult; [self setStatus:httpCode>=400?[NSString stringWithFormat:@"OpenAI API lỗi HTTP %ld",(long)httpCode]:(self.listening?@"● ĐANG NGHE MICRO":@"● Đã dừng nghe") color:httpCode>=400?NSColor.systemRedColor:(self.listening?NSColor.systemRedColor:NSColor.secondaryLabelColor)]; });
    }] resume];
}
- (void)showErrorTitle:(NSString *)title detail:(NSString *)detail {
    [self setStatus:title color:NSColor.systemRedColor]; self.answerView.string=[NSString stringWithFormat:@"%@\n\n%@", title, detail];
}
- (void)setStatus:(NSString *)s color:(NSColor *)c { self.status.stringValue=s; self.status.textColor=c; }
- (void)buildMenu { NSMenu *m=[NSMenu new], *a=[NSMenu new]; NSMenuItem *i=[NSMenuItem new]; [m addItem:i]; [a addItemWithTitle:@"Thoát Presenter AI" action:@selector(terminate:) keyEquivalent:@"q"]; i.submenu=a; NSApp.mainMenu=m; }
- (void)applicationWillTerminate:(NSNotification *)n { if (self.spaceKeyMonitor) [NSEvent removeMonitor:self.spaceKeyMonitor]; if (self.listening) [self stopListening]; }
@end

int main(int argc,const char *argv[]){ @autoreleasepool { NSApplication *a=NSApplication.sharedApplication; AppDelegate *d=[AppDelegate new]; a.delegate=d; [a run]; } return 0; }
