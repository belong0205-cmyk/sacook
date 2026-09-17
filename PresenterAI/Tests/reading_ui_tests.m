// Native, offscreen UI regression fixture. No launch callback, audio, key access,
// model requests, or preference writes are performed by this test.
#define main PresenterApplicationMain
#import "../Sources/main.m"
#undef main

@interface ReadingUITestApp : AppDelegate
@end
@implementation ReadingUITestApp
- (NSInteger)initialBackdropStrength { return 1; }
@end

static NSUInteger assertions=0, failures=0;
static void Check(BOOL condition, NSString *message) {
    assertions++;
    if(!condition) { failures++; fprintf(stderr,"FAIL: %s\n",message.UTF8String); }
}

static BOOL MenuHasAction(NSMenu *menu, SEL action) {
    for(NSMenuItem *item in menu.itemArray) if(item.action==action || (item.submenu && MenuHasAction(item.submenu,action))) return YES;
    return NO;
}

static void CheckLayoutTree(NSView *view) {
    // AppKit's private text rendering surfaces use their own layout machinery;
    // assess only the application-owned/public controls and constraints.
    if(!view.hidden && !view.translatesAutoresizingMaskIntoConstraints && ![NSStringFromClass(view.class) hasPrefix:@"_"])
        Check(!view.hasAmbiguousLayout,[NSString stringWithFormat:@"Unambiguous layout for %@ (%@)",view.class,view.accessibilityLabel?:@""]);
    for(NSView *child in view.subviews) CheckLayoutTree(child);
}

static BOOL ContainsVisualEffectView(NSView *view) {
    if([view isKindOfClass:NSVisualEffectView.class]) return YES;
    for(NSView *child in view.subviews) if(ContainsVisualEffectView(child)) return YES;
    return NO;
}

static void Layout(AppDelegate *app) {
    [app.window.contentView layoutSubtreeIfNeeded];
    for(NSTextView *view in @[app.currentAnswerView,app.autoAnswerView,app.answerView,app.autoHistoryView]) {
        [view.layoutManager ensureLayoutForTextContainer:view.textContainer];
    }
    [app.window.contentView layoutSubtreeIfNeeded];
}

static double LinearComponent(double value) {
    return value<=0.04045?value/12.92:pow((value+0.055)/1.055,2.4);
}

static double Luminance(NSColor *color) {
    NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return 0.2126*LinearComponent(rgb.redComponent)+0.7152*LinearComponent(rgb.greenComponent)+0.0722*LinearComponent(rgb.blueComponent);
}

static void CheckContrast(NSTextView *view, NSString *fragment, NSColor *background) {
    NSRange range=[view.string rangeOfString:fragment];
    NSColor *color=range.location!=NSNotFound?[view.textStorage attribute:NSForegroundColorAttributeName atIndex:range.location effectiveRange:NULL]:nil;
    Check(color!=nil,@"Reading text has an explicit foreground color");
    if(!color) return;
    double a=Luminance(color),b=Luminance(background);
    double contrast=(MAX(a,b)+0.05)/(MIN(a,b)+0.05);
    Check(contrast>=4.5,[NSString stringWithFormat:@"Text contrast %.2f meets 4.5:1 for %.28s",contrast,fragment.UTF8String]);
}

static void Render(AppDelegate *app,NSString *path) {
    Layout(app);
    NSView *root=app.window.contentView;
    NSBitmapImageRep *bitmap=[root bitmapImageRepForCachingDisplayInRect:root.bounds];
    [root cacheDisplayInRect:root.bounds toBitmapImageRep:bitmap];
    NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    NSError *error=nil;
    Check([png writeToFile:path options:NSDataWritingAtomic error:&error],[NSString stringWithFormat:@"Render offscreen reading fixture: %@",error?:path]);
}

static CGFloat RenderedAlphaAtPoint(NSView *root, NSBitmapImageRep *bitmap, NSPoint point) {
    NSInteger x=lround(point.x*bitmap.pixelsWide/NSWidth(root.bounds));
    NSInteger y=lround(point.y*bitmap.pixelsHigh/NSHeight(root.bounds));
    x=MAX(0,MIN(bitmap.pixelsWide-1,x)); y=MAX(0,MIN(bitmap.pixelsHigh-1,y));
    return [bitmap colorAtX:x y:y].alphaComponent;
}

static void CheckText(NSTextView *view, CGFloat fontSize, NSString *question, NSString *answer) {
    NSScrollView *scroll=view.enclosingScrollView;
    Check([view.string containsString:question],@"The full multipart question is displayed");
    Check([view.string containsString:answer],@"The complete long answer is displayed");
    Check([view.string hasPrefix:[question stringByAppendingString:@"\n"]] && [view.string containsString:@"\nLISTENING  •  "],@"Latest answer and live transcript share one continuous conversation surface without a heading");
    Check([view.string rangeOfString:@"CURRENT\n"].location==NSNotFound && [view.string rangeOfString:@"\nPREVIOUS\n"].location==NSNotFound,@"Conversation omits the CURRENT and PREVIOUS labels");
    Check([view.string rangeOfString:@"\nTHEM\n"].location==NSNotFound && [view.string rangeOfString:@"\nME\n"].location==NSNotFound,@"Question and answer use colour instead of THEM and ME rows");
    Check(!view.editable && view.selectable,@"Reading content is read-only and can still be selected or copied");
    NSRange answerRange=[view.string rangeOfString:answer];
    NSFont *font=answerRange.location!=NSNotFound?[view.textStorage attribute:NSFontAttributeName atIndex:answerRange.location effectiveRange:NULL]:nil;
    NSParagraphStyle *answerParagraph=answerRange.location!=NSNotFound?[view.textStorage attribute:NSParagraphStyleAttributeName atIndex:answerRange.location effectiveRange:NULL]:nil;
    NSRange questionRange=[view.string rangeOfString:question];
    NSColor *questionColor=questionRange.location!=NSNotFound?[view.textStorage attribute:NSForegroundColorAttributeName atIndex:questionRange.location effectiveRange:NULL]:nil;
    NSColor *answerColor=answerRange.location!=NSNotFound?[view.textStorage attribute:NSForegroundColorAttributeName atIndex:answerRange.location effectiveRange:NULL]:nil;
    NSShadow *questionShadow=questionRange.location!=NSNotFound?[view.textStorage attribute:NSShadowAttributeName atIndex:questionRange.location effectiveRange:NULL]:nil;
    NSShadow *answerShadow=answerRange.location!=NSNotFound?[view.textStorage attribute:NSShadowAttributeName atIndex:answerRange.location effectiveRange:NULL]:nil;
    Check(fabs(font.pointSize-fontSize)<0.01,@"Answer respects selected reading size");
    Check(answerParagraph.lineSpacing<=MAX(1.5,fontSize*0.08)+0.01 && answerParagraph.paragraphSpacing<=6.01,@"Current answer typography stays vertically compact");
    Check(questionColor && answerColor && ![questionColor isEqual:answerColor],@"Question colour is visibly distinct from answer colour");
    Check(questionColor.alphaComponent>0.99 && answerColor.alphaComponent>0.99 && questionShadow.shadowBlurRadius>=2 && answerShadow.shadowBlurRadius>=2,@"Opaque reading text retains a subtle shadow over bright or busy slides");
    Check(view.verticallyResizable && !view.horizontallyResizable,@"Answers resize vertically, not horizontally");
    Check(view.textContainer.widthTracksTextView,@"Answer wrapping tracks its text view");
    Check(!scroll.hasHorizontalScroller,@"Reading does not require horizontal scrolling");
    Check(fabs(view.frame.size.width-scroll.contentSize.width)<2,@"Text document fits the available column width");
    NSRect used=[view.layoutManager usedRectForTextContainer:view.textContainer];
    Check(used.size.width<=view.textContainer.containerSize.width+1,@"Long answer glyphs stay inside the text container");
    Check(view.frame.size.height+2>=NSMaxY(used)+view.textContainerInset.height*2,@"The text document reaches the final line");
    Check(used.size.height>fontSize*5,@"Long fixture actually wraps across many lines");
    Check(scroll.frame.size.height>=445,@"The single conversation surface uses nearly the full lane height");
}

int main(int argc,const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        ReadingUITestApp *app=[ReadingUITestApp new];
        [app buildMenu];
        [app buildUI];
        NSView *dock=nil,*autoLane=nil,*spaceLane=nil;
        for(NSView *view in app.window.contentView.subviews) {
            if([view.identifier isEqualToString:@"bottomControlBar"]) dock=view;
            else if([view.identifier isEqualToString:@"autoConversationLane"]) autoLane=view;
            else if([view.identifier isEqualToString:@"spaceConversationLane"]) spaceLane=view;
        }
        Check(dock!=nil && autoLane!=nil && spaceLane!=nil,@"Two reading lanes and the bottom control dock are explicit layout regions");
        Check(app.listenButton.superview==dock && app.deviceButton.superview==dock && app.autoButton.superview==dock && app.commitButton.superview==dock,@"Listening, source, AUTO, and SPACE controls all live in the bottom dock");
        Check(app.status.superview==dock && app.levelLabel.superview==dock && app.moreButton.superview==dock,@"Status and one compact secondary-actions menu live in the bottom dock");
        Check(dock.subviews.count==7,@"Bottom dock exposes only four primary controls, two compact states, and one overflow menu");
        for(NSString *selectorName in @[@"copyAutoConversation:",@"copyManualConversation:",@"retryAutoAnswer:",@"retryManualAnswer:",@"clearAutoHistory:",@"clearManualHistory:",@"checkForUpdates:",@"configureAI:",@"changeReadingFont:",@"changeBackdropStrength:"])
            Check(MenuHasAction(app.moreButton.menu,NSSelectorFromString(selectorName)),[NSString stringWithFormat:@"Secondary menu exposes %@",selectorName]);
        Check(app.backdropMenuItems.count==3 && app.backdropStrength==1,@"Background menu offers three levels and starts at the balanced level");
        for(NSUInteger i=0;i<app.backdropMenuItems.count;i++) Check(app.backdropMenuItems[i].tag==(NSInteger)i && app.backdropMenuItems[i].state==(i==1?NSControlStateValueOn:NSControlStateValueOff),@"Exactly the balanced background item starts checked");
        for(NSTextView *conversation in @[app.autoAnswerView,app.currentAnswerView]) {
            Check(conversation.selectable && !conversation.editable,@"Conversation text can be selected without being edited");
            Check(MenuHasAction(conversation.menu,@selector(copy:)) && MenuHasAction(conversation.menu,@selector(selectAll:)),@"Conversation right-click menu exposes Copy and Select All");
        }
        BOOL globalCopy=NO,globalSelectAll=NO;
        for(NSMenuItem *rootItem in NSApp.mainMenu.itemArray) for(NSMenuItem *item in rootItem.submenu.itemArray) {
            globalCopy|=item.action==@selector(copy:) && [item.keyEquivalent isEqualToString:@"c"];
            globalSelectAll|=item.action==@selector(selectAll:) && [item.keyEquivalent isEqualToString:@"a"];
        }
        Check(globalCopy && globalSelectAll,@"Application menu routes Command-C and Command-A to the selected conversation text");
        Check(autoLane.subviews.count==1 && spaceLane.subviews.count==1,@"Each reading lane contains only its continuous conversation surface and no lane heading");
        Check(app.window.contentView.layer.borderWidth==0 && dock.layer.borderWidth==0 && autoLane.layer.borderWidth==0 && spaceLane.layer.borderWidth==0 && app.autoAnswerView.enclosingScrollView.layer.borderWidth==0 && app.currentAnswerView.enclosingScrollView.layer.borderWidth==0,@"Shell, dock, and reading surfaces have no grey rounded border");
        Check(!app.autoAnswerView.enclosingScrollView.drawsBackground && !app.currentAnswerView.enclosingScrollView.drawsBackground && !app.autoAnswerView.enclosingScrollView.contentView.drawsBackground && !app.currentAnswerView.enclosingScrollView.contentView.drawsBackground,@"Conversation uses one translucent paint layer with clear scroll and clip views");
        Check([app.autoAnswerView.string rangeOfString:@"Start listening" options:NSCaseInsensitiveSearch].location==NSNotFound && [app.autoAnswerView.string rangeOfString:@"AUTO will detect" options:NSCaseInsensitiveSearch].location==NSNotFound,@"AUTO startup copy does not occupy the answer area");
        Check(!ContainsVisualEffectView(app.window.contentView) && !app.window.opaque && app.window.backgroundColor.alphaComponent<0.001,@"Entire shell uses genuinely clear views instead of an opaque macOS blur material");
        Check(fabs(app.window.alphaValue-1.0)<0.001 && [app readingSurfaceColor].alphaComponent<0.50,@"Only the local reading veil changes while text remains fully opaque");
        Check(fabs([app readingSurfaceColor].alphaComponent-0.28)<0.011,@"Conversation starts with the balanced twenty-eight-percent reading veil");
        CGFloat rootAlpha=CGColorGetAlpha(app.window.contentView.layer.backgroundColor), surfaceAlpha=[app readingSurfaceColor].alphaComponent;
        Check(fabs(rootAlpha-0.02)<0.011 && fabs(CGColorGetAlpha(dock.layer.backgroundColor)-0.10)<0.011,@"Shell and dock use genuinely light transparent tints");
        Check(1-(1-rootAlpha)*(1-surfaceAlpha)>0.28 && 1-(1-rootAlpha)*(1-surfaceAlpha)<0.31,@"Balanced reading area keeps about seventy percent of the backdrop visible");
        Check(!app.window.contentView.layer.opaque && !autoLane.layer.opaque && !spaceLane.layer.opaque && autoLane.layer.shadowOpacity==0 && spaceLane.layer.shadowOpacity==0,@"No hidden opaque lane or shadow can darken the slide");
        for(NSTextView *conversation in @[app.autoAnswerView,app.currentAnswerView])
            Check(conversation.drawsBackground && fabs(conversation.backgroundColor.alphaComponent-0.28)<0.011 && fabs(conversation.alphaValue-1)<0.001,@"Each reading view paints the balanced veil and never dims its text");
        NSArray<NSNumber *> *presetSurface=@[@0.14,@0.28,@0.46];
        for(NSUInteger preset=0;preset<presetSurface.count;preset++) {
            app.backdropStrength=(NSInteger)preset; [app refreshBackdropAppearance];
            NSUInteger checked=0; for(NSMenuItem *item in app.backdropMenuItems) if(item.state==NSControlStateValueOn) checked++;
            Check(fabs([app readingSurfaceColor].alphaComponent-presetSurface[preset].doubleValue)<0.011 && checked==1 && app.backdropMenuItems[preset].state==NSControlStateValueOn,@"Each background preset applies immediately and checks only its own menu item");
            Check(fabs(app.autoAnswerView.backgroundColor.alphaComponent-presetSurface[preset].doubleValue)<0.011 && fabs(app.currentAnswerView.backgroundColor.alphaComponent-presetSurface[preset].doubleValue)<0.011 && fabs(app.window.alphaValue-1)<0.001,@"Preset updates both lanes without fading their text");
        }
        app.backdropStrength=1; [app refreshBackdropAppearance];
        NSAttributedString *savedAuto=app.autoAnswerView.attributedString.copy,*savedSpace=app.currentAnswerView.attributedString.copy;
        [app.autoAnswerView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
        [app.currentAnswerView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]]; Layout(app);
        NSView *root=app.window.contentView; NSBitmapImageRep *alphaBitmap=[root bitmapImageRepForCachingDisplayInRect:root.bounds];
        [root cacheDisplayInRect:root.bounds toBitmapImageRep:alphaBitmap];
        NSPoint gapPoint=NSMakePoint((NSMaxX(autoLane.frame)+NSMinX(spaceLane.frame))/2,NSMidY(autoLane.frame));
        NSPoint lanePoint=[root convertPoint:NSMakePoint(NSMidX(app.autoAnswerView.bounds),NSMidY(app.autoAnswerView.bounds)) fromView:app.autoAnswerView];
        Check(fabs(RenderedAlphaAtPoint(root,alphaBitmap,gapPoint)-5.0/255.0)<0.01,@"Rendered shell gap is truly two-percent alpha");
        Check(fabs(RenderedAlphaAtPoint(root,alphaBitmap,lanePoint)-75.0/255.0)<0.015,@"Rendered balanced lane is truly about twenty-nine-percent combined alpha");
        [app.autoAnswerView.textStorage setAttributedString:savedAuto]; [app.currentAnswerView.textStorage setAttributedString:savedSpace]; Layout(app);
        Check(app.window.titlebarAppearsTransparent && app.window.titleVisibility==NSWindowTitleHidden,@"Floating shell has an integrated transparent titlebar");
        Check(app.window.movableByWindowBackground && app.window.level==NSFloatingWindowLevel,@"Compact assistant can be dragged and stays above presentation windows");
        Check((app.window.collectionBehavior&NSWindowCollectionBehaviorFullScreenAuxiliary)!=0,@"Assistant remains available beside full-screen presentation apps");
        [app.deviceButton addItemWithTitle:@"Nguồn: BlackHole 2ch"];
        app.status.stringValue=@"● Đang nghe";
        app.levelLabel.stringValue=@"● Có âm thanh";
        NSString *question=@"Which knife is the most versatile for slicing, chopping and dicing? What knife is best for cutting julienne or vegetables?";
        NSString *answer=@"A chef's knife is the most versatile choice for slicing, chopping and dicing. For julienne, I use its sharp broad blade to cut even slices, stack them safely, and make consistent matchsticks. A smaller utility knife offers precision but is slower for volume.";
        NSString *autoQuestion=@"What is the difference between cleaning and sanitising?";
        NSString *autoAnswer=@"Cleaning removes food residue, grease and visible dirt. Sanitising then reduces microorganisms to a safe level. I clean first, rinse if required, apply food-safe sanitiser for the correct contact time, and allow the surface to air dry.";
        app.currentQuestion=question; app.currentAnswer=answer;
        app.autoQuestion=autoQuestion; app.autoAnswer=autoAnswer;
        app.manualRecords=[@[
            [@{@"question":@"SPACE history example",@"answer":@"This manual answer stays in the SPACE history.",@"state":@"complete",@"lane":@"manual"} mutableCopy],
            [@{@"question":question,@"answer":answer,@"state":@"complete",@"lane":@"manual"} mutableCopy]
        ] mutableCopy];
        app.autoRecords=[@[
            [@{@"question":@"AUTO history example",@"answer":@"This automatic answer stays in the AUTO history.",@"state":@"complete",@"lane":@"auto"} mutableCopy],
            [@{@"question":autoQuestion,@"answer":autoAnswer,@"state":@"complete",@"lane":@"auto"} mutableCopy]
        ] mutableCopy];
        // Multiple previous answers make both histories genuinely scrollable.
        for(NSUInteger i=0;i<6;i++) {
            [app.manualRecords insertObject:[@{@"question":@"How do you prevent cross-contamination?",@"answer":@"I keep raw and ready-to-eat food separate, use separate chopping boards and utensils, wash my hands between tasks, and clean and sanitise food-contact surfaces.",@"state":@"complete",@"lane":@"manual"} mutableCopy] atIndex:app.manualRecords.count-1];
            [app.autoRecords insertObject:[@{@"question":@"What is mise en place?",@"answer":@"Mise en place means having everything in its place: preparing and organising ingredients, equipment and the work area before cooking or service.",@"state":@"complete",@"lane":@"auto"} mutableCopy] atIndex:app.autoRecords.count-1];
        }
        Check(app.manualHistoryScroll.hidden && app.autoHistoryScroll.hidden,@"Legacy history boxes stay hidden because previous turns render in the main conversation");
        Check(fabs(app.window.contentView.frame.size.width-1080)<1 && fabs(app.window.contentView.frame.size.height-700)<1,@"Default content size is compact 1080 by 700");
        for(NSValue *sizeValue in @[[NSValue valueWithSize:NSMakeSize(900,600)],[NSValue valueWithSize:NSMakeSize(1080,700)]]) {
            [app.window setContentSize:sizeValue.sizeValue];
            for(NSNumber *size in @[@20,@26,@40]) {
                app.readingFontSize=size.doubleValue;
                [app refreshReadingTypography];
                Layout(app);
                Check(NSMinY(dock.frame)<=11.1,@"Control dock remains anchored to the bottom edge");
                Check(dock.frame.size.height<=54.1,@"Bottom dock remains a compact single row");
                Check(app.window.contentView.bounds.size.height-NSMaxY(autoLane.frame)<=35.1 && app.window.contentView.bounds.size.height-NSMaxY(spaceLane.frame)<=35.1,@"Both question-and-answer lanes begin near the top edge");
                NSArray<NSView *> *primary=@[app.listenButton,app.deviceButton,app.autoButton,app.commitButton,app.status,app.levelLabel,app.moreButton];
                for(NSView *control in primary) Check(NSContainsRect(NSInsetRect(dock.bounds,-1,-1),control.frame),@"Every visible dock control stays inside the compact bar");
                for(NSUInteger i=0;i<primary.count;i++) for(NSUInteger j=i+1;j<primary.count;j++) {
                    NSRect intersection=NSIntersectionRect(primary[i].frame,primary[j].frame);
                    Check(NSIsEmptyRect(intersection) || intersection.size.width*intersection.size.height<1,@"Compact dock controls never overlap");
                }
                Check(app.listenButton.frame.size.width>=84 && app.listenButton.frame.size.height>=28 && app.commitButton.frame.size.width>=84 && app.commitButton.frame.size.height>=28,@"The two primary action buttons retain comfortable targets");
                Check(app.moreButton.frame.size.width>=28 && app.moreButton.frame.size.height>=28,@"Secondary-actions menu retains a comfortable target");
                CheckLayoutTree(app.window.contentView);
                CheckText(app.currentAnswerView,size.doubleValue,question,answer);
                CheckText(app.autoAnswerView,size.doubleValue,autoQuestion,autoAnswer);
                Check(fabs(app.currentAnswerView.enclosingScrollView.frame.size.width-app.autoAnswerView.enclosingScrollView.frame.size.width)<=1.1,@"AUTO and SPACE have equal reading widths within pixel rounding");
                Check(![app.currentAnswerView.string containsString:autoQuestion],@"AUTO question never appears in SPACE answer");
                Check(![app.autoAnswerView.string containsString:question],@"SPACE question never appears in AUTO answer");
                Check([app.currentAnswerView.string containsString:@"SPACE history example"] && ![app.currentAnswerView.string containsString:@"AUTO history example"] && [app.currentAnswerView.string rangeOfString:@"\nPREVIOUS\n"].location==NSNotFound,@"SPACE latest and earlier exchanges share one independent label-free surface");
                Check([app.autoAnswerView.string containsString:@"AUTO history example"] && ![app.autoAnswerView.string containsString:@"SPACE history example"] && [app.autoAnswerView.string rangeOfString:@"\nPREVIOUS\n"].location==NSNotFound,@"AUTO latest and earlier exchanges share one independent label-free surface");
                Check(app.manualHistoryScroll.hidden && app.autoHistoryScroll.hidden,@"Changing text size never restores the removed extra history boxes");
            }
        }
        // A repaint of the same question must not pull the reader back to the top.
        [app.window setContentSize:NSMakeSize(900,600)];
        app.readingFontSize=26; [app refreshReadingTypography]; Layout(app);
        [app.currentAnswerView scrollPoint:NSMakePoint(0,90)];
        [app.autoAnswerView scrollPoint:NSMakePoint(0,70)]; Layout(app);
        CGFloat manualY=app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y;
        CGFloat autoY=app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y;
        Check(manualY>1 && autoY>1,@"Scroll-preservation fixture has actually scrolled both answers");
        [app refreshManualAnswerPanel]; [app refreshAutoAnswerPanel]; Layout(app);
        Check(fabs(app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y-manualY)<1,@"Same-question SPACE refresh preserves scroll");
        Check(fabs(app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y-autoY)<1,@"Same-question AUTO refresh preserves scroll");
        [app refreshManualAnswerPanel]; [app refreshAutoAnswerPanel]; Layout(app);
        Check(fabs(app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y-manualY)<1,@"Repeated SPACE refresh does not jump the unified conversation");
        Check(fabs(app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y-autoY)<1,@"Repeated AUTO refresh does not jump the unified conversation");
        app.currentAnswer=[answer stringByAppendingString:@" I keep the knife sharp."];
        [app showCurrentQuestion:question answer:app.currentAnswer]; Layout(app);
        Check(fabs(app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y-manualY)<1,@"Updated answer for the same question preserves scroll");
        app.currentAnswer=answer; app.readingFontSize=30;
        [app refreshReadingTypography]; Layout(app);
        Check(fabs(app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y-manualY)<1,@"SPACE typography change preserves scroll");
        Check(fabs(app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y-autoY)<1,@"AUTO typography change preserves scroll");
        NSString *autoBefore=app.autoAnswerView.string.copy;
        [app showCurrentQuestion:@"What should I prepare before service?" answer:answer]; Layout(app);
        Check(fabs(app.currentAnswerView.enclosingScrollView.contentView.bounds.origin.y)<1,@"New SPACE question starts at the top");
        Check([app.autoAnswerView.string isEqualToString:autoBefore],@"New SPACE question leaves AUTO content unchanged");
        Check(fabs(app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y-autoY)<1,@"New SPACE question leaves AUTO scroll unchanged");
        [app showAutoQuestion:@"What should I check before starting work?" answer:autoAnswer]; Layout(app);
        Check(fabs(app.autoAnswerView.enclosingScrollView.contentView.bounds.origin.y)<1,@"New AUTO question starts at the top");
        // A newly answered question moves the former current exchange directly
        // below the new one in the same visible conversation surface.
        for(NSNumber *automaticValue in @[@NO,@YES]) {
            BOOL automatic=automaticValue.boolValue;
            NSTextView *conversation=automatic?app.autoAnswerView:app.currentAnswerView;
            NSTextView *otherConversation=automatic?app.currentAnswerView:app.autoAnswerView;
            NSMutableArray *records=automatic?app.autoRecords:app.manualRecords;
            NSString *formerQuestion=records.lastObject[@"question"];
            NSString *otherText=otherConversation.string.copy;
            [records addObject:[@{@"question":@"What should I prepare before service?",@"answer":@"I organise my ingredients, equipment and work station before service.",@"state":@"complete",@"lane":automatic?@"auto":@"manual"} mutableCopy]];
            if(automatic) [app refreshAutoAnswerPanel]; else [app refreshManualAnswerPanel];
            Layout(app);
            Check([conversation.string hasPrefix:@"What should I prepare before service?\n"],@"The latest exchange starts directly at the top");
            NSRange latestRange=[conversation.string rangeOfString:@"What should I prepare before service?"];
            NSRange listeningRange=[conversation.string rangeOfString:@"\nLISTENING  •  "];
            NSRange formerRange=[conversation.string rangeOfString:formerQuestion];
            Check(listeningRange.location!=NSNotFound && formerRange.location!=NSNotFound && latestRange.location<listeningRange.location && listeningRange.location<formerRange.location && [conversation.string rangeOfString:@"\nPREVIOUS\n"].location==NSNotFound,@"Earlier exchange remains below a neutral compact separator without a PREVIOUS label");
            Check([otherConversation.string isEqualToString:otherText],@"A new exchange in one lane does not repaint the other conversation");
            [records removeLastObject];
            if(automatic) [app refreshAutoAnswerPanel]; else [app refreshManualAnswerPanel];
            Layout(app);
        }
        app.readingFontSize=20; [app refreshReadingTypography];
        [app.window setContentSize:NSMakeSize(1080,700)]; Layout(app);
        for(NSTextView *view in @[app.currentAnswerView,app.autoAnswerView]) {
            NSString *q=view==app.currentAnswerView?question:autoQuestion;
            NSString *a=view==app.currentAnswerView?answer:autoAnswer;
            for(NSString *fragment in @[q,a]) CheckContrast(view,fragment,[app readingSurfaceColor]);
        }
        if(argc>1) {
            NSString *path=[NSString stringWithUTF8String:argv[1]];
            [app.currentAnswerView scrollPoint:NSZeroPoint]; [app.autoAnswerView scrollPoint:NSZeroPoint];
            Check(app.manualHistoryScroll.hidden && app.autoHistoryScroll.hidden,@"Preview contains no separate history boxes");
            Render(app,path);
            [app.window setContentSize:NSMakeSize(900,600)];
            Layout(app);
            [app.currentAnswerView scrollPoint:NSZeroPoint]; [app.autoAnswerView scrollPoint:NSZeroPoint];
            Render(app,[[path stringByDeletingPathExtension] stringByAppendingString:@"-minimum-histories.png"]);
        }
        Check(!app.listening && app.audioEngine==nil && app.recognizer==nil,@"UI test never starts audio or speech recognition");
        printf("Reading UI: %lu assertions, %lu failures\n",(unsigned long)assertions,(unsigned long)failures);
        return failures?1:0;
    }
}
