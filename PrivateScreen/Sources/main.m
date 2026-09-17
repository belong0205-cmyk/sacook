#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate>
@property NSWindow *window;
@property NSTextView *textView;
@property NSTextField *statusLabel;
@property NSButton *protectionButton;
@property BOOL protectionEnabled;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [self buildMenu];
    [self buildWindow];
    [self applyProtection:YES];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (void)textDidChange:(NSNotification *)notification {
    [[NSUserDefaults standardUserDefaults] setObject:self.textView.string forKey:@"PrivateScreen.note"];
}

- (void)toggleProtection:(id)sender { [self applyProtection:!self.protectionEnabled]; }

- (void)clearNote:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Xóa toàn bộ ghi chú?";
    alert.informativeText = @"Thao tác này không thể hoàn tác.";
    [alert addButtonWithTitle:@"Xóa"];
    [alert addButtonWithTitle:@"Hủy"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    self.textView.string = @"";
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"PrivateScreen.note"];
}

- (void)applyProtection:(BOOL)enabled {
    self.protectionEnabled = enabled;
    self.window.sharingType = enabled ? NSWindowSharingNone : NSWindowSharingReadOnly;
    self.window.title = enabled ? @"Private Screen — Đang bảo vệ" : @"Private Screen — Không bảo vệ";
    self.statusLabel.stringValue = enabled
        ? @"● ĐANG BẢO VỆ — cửa sổ được yêu cầu loại khỏi bản chụp/chia sẻ"
        : @"● KHÔNG BẢO VỆ — nội dung có thể xuất hiện khi chia sẻ";
    self.statusLabel.textColor = enabled ? NSColor.systemGreenColor : NSColor.systemRedColor;
    self.protectionButton.title = enabled ? @"Tắt bảo vệ" : @"Bật bảo vệ";
}

- (void)buildWindow {
    self.window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 760, 520)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    [self.window center];
    self.window.minSize = NSMakeSize(520, 360);
    self.window.releasedWhenClosed = NO;
    self.window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSView *root = [[NSView alloc] init];
    self.window.contentView = root;

    self.statusLabel = [NSTextField labelWithString:@""];
    self.statusLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.protectionButton = [NSButton buttonWithTitle:@"" target:self action:@selector(toggleProtection:)];
    self.protectionButton.bezelStyle = NSBezelStyleRounded;
    self.protectionButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *clearButton = [NSButton buttonWithTitle:@"Xóa ghi chú" target:self action:@selector(clearNote:)];
    clearButton.bezelStyle = NSBezelStyleRounded;
    clearButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *warning = [NSTextField wrappingLabelWithString:
        @"Kiểm tra bằng một cuộc Meet thử trước khi dùng. Một số phiên bản trình duyệt/macOS có thể không tôn trọng cờ chống chụp khi chia sẻ toàn bộ màn hình."];
    warning.textColor = NSColor.secondaryLabelColor;
    warning.font = [NSFont systemFontOfSize:12];
    warning.translatesAutoresizingMaskIntoConstraints = NO;

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;

    self.textView = [[NSTextView alloc] init];
    self.textView.richText = NO;
    self.textView.automaticQuoteSubstitutionEnabled = NO;
    self.textView.automaticDashSubstitutionEnabled = NO;
    self.textView.allowsUndo = YES;
    self.textView.font = [NSFont monospacedSystemFontOfSize:16 weight:NSFontWeightRegular];
    self.textView.textContainerInset = NSMakeSize(14, 14);
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:@"PrivateScreen.note"];
    self.textView.string = saved ?: @"Ghi chú riêng tư của bạn…";
    self.textView.delegate = self;
    scroll.documentView = self.textView;

    for (NSView *view in @[self.statusLabel, self.protectionButton, clearButton, warning, scroll]) [root addSubview:view];

    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [self.protectionButton.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.protectionButton.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [clearButton.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [clearButton.trailingAnchor constraintEqualToAnchor:self.protectionButton.leadingAnchor constant:-8],
        [warning.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:12],
        [warning.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [warning.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [scroll.topAnchor constraintEqualToAnchor:warning.bottomAnchor constant:14],
        [scroll.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20]
    ]];
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];
    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"Giới thiệu Private Screen" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Thoát Private Screen" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSApp.mainMenu = mainMenu;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
