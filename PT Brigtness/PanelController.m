#import "PanelController.h"
#import "BackgroundView.h"
#import "StatusItemView.h"
#import "MenubarController.h"
#import "DDC.h"
#import <ServiceManagement/ServiceManagement.h>

#define OPEN_DURATION .15
#define CLOSE_DURATION .1

#define POPUP_HEIGHT 180
#define PANEL_WIDTH 280
#define MENU_ANIMATION_DURATION .2

#pragma mark -

@implementation PanelController

@synthesize backgroundView = _backgroundView;
@synthesize delegate = _delegate;

#pragma mark -

- (id)initWithDelegate:(id<PanelControllerDelegate>)delegate
{
    self = [super initWithWindowNibName:@"Panel"];
    if (self != nil)
    {
        _delegate = delegate;
    }
    
    @autoreleasepool {
        
        _displayIDs = [NSPointerArray pointerArrayWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsIntegerPersonality];
        
        for (NSScreen *screen in NSScreen.screens)
        {
            NSDictionary *description = [screen deviceDescription];
            if ([description objectForKey:@"NSDeviceIsScreen"]) {
                CGDirectDisplayID screenNumber = [[description objectForKey:@"NSScreenNumber"] unsignedIntValue];
                if (CGDisplayIsBuiltin(screenNumber)) continue; // ignore MacBook screens because the lid can be closed and they don't use DDC.
                [_displayIDs addPointer:(void *)(UInt64)screenNumber];
                NSSize displayPixelSize = [[description objectForKey:NSDeviceSize] sizeValue];
                CGSize displayPhysicalSize = CGDisplayScreenSize(screenNumber); // dspPhySz only valid if EDID present!
                float displayScale = [screen backingScaleFactor];
                double rotation = CGDisplayRotation(screenNumber);
                if (displayScale > 1) {
                    NSLog(@"D: NSScreen #%u (%.0fx%.0f %g°) HiDPI",
                          screenNumber,
                          displayPixelSize.width,
                          displayPixelSize.height,
                          rotation);
                } else {
                    NSLog(@"D: NSScreen #%u (%.0fx%.0f %g°) %0.2f DPI",
                          screenNumber,
                          displayPixelSize.width,
                          displayPixelSize.height,
                          rotation,
                          (displayPixelSize.width / displayPhysicalSize.width) * 25.4f); // there being 25.4 mm in an inch
                }
            }
        }
        
    }
        
    return self;
}

- (void)dealloc
{
    
    
}

- (IBAction)toggleEnforce:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:[sender state] == 1 forKey:@"enforce_values"];
}

- (IBAction)toggleLaunchAtLogin:(id)sender
{
    int clickedSegment = [sender state];
    NSBundle *bundle = [NSBundle mainBundle];
    NSLog(@"toggleLaunchAtLogin: %@", [bundle bundleIdentifier]);
    [[NSUserDefaults standardUserDefaults] setBool:[sender state] == 1 forKey:@"starts_at_login"];
    if (clickedSegment == 0) { // ON
        // Turn on launch at login
        if (!SMLoginItemSetEnabled ((__bridge CFStringRef)[bundle bundleIdentifier], YES)) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"An error ocurred"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Couldn't add Helper App to launch at login item list."];
            [alert runModal];
        }
    }
    if (clickedSegment == 1) { // OFF
        // Turn off launch at login
        if (!SMLoginItemSetEnabled ((__bridge CFStringRef)[bundle bundleIdentifier], NO)) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"An error ocurred"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Couldn't remove Helper App from launch at login item list."];
            [alert runModal];
        }
    }
}


- (void)performBackgroundTask
{
    BOOL enforceValues = [[NSUserDefaults standardUserDefaults] boolForKey:@"enforce_values"];
    if(enforceValues == false) {
        [self setControlsToCurrentValues];
        return;
    }
    
    int stored_brigtness = (int)[[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"%d", 0x10]];
    int stored_contrast  = (int)[[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"%d", 0x12]];
    
    
    [self setControlValue:0x10 value:stored_brigtness];
    [self setControlValue:0x12 value:stored_contrast];
    
    [self setControlsToCurrentValues];
}

- (void)startTimedTask
{
    if(fiveSecondTimer == nil) {
        fiveSecondTimer = [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(performBackgroundTask) userInfo:nil repeats:YES];
    }
}

- (void)setControlValue:(int)control value:(int)value {
    CGDirectDisplayID cdisplay = (CGDirectDisplayID)[_displayIDs pointerAtIndex:0];
    setControl(cdisplay, control, value);
}

- (int)readControlValue:(int)control {
    CGDirectDisplayID cdisplay = (CGDirectDisplayID)[_displayIDs pointerAtIndex:0];
    return (int)getControl(cdisplay, control);
}

void setControl(CGDirectDisplayID cdisplay, uint control_id, uint new_value)
{
    struct DDCWriteCommand command;
    command.control_id = control_id;
    command.new_value = new_value;
    
    if (!DDCWrite(cdisplay, &command)) {
        NSLog(@"E: Failed to send DDC command!");
    }
}

uint getControl(CGDirectDisplayID cdisplay, uint control_id)
{
    struct DDCReadCommand command;
    command.control_id = control_id;
    command.max_value = 0;
    command.current_value = 0;
    
    if (!DDCRead(cdisplay, &command)) {
        NSLog(@"E: DDC send command failed!");
        NSLog(@"E: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    } else {
        NSLog(@"I: VCP control #%u (0x%02hhx) = current: %u, max: %u", command.control_id, command.control_id, command.current_value, command.max_value);
    }
    return command.current_value;
}


- (void)setControlsToCurrentValues
{
    //Brightness
    int brightness_value = [self readControlValue:0x10];
    [_brightSlider setIntValue:brightness_value];
    [_brightLabelValue setIntValue:brightness_value];
    
    //Contrast
    int contrast_value = [self readControlValue:0x12];
    [_contrastSlider setIntValue:contrast_value];
    [_contrastLabelValue setIntValue:contrast_value];
    
    
    //Volume
    int volume_value = [self readControlValue:0x62];
    [_volumeSlider setIntValue:volume_value];
    [_volumeLabelValue setIntValue:volume_value];
}


- (void)setControlAndUpdateLabel:(int)control :(id)slider
{
    [self setControlValue:control value:[slider intValue]];
}

#pragma mark -

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    // Make a fully skinned panel
    NSPanel *panel = (id)[self window];
    [panel setAcceptsMouseMovedEvents:YES];
    [panel setLevel:NSPopUpMenuWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
}

#pragma mark - Public accessors

- (BOOL)hasActivePanel
{
    return _hasActivePanel;
}

- (void)setHasActivePanel:(BOOL)flag
{
    if (_hasActivePanel != flag)
    {
        _hasActivePanel = flag;
        
        if (_hasActivePanel)
        {
            [self openPanel];
        }
        else
        {
            [self closePanel];
        }
    }
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification
{
    self.hasActivePanel = NO;
}

- (void)windowDidResignKey:(NSNotification *)notification;
{
    if ([[self window] isVisible])
    {
        self.hasActivePanel = NO;
    }
}


#pragma mark - Public methods

- (NSRect)statusRectForWindow:(NSWindow *)window
{
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = NSZeroRect;
    
    StatusItemView *statusItemView = nil;
    if ([self.delegate respondsToSelector:@selector(statusItemViewForPanelController:)])
    {
        statusItemView = [self.delegate statusItemViewForPanelController:self];
    }
    
    if (statusItemView)
    {
        statusRect = statusItemView.globalRect;
        statusRect.origin.y = NSMinY(statusRect) - NSHeight(statusRect);
    }
    else
    {
        statusRect.size = NSMakeSize(STATUS_ITEM_VIEW_WIDTH, [[NSStatusBar systemStatusBar] thickness]);
        statusRect.origin.x = roundf((NSWidth(screenRect) - NSWidth(statusRect)) / 2);
        statusRect.origin.y = NSHeight(screenRect) - NSHeight(statusRect) * 2;
    }
    return statusRect;
}

- (void)windowDidResize:(NSNotification *)notification
{
    NSWindow *panel = [self window];
    NSRect statusRect = [self statusRectForWindow:panel];
    NSRect panelRect = [panel frame];
    
    CGFloat statusX = roundf(NSMidX(statusRect));
    CGFloat panelX = statusX - NSMinX(panelRect);
    
    self.backgroundView.arrowX = panelX;
}

- (void)openPanel
{
    NSWindow *panel = [self window];
    
    NSRect screenRect = [[[NSScreen screens] objectAtIndex:0] frame];
    NSRect statusRect = [self statusRectForWindow:panel];
    
    NSRect panelRect = [panel frame];
    panelRect.size.width = PANEL_WIDTH;
    panelRect.size.height = POPUP_HEIGHT;
    panelRect.origin.x = roundf(NSMidX(statusRect) - NSWidth(panelRect) / 2);
    panelRect.origin.y = NSMaxY(statusRect) - NSHeight(panelRect);
    
    if (NSMaxX(panelRect) > (NSMaxX(screenRect) - ARROW_HEIGHT))
        panelRect.origin.x -= NSMaxX(panelRect) - (NSMaxX(screenRect) - ARROW_HEIGHT);
    
    [NSApp activateIgnoringOtherApps:NO];
    [panel setAlphaValue:0];
    [panel setFrame:statusRect display:YES];
    [panel makeKeyAndOrderFront:nil];
    
    NSTimeInterval openDuration = OPEN_DURATION;
    
    NSEvent *currentEvent = [NSApp currentEvent];
    if ([currentEvent type] == NSLeftMouseDown)
    {
        NSUInteger clearFlags = ([currentEvent modifierFlags] & NSDeviceIndependentModifierFlagsMask);
        BOOL shiftPressed = (clearFlags == NSShiftKeyMask);
        BOOL shiftOptionPressed = (clearFlags == (NSShiftKeyMask | NSAlternateKeyMask));
        if (shiftPressed || shiftOptionPressed)
        {
            openDuration *= 10;
            
            if (shiftOptionPressed)
                NSLog(@"Icon is at %@\n\tMenu is on screen %@\n\tWill be animated to %@",
                      NSStringFromRect(statusRect), NSStringFromRect(screenRect), NSStringFromRect(panelRect));
        }
    }
    
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:openDuration];
    [[panel animator] setFrame:panelRect display:YES];
    [[panel animator] setAlphaValue:1];
    [NSAnimationContext endGrouping];
    
    [self setControlsToCurrentValues];
    
    BOOL loginStart = [[NSUserDefaults standardUserDefaults] boolForKey:@"starts_at_login"];
    BOOL enforceValues = [[NSUserDefaults standardUserDefaults] boolForKey:@"enforce_values"];
    
    [_enforceButton setState:enforceValues];
    [_startButton setState:loginStart];
}

- (void)closePanel
{
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:CLOSE_DURATION];
    [[[self window] animator] setAlphaValue:0];
    [NSAnimationContext endGrouping];
    
    dispatch_after(dispatch_walltime(NULL, NSEC_PER_SEC * CLOSE_DURATION * 2), dispatch_get_main_queue(), ^{
        
        [self.window orderOut:nil];
    });
}

- (IBAction)setBrightness:(id)sender {
    [_brightLabelValue setIntValue:[sender intValue]];
    [self setControlAndUpdateLabel:0x10 :sender];
}

- (IBAction)setContrast:(id)sender {
    [_contrastLabelValue setIntValue:[sender intValue]];
    [self setControlAndUpdateLabel:0x12 :sender];
}

- (IBAction)setVolume:(id)sender {
    [_contrastLabelValue setIntValue:[sender intValue]];
    [self setControlAndUpdateLabel:0x62 :sender];
}

- (IBAction)quitApp:(id)sender {
    [NSApp terminate:sender];
}

@end
