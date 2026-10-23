#import <Cocoa/Cocoa.h>
#import "HorosAPI.h"
#include "SPMath.h"

// Guided measurement of sagittal spinopelvic parameters on a lateral standing radiograph.
// Each landmark is a Horos 2D point ROI, so it is saved with the image and can be dragged
// to adjust it; results and the helper lines update live.

static NSString *const HelperPrefix = @"SP·";
static NSString *const CalibrationPrefix = @"Calibración SP: ";

typedef struct { const char *name, *instruction; BOOL optional; } SPStep;

// Names are shown next to each point on the image, so they are short. The TK pair takes its
// level (T4/T5) from the popup.
static const SPStep Steps[SPLandmarkCount] = {
    [SPFemoralHead1] = {"CF1", "Centro de la cabeza femoral 1", NO},
    [SPFemoralHead2] = {"CF2", "Centro de la cabeza femoral 2 (saltar si se superponen)", YES},
    [SPS1Posterior] = {"S1 post", "S1: esquina posterosuperior del platillo", NO},
    [SPS1Anterior] = {"S1 ant", "S1: esquina anterosuperior del platillo", NO},
    [SPL1Posterior] = {"L1 post", "L1: platillo superior, esquina posterior", NO},
    [SPL1Anterior] = {"L1 ant", "L1: platillo superior, esquina anterior", NO},
    [SPT12Posterior] = {"T12 post", "T12: platillo inferior, esquina posterior", YES},
    [SPT12Anterior] = {"T12 ant", "T12: platillo inferior, esquina anterior", YES},
    [SPTKPosterior] = {"%@ post", "%@: platillo superior, esquina posterior", YES},
    [SPTKAnterior] = {"%@ ant", "%@: platillo superior, esquina anterior", YES},
    [SPT1Center] = {"T1", "Centro del cuerpo vertebral de T1", YES},
    [SPC7Center] = {"C7", "Centro del cuerpo vertebral de C7", YES},
};

// Horos reads RGB components, which catalog colors such as systemGreenColor do not have.
static NSColor *RGB(NSColor *c) { return [c colorUsingColorSpace:NSColorSpace.sRGBColorSpace]; }

#pragma mark - Controller

@interface SPController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (weak) ViewerController *viewer;
@property short slice;
@property NSInteger active;            // step waiting for a click, -1 when none
@property NSString *tkLevel;           // "T4" or "T5"
@property double calibrationMMPerPx;   // > 0 overrides the DICOM pixel spacing
@property NSString *lastSignature;
@property NSString *resultsText;
@property NSMutableDictionary<NSString *, ROI *> *helpers;
@property NSPanel *panel;
@property NSTextField *instruction, *calibrationLabel;
@property NSTableView *table;
@property NSTextView *results;
@property NSPopUpButton *tkPopup;
@property NSButton *updateButton;
@property NSTextField *notice;
@property NSTimer *timer;
@end

static NSMutableArray<SPController *> *Controllers;

#pragma mark - Updates

// Once per Horos session, the latest GitHub release is compared with this bundle's version.
// When it is newer, every open panel shows a button that downloads its installer and opens it.
static NSString *const ReleasesAPI = @"https://api.github.com/repos/bersonzini-glitch/horos-parametros-espinopelvicos/releases/latest";
static NSDictionary *LatestRelease;   // @{@"version", @"notes", @"pkg"} when an update exists
static BOOL UpdateChecked;

static NSString *BundleVersion(void) {
    return [[NSBundle bundleForClass:SPController.class] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"0";
}

// "v1.2.0" > "1.1": numeric components, missing ones count as 0.
static BOOL IsNewer(NSString *candidate, NSString *current) {
    NSArray *a = [[candidate stringByTrimmingCharactersInSet:NSCharacterSet.letterCharacterSet] componentsSeparatedByString:@"."];
    NSArray *b = [current componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(a.count, b.count); i++) {
        NSInteger x = i < a.count ? [a[i] integerValue] : 0, y = i < b.count ? [b[i] integerValue] : 0;
        if (x != y) return x > y;
    }
    return NO;
}

// Once per Horos session: tells sagitalapp.com about a first install or a new version, so the
// author can count installs. Sends the plugin and Horos versions and a random id kept in Horos's
// preferences; the server derives an approximate location from the connection and stores no IP.
static void ReportInstall(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSString *iid = [d stringForKey:@"SagitalAppInstallID"], *reported = [d stringForKey:@"SagitalAppReportedVersion"];
    NSString *version = BundleVersion();
    if (iid && [reported isEqualToString:version]) return;
    NSMutableDictionary *body = [@{
        @"plugin": @"horos", @"so": @"mac", @"version": version,
        @"evento": iid ? @"actualizacion" : @"instalacion",
        @"instalacion_id": iid ?: NSUUID.UUID.UUIDString.lowercaseString,
        @"app_version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"",
    } mutableCopy];
    if (reported) body[@"version_anterior"] = reported;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://sagitalapp.com/api/instalacion"]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 15;
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (err || status < 200 || status >= 300) return;   // try again next session
        dispatch_async(dispatch_get_main_queue(), ^{
            [d setObject:body[@"instalacion_id"] forKey:@"SagitalAppInstallID"];
            [d setObject:version forKey:@"SagitalAppReportedVersion"];
        });
    }] resume];
}

// The author's current message, from sagitalapp.com/api/aviso. It is kept in Horos's preferences,
// so without internet the panel shows the last one received; an empty message clears it.
static NSString *const NoticeKey = @"SagitalAppAviso";

static void FetchNotice(void (^done)(void)) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://sagitalapp.com/api/aviso"]];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    req.timeoutInterval = 15;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        NSDictionary *json = data && !err && status == 200 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *text = [json isKindOfClass:NSDictionary.class] ? json[@"texto"] : nil;
        if (![text isKindOfClass:NSString.class]) return;   // offline: keep the last one
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSUserDefaults.standardUserDefaults setObject:text forKey:NoticeKey];
            done();
        });
    }] resume];
}

static void CheckForUpdate(void (^done)(void)) {
    if (UpdateChecked) { done(); return; }
    UpdateChecked = YES;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:ReleasesAPI]];
    [req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    req.timeoutInterval = 15;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSDictionary *json = data && !err ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *tag = [json isKindOfClass:NSDictionary.class] ? json[@"tag_name"] : nil;
        NSString *pkg = nil;
        for (NSDictionary *asset in json[@"assets"]) {
            if ([asset[@"name"] hasSuffix:@".pkg"]) pkg = asset[@"browser_download_url"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([tag isKindOfClass:NSString.class] && pkg && IsNewer(tag, BundleVersion())) {
                NSString *notes = [json[@"body"] isKindOfClass:NSString.class] ? json[@"body"] : @"";
                LatestRelease = @{@"version": [tag stringByTrimmingCharactersInSet:NSCharacterSet.letterCharacterSet], @"notes": notes, @"pkg": pkg};
            } else if (!tag) {
                UpdateChecked = NO;   // offline or rate-limited: try again next time a panel opens
            }
            done();
        });
    }] resume];
}

@implementation SPController {
    ROI *__strong _rois[SPLandmarkCount];
    BOOL _skipped[SPLandmarkCount];
}

+ (void)openForViewer:(ViewerController *)viewer {
    if (!Controllers) Controllers = [NSMutableArray array];
    for (SPController *c in Controllers) {
        if (c.viewer == viewer) { [c.panel makeKeyAndOrderFront:nil]; return; }
    }
    SPController *c = [SPController new];
    c.viewer = viewer;
    c.slice = viewer.imageView.curImage;
    c.tkLevel = @"T4";
    c.helpers = [NSMutableDictionary dictionary];
    [Controllers addObject:c];
    [c adoptExistingROIs];
    [c buildPanel];
    [c selectNextStepFrom:0];
    [c refresh:YES];

    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    [nc addObserver:c selector:@selector(roiAdded:) name:@"addROI" object:nil];
    [nc addObserver:c selector:@selector(viewerClosed:) name:@"CloseViewerNotification" object:viewer];
    c.timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:c selector:@selector(tick:) userInfo:nil repeats:YES];
    [viewer setROIToolTag:t2DPoint];
    CheckForUpdate(^{ for (SPController *o in Controllers) [o showUpdateButton]; });
    ReportInstall();
    FetchNotice(^{ for (SPController *o in Controllers) [o showNotice]; });
}

- (NSMutableArray<ROI *> *)sliceROIs {
    NSArray *all = self.viewer.roiList;
    return self.slice < (short)all.count ? all[self.slice] : nil;
}

- (NSString *)nameForStep:(NSInteger)i {
    NSString *f = @(Steps[i].name);
    return [f containsString:@"%@"] ? [NSString stringWithFormat:f, self.tkLevel] : f;
}

- (NSString *)instructionForStep:(NSInteger)i {
    NSString *f = @(Steps[i].instruction);
    return [f containsString:@"%@"] ? [NSString stringWithFormat:f, self.tkLevel] : f;
}

#pragma mark Existing ROIs

// Reopening the tool on an image already measured picks up its points and calibration.
- (void)adoptExistingROIs {
    for (ROI *r in [self.sliceROIs copy]) {
        // Helper lines, and the point labels (the only non-selectable text ROIs).
        if ([r.name hasPrefix:HelperPrefix] || (r.type == tText && !r.selectable)) { [self.sliceROIs removeObject:r]; continue; }
        if (r.type == tMesure && [r.name hasPrefix:CalibrationPrefix]) {
            double mm = [[r.name substringFromIndex:CalibrationPrefix.length] doubleValue];
            [self applyCalibrationLine:r mm:mm];
            continue;
        }
        if (r.type != t2DPoint) continue;
        for (NSInteger i = 0; i < SPLandmarkCount; i++) {
            if (_rois[i]) continue;
            if ([r.name isEqualToString:[self nameForStep:i]]) { _rois[i] = r; r.displayTextualData = NO; break; }
            if ((i == SPTKPosterior || i == SPTKAnterior) && [r.name hasPrefix:@"T5 "]) {
                self.tkLevel = @"T5";
                if ([r.name isEqualToString:[self nameForStep:i]]) { _rois[i] = r; r.displayTextualData = NO; break; }
            }
        }
    }
}

#pragma mark Panel

static NSTextField *Label(NSString *s, CGFloat size, BOOL bold) {
    NSTextField *t = [NSTextField wrappingLabelWithString:s];
    t.font = bold ? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size];
    return t;
}

static NSButton *Button(NSString *title, id target, SEL action) {
    NSButton *b = [NSButton buttonWithTitle:title target:target action:action];
    b.bezelStyle = NSBezelStyleRounded;
    return b;
}

- (void)buildPanel {
    NSPanel *p = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 400, 740)
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow | NSWindowStyleMaskResizable
                                              backing:NSBackingStoreBuffered defer:NO];
    p.title = @"SagitalApp · Parámetros espinopélvicos";
    p.floatingPanel = YES;
    p.becomesKeyOnlyIfNeeded = YES;
    p.hidesOnDeactivate = YES;
    p.releasedWhenClosed = NO;
    p.delegate = self;
    p.minSize = NSMakeSize(360, 560);
    self.panel = p;

    self.instruction = Label(@"", 13, YES);
    self.instruction.textColor = NSColor.systemOrangeColor;

    NSTableView *t = [NSTableView new];
    t.headerView = nil;
    t.rowHeight = 20;
    t.usesAlternatingRowBackgroundColors = YES;
    t.allowsEmptySelection = YES;
    NSTableColumn *state = [[NSTableColumn alloc] initWithIdentifier:@"state"];
    state.width = 22;
    state.resizingMask = NSTableColumnNoResizing;
    NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    name.resizingMask = NSTableColumnAutoresizingMask;
    [t addTableColumn:state];
    [t addTableColumn:name];
    t.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    t.dataSource = self;
    t.delegate = self;
    self.table = t;
    NSScrollView *ts = [NSScrollView new];
    ts.documentView = t;
    ts.hasVerticalScroller = YES;
    ts.borderType = NSBezelBorder;

    NSStackView *stepButtons = [NSStackView stackViewWithViews:@[
        Button(@"Saltar", self, @selector(skip:)),
        Button(@"Borrar punto", self, @selector(deletePoint:)),
        Button(@"Reiniciar", self, @selector(reset:)),
    ]];

    NSPopUpButton *tk = [NSPopUpButton new];
    [tk addItemsWithTitles:@[@"T4–T12", @"T5–T12"]];
    [tk selectItemAtIndex:[self.tkLevel isEqualToString:@"T5"] ? 1 : 0];
    tk.target = self;
    tk.action = @selector(tkChanged:);
    self.tkPopup = tk;
    NSStackView *tkRow = [NSStackView stackViewWithViews:@[Label(@"Cifosis torácica:", 12, NO), tk]];

    NSTextView *r = [NSTextView new];
    r.editable = NO;
    r.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    r.textContainerInset = NSMakeSize(4, 6);
    r.autoresizingMask = NSViewWidthSizable;
    self.results = r;
    NSScrollView *rs = [NSScrollView new];
    rs.documentView = r;
    rs.hasVerticalScroller = YES;
    rs.borderType = NSBezelBorder;

    self.calibrationLabel = Label(@"", 11, NO);
    self.calibrationLabel.textColor = NSColor.secondaryLabelColor;
    NSStackView *bottom = [NSStackView stackViewWithViews:@[
        Button(@"Calibrar…", self, @selector(calibrate:)),
        Button(@"Copiar resultados", self, @selector(copyResults:)),
        Button(@"Acerca de…", self, @selector(showAbout:)),
    ]];

    // Hidden until CheckForUpdate finds a newer release.
    self.updateButton = Button(@"", self, @selector(installUpdate:));
    self.updateButton.bezelColor = NSColor.controlAccentColor;
    self.updateButton.keyEquivalent = @"";
    self.updateButton.hidden = YES;

    // Messages from the author (sagitalapp.com), below everything else.
    self.notice = [NSTextField wrappingLabelWithString:@""];
    self.notice.font = [NSFont systemFontOfSize:12];
    self.notice.selectable = YES;
    self.notice.preferredMaxLayoutWidth = 340;
    NSBox *noticeBox = [NSBox new];
    noticeBox.title = @"Avisos de SagitalApp";
    noticeBox.titleFont = [NSFont systemFontOfSize:11];
    noticeBox.contentViewMargins = NSMakeSize(8, 6);
    noticeBox.contentView = self.notice;
    [self.notice.heightAnchor constraintGreaterThanOrEqualToConstant:32].active = YES;
    [self showNotice];

    NSStackView *v = [NSStackView stackViewWithViews:@[self.updateButton, self.instruction, ts, stepButtons, tkRow, rs, self.calibrationLabel, bottom, noticeBox]];
    v.orientation = NSUserInterfaceLayoutOrientationVertical;
    v.alignment = NSLayoutAttributeLeading;
    v.spacing = 10;
    v.edgeInsets = NSEdgeInsetsMake(14, 14, 14, 14);
    p.contentView = v;
    for (NSView *w in @[self.updateButton, self.instruction, ts, rs, self.calibrationLabel, noticeBox]) {
        [w.widthAnchor constraintEqualToAnchor:v.widthAnchor constant:-28].active = YES;
    }
    [ts.heightAnchor constraintEqualToConstant:SPLandmarkCount * 22 + 4].active = YES;
    [rs.heightAnchor constraintGreaterThanOrEqualToConstant:170].active = YES;
    [self.instruction.heightAnchor constraintGreaterThanOrEqualToConstant:34].active = YES;

    // Next to the viewer, on its right when there is room.
    NSRect vf = self.viewer.window.frame, sf = self.viewer.window.screen.visibleFrame;
    CGFloat x = MIN(NSMaxX(vf) - 420, NSMaxX(sf) - 420);
    [p setFrameTopLeftPoint:NSMakePoint(MAX(x, NSMinX(sf)), NSMaxY(vf) - 40)];
    [p orderFront:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv { return SPLandmarkCount; }

- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)col row:(NSInteger)row {
    if ([col.identifier isEqualToString:@"state"]) {
        if (row == self.active) return @"▶";
        if (_rois[row]) return @"✓";
        return _skipped[row] ? @"–" : @"○";
    }
    NSString *s = [self instructionForStep:row];
    return Steps[row].optional ? [s stringByAppendingString:@" · opcional"] : s;
}

- (BOOL)tableView:(NSTableView *)tv shouldEditTableColumn:(NSTableColumn *)col row:(NSInteger)row { return NO; }

- (void)tableViewSelectionDidChange:(NSNotification *)n {
    NSInteger row = self.table.selectedRow;
    if (row >= 0 && row != self.active) [self setActiveStep:row];
}

#pragma mark Steps

- (void)setActiveStep:(NSInteger)i {
    self.active = i;
    if (i >= 0) {
        self.instruction.stringValue = [NSString stringWithFormat:@"Hacé clic en: %@%@", [self instructionForStep:i],
                                        _rois[i] ? @"\n(reemplaza el punto actual)" : @""];
        [self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
        [self.table scrollRowToVisible:i];
        [self.viewer setROIToolTag:t2DPoint];
    } else {
        self.instruction.stringValue = @"Listo. Arrastrá cualquier punto para ajustarlo, o elegí un paso para rehacerlo.";
        [self.table deselectAll:nil];
    }
    [self.table reloadData];
}

- (void)selectNextStepFrom:(NSInteger)start {
    for (NSInteger k = 0; k < SPLandmarkCount; k++) {
        NSInteger i = (start + k) % SPLandmarkCount;
        if (!_rois[i] && !_skipped[i]) { [self setActiveStep:i]; return; }
    }
    [self setActiveStep:-1];
}

- (void)roiAdded:(NSNotification *)n {
    if (n.object != self.viewer.imageView || self.active < 0) return;
    ROI *r = n.userInfo[@"ROI"];
    if (r.type != t2DPoint || [n.userInfo[@"sliceNumber"] intValue] != self.slice) return;

    NSInteger i = self.active;
    if (_rois[i] && _rois[i] != r) [self.viewer deleteROI:_rois[i]];
    _rois[i] = r;
    _skipped[i] = NO;
    r.name = [self nameForStep:i];
    // Horos' text box would take clicks meant for the next landmark nearby; the name is drawn
    // by a non-selectable label instead (updateLabels).
    r.displayTextualData = NO;
    [r setNSColor:RGB(NSColor.yellowColor) globally:NO];
    [self selectNextStepFrom:i + 1];
    [self refresh:YES];
}

- (void)skip:(id)sender {
    if (self.active < 0) return;
    _skipped[self.active] = YES;
    [self selectNextStepFrom:self.active + 1];
}

- (void)deletePoint:(id)sender {
    NSInteger i = self.table.selectedRow >= 0 ? self.table.selectedRow : self.active;
    if (i < 0 || !_rois[i]) return;
    [self.viewer deleteROI:_rois[i]];
    _rois[i] = nil;
    [self setActiveStep:i];
    [self refresh:YES];
}

- (void)reset:(id)sender {
    NSAlert *a = [NSAlert new];
    a.messageText = @"¿Borrar todos los puntos de esta imagen?";
    [a addButtonWithTitle:@"Borrar"];
    [a addButtonWithTitle:@"Cancelar"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    for (NSInteger i = 0; i < SPLandmarkCount; i++) {
        if (_rois[i]) [self.viewer deleteROI:_rois[i]];
        _rois[i] = nil;
        _skipped[i] = NO;
    }
    [self selectNextStepFrom:0];
    [self refresh:YES];
}

- (void)tkChanged:(id)sender {
    self.tkLevel = self.tkPopup.indexOfSelectedItem == 1 ? @"T5" : @"T4";
    for (NSInteger i = SPTKPosterior; i <= SPTKAnterior; i++) _rois[i].name = [self nameForStep:i];
    [self setActiveStep:self.active];
    [self refresh:YES];
}

#pragma mark Calibration

- (void)applyCalibrationLine:(ROI *)line mm:(double)mm {
    NSArray *pts = line.points;
    if (pts.count < 2 || mm <= 0) return;
    NSPoint a = [pts[0] point], b = [pts[1] point];
    DCMPix *pix = self.viewer.imageView.curDCM;
    double sx = pix.pixelSpacingX > 0 ? pix.pixelSpacingX : 1, sy = pix.pixelSpacingY > 0 ? pix.pixelSpacingY : sx;
    double d = hypot((b.x - a.x) * sx, (b.y - a.y) * sy);
    if (d <= 0) return;
    self.calibrationMMPerPx = mm / d;  // scale applied on top of the native spacing
}

- (void)calibrate:(id)sender {
    ROI *line = nil;
    for (ROI *r in self.sliceROIs) {
        if (r.type != tMesure || [r.name hasPrefix:HelperPrefix]) continue;
        if (r.ROImode == ROI_selected || r.ROImode == ROI_selectedModify) { line = r; break; }
        line = r;  // otherwise the last one drawn
    }
    NSAlert *a = [NSAlert new];
    if (!line) {
        a.messageText = @"Dibujá primero una línea de medición";
        a.informativeText = @"Usá la herramienta de longitud de Horos sobre un objeto de tamaño conocido (regla, esfera de calibración, implante) y volvé a tocar Calibrar.";
        [a runModal];
        return;
    }
    a.messageText = @"Calibración";
    a.informativeText = @"Longitud real de la línea seleccionada, en mm:";
    NSTextField *f = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 120, 24)];
    if ([line.name hasPrefix:CalibrationPrefix]) f.stringValue = [line.name substringFromIndex:CalibrationPrefix.length];
    a.accessoryView = f;
    [a addButtonWithTitle:@"Calibrar"];
    [a addButtonWithTitle:@"Cancelar"];
    a.window.initialFirstResponder = f;
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    double mm = [[f.stringValue stringByReplacingOccurrencesOfString:@"," withString:@"."] doubleValue];
    if (mm <= 0) return;
    [self applyCalibrationLine:line mm:mm];
    line.name = [NSString stringWithFormat:@"%@%g mm", CalibrationPrefix, mm];
    [self refresh:YES];
}

// mm per pixel in x and y, or 0 when the image has no spacing and was not calibrated.
- (NSSize)mmPerPixel:(NSString **)source {
    DCMPix *pix = self.viewer.imageView.curDCM;
    double sx = pix.pixelSpacingX, sy = pix.pixelSpacingY > 0 ? pix.pixelSpacingY : pix.pixelSpacingX;
    if (self.calibrationMMPerPx > 0) {
        if (sx <= 0) sx = sy = 1;
        *source = @"calibración manual";
        return NSMakeSize(sx * self.calibrationMMPerPx, sy * self.calibrationMMPerPx);
    }
    if (sx > 0) {
        *source = @"espaciado DICOM";
        return NSMakeSize(sx, sy);
    }
    *source = nil;
    return NSZeroSize;
}

#pragma mark Results

- (void)tick:(NSTimer *)t {
    if (!self.viewer.window.isVisible) return;
    [self refresh:NO];
}

- (void)refresh:(BOOL)force {
    NSMutableArray *slice = self.sliceROIs;
    SPInput in = {0};
    NSMutableString *sig = [NSMutableString string];
    BOOL lost = NO;
    for (NSInteger i = 0; i < SPLandmarkCount; i++) {
        if (_rois[i] && ![slice containsObject:_rois[i]]) { _rois[i] = nil; lost = YES; }  // deleted in Horos
        if (!_rois[i]) continue;
        NSPoint pt = _rois[i].rect.origin;
        in.p[i] = (SPPoint){pt.x, pt.y, 1};
        [sig appendFormat:@"%ld:%.2f,%.2f;", (long)i, pt.x, pt.y];
    }
    NSString *source = nil;
    NSSize mm = [self mmPerPixel:&source];
    in.mmPerPixelX = mm.width;
    in.mmPerPixelY = mm.height;
    [sig appendFormat:@"%g,%g,%@,%g", mm.width, mm.height, self.tkLevel, self.viewer.imageView.scaleValue];
    if (lost) [self.table reloadData];
    if (!force && [sig isEqualToString:self.lastSignature]) return;
    self.lastSignature = sig;

    SPResult r = SPCompute(&in);
    [self showResults:r];
    [self updateHelperLines:in];
    [self updateLabels];
    self.calibrationLabel.stringValue = source
        ? [NSString stringWithFormat:@"Escala: %.3f mm/píxel (%@). En radiografías la magnificación puede alterar el SVA.", mm.width, source]
        : @"Sin escala: la imagen no tiene espaciado de píxel. El SVA se muestra en píxeles hasta calibrar.";
    [self.viewer.imageView setNeedsDisplay:YES];
}

static NSString *Deg(int has, double v) { return has ? [NSString stringWithFormat:@"%6.1f°", v] : @"     —"; }

- (void)showResults:(SPResult)r {
    NSString *sva = !r.hasSVA ? @"     —" : [NSString stringWithFormat:r.svaInMM ? @"%+6.1f mm" : @"%+6.0f px", r.SVA];
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"PI    Incidencia pélvica   %@\n", Deg(r.hasPI, r.PI)];
    [s appendFormat:@"PT    Tilt pélvico         %@\n", Deg(r.hasPT, r.PT)];
    [s appendFormat:@"SS    Slope sacro          %@\n", Deg(r.hasSS, r.SS)];
    [s appendFormat:@"LL    Lordosis L1–S1       %@\n", Deg(r.hasLL, r.LL)];
    [s appendFormat:@"PI−LL Mismatch             %@\n", Deg(r.hasPILL, r.PILL)];
    [s appendFormat:@"TK    Cifosis %@–T12       %@\n", self.tkLevel, Deg(r.hasTK, r.TK)];
    [s appendFormat:@"T1PA  T1 pelvic angle      %@\n", Deg(r.hasT1PA, r.T1PA)];
    [s appendFormat:@"SVA   C7 – S1 posterior    %@\n", sva];

    const char *mPILL = SPSchwabPILL(&r), *mPT = SPSchwabPT(&r), *mSVA = SPSchwabSVA(&r);
    if (mPILL || mPT || mSVA) {
        [s appendString:@"\nModificadores SRS-Schwab\n"];
        if (mPILL) [s appendFormat:@"  PI−LL  %-3s (0 <10° · + 10–20° · ++ >20°)\n", mPILL];
        if (mPT) [s appendFormat:@"  PT     %-3s (0 <20° · + 20–30° · ++ >30°)\n", mPT];
        if (mSVA) [s appendFormat:@"  SVA    %-3s (0 <4 cm · + 4–9,5 cm · ++ >9,5 cm)\n", mSVA];
    }
    if (r.hasLL || r.hasTK) [s appendString:@"\nLL y TK positivos = lordosis y cifosis.\n"];
    if (r.hasSVA || r.hasPT) [s appendString:@"SVA y PT positivos = hacia anterior.\n"];
    self.resultsText = s;
    self.results.string = s;
}

#pragma mark Helper lines

- (void)setLine:(NSString *)key from:(NSPoint)a to:(NSPoint)b color:(NSColor *)color show:(BOOL)show {
    ROI *r = self.helpers[key];
    if (r && ![self.sliceROIs containsObject:r]) r = nil;
    if (!show) { r.hidden = YES; return; }
    if (!r) {
        r = [self.viewer newROI:tMesure];
        r.name = [HelperPrefix stringByAppendingString:key];
        r.displayTextualData = NO;
        r.thickness = 1.5;
        [r setNSColor:RGB(color) globally:NO];
        r.selectable = NO;
        [self.sliceROIs addObject:r];
        self.helpers[key] = r;
    }
    r.hidden = NO;
    r.locked = NO;
    r.points = [NSMutableArray arrayWithObjects:[MyPoint point:a], [MyPoint point:b], nil];
    r.locked = YES;
}

// Each point's name, just right of it. Text ROIs that are not selectable never take a click.
- (void)updateLabels {
    float scale = self.viewer.imageView.scaleValue;
    if (scale <= 0) scale = 1;
    for (NSInteger i = 0; i < SPLandmarkCount; i++) {
        NSString *key = [NSString stringWithFormat:@"label%ld", (long)i];
        ROI *l = self.helpers[key];
        if (l && ![self.sliceROIs containsObject:l]) l = nil;
        if (!_rois[i]) { l.hidden = YES; continue; }
        if (!l) {
            l = [self.viewer newROI:tText];
            [l setNSColor:RGB(NSColor.yellowColor) globally:NO];
            l.selectable = NO;
            [self.sliceROIs addObject:l];
            self.helpers[key] = l;
        }
        l.hidden = NO;
        l.name = [self nameForStep:i];  // also sizes the rect to the text
        NSRect rr = l.rect;
        NSPoint pt = _rois[i].rect.origin;
        rr.origin = NSMakePoint(pt.x + (rr.size.width / 2 + 10) / scale, pt.y);  // tText is drawn centred on its origin
        l.rect = rr;
    }
}

static NSPoint Mid(SPPoint a, SPPoint b) { return NSMakePoint((a.x + b.x) / 2, (a.y + b.y) / 2); }
static NSPoint NP(SPPoint a) { return NSMakePoint(a.x, a.y); }

- (void)updateHelperLines:(SPInput)in {
    const SPPoint *p = in.p;
    NSColor *green = NSColor.systemGreenColor, *cyan = NSColor.cyanColor, *orange = NSColor.orangeColor;

    static const SPLandmark endplates[][2] = {
        {SPS1Posterior, SPS1Anterior}, {SPL1Posterior, SPL1Anterior},
        {SPT12Posterior, SPT12Anterior}, {SPTKPosterior, SPTKAnterior},
    };
    for (int i = 0; i < 4; i++) {
        SPPoint a = p[endplates[i][0]], b = p[endplates[i][1]];
        // Extended past both corners so the angle reads clearly.
        NSPoint d = NSMakePoint((b.x - a.x) * 0.35, (b.y - a.y) * 0.35);
        [self setLine:[NSString stringWithFormat:@"platillo%d", i] from:NSMakePoint(a.x - d.x, a.y - d.y)
                   to:NSMakePoint(b.x + d.x, b.y + d.y) color:green show:a.ok && b.ok];
    }

    SPPoint f1 = p[SPFemoralHead1], f2 = p[SPFemoralHead2];
    BOOL hasHip = f1.ok || f2.ok;
    NSPoint hip = f1.ok && f2.ok ? Mid(f1, f2) : NP(f1.ok ? f1 : f2);
    [self setLine:@"bicoxofemoral" from:NP(f1) to:NP(f2) color:cyan show:f1.ok && f2.ok];

    BOOL hasS1 = p[SPS1Posterior].ok && p[SPS1Anterior].ok;
    NSPoint mid = hasS1 ? Mid(p[SPS1Posterior], p[SPS1Anterior]) : NSZeroPoint;
    [self setLine:@"cadera-S1" from:hip to:mid color:cyan show:hasHip && hasS1];

    // Perpendicular to S1 at its midpoint, towards the hips, as long as the hip line (PI).
    BOOL perp = hasHip && hasS1;
    NSPoint perpEnd = mid;
    if (perp) {
        double ex = p[SPS1Anterior].x - p[SPS1Posterior].x, ey = p[SPS1Anterior].y - p[SPS1Posterior].y;
        double len = hypot(ex, ey), reach = hypot(hip.x - mid.x, hip.y - mid.y);
        double nx = -ey / len, ny = ex / len;
        if (nx * (hip.x - mid.x) + ny * (hip.y - mid.y) < 0) { nx = -nx; ny = -ny; }
        perpEnd = NSMakePoint(mid.x + nx * reach, mid.y + ny * reach);
    }
    [self setLine:@"perpendicular-S1" from:mid to:perpEnd color:green show:perp];

    SPPoint t1 = p[SPT1Center];
    [self setLine:@"cadera-T1" from:hip to:NP(t1) color:cyan show:hasHip && t1.ok && hasS1];

    // C7 plumb line down to the level of the S1 posterior corner (SVA).
    SPPoint c7 = p[SPC7Center], s1p = p[SPS1Posterior];
    [self setLine:@"plomada-C7" from:NP(c7) to:NSMakePoint(c7.x, s1p.ok ? s1p.y : c7.y) color:orange show:c7.ok && s1p.ok];
    [self setLine:@"SVA" from:NSMakePoint(c7.x, s1p.y) to:NP(s1p) color:orange show:c7.ok && s1p.ok];
}

#pragma mark Actions

- (void)copyResults:(id)sender {
    NSPasteboard *pb = NSPasteboard.generalPasteboard;
    [pb clearContents];
    [pb setString:self.resultsText ?: @"" forType:NSPasteboardTypeString];
}

- (void)showAbout:(id)sender {
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"SagitalApp %@", BundleVersion()];
    a.informativeText = @"Parámetros espinopélvicos en Horos: mide PI, PT, SS, LL, PI−LL, cifosis torácica, T1PA y SVA, con los modificadores SRS-Schwab.\n\n"
                        @"Autor: Dr. Bernardo Sonzini Astudillo\ncolumna-spine.com\n\n"
                        @"Herramienta de apoyo; no es un dispositivo médico. Código abierto (licencia MIT).\n\n"
                        @"Al instalarse o actualizarse avisa a sagitalapp.com la versión y la ubicación aproximada (país y ciudad), para contar usuarios, y desde ahí recibe los avisos del autor. Nunca envía imágenes ni datos de pacientes.";
    [a addButtonWithTitle:@"Abrir columna-spine.com"];
    [a addButtonWithTitle:@"Cerrar"];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://www.columna-spine.com/"]];
    }
}

- (void)showNotice {
    self.notice.stringValue = [NSUserDefaults.standardUserDefaults stringForKey:NoticeKey] ?: @"";
}

- (void)showUpdateButton {
    if (!LatestRelease) return;
    self.updateButton.title = [NSString stringWithFormat:@"Actualizar a la versión %@…", LatestRelease[@"version"]];
    self.updateButton.hidden = NO;
}

- (void)installUpdate:(id)sender {
    NSString *version = LatestRelease[@"version"];
    NSString *notes = [LatestRelease[@"notes"] stringByReplacingOccurrencesOfString:@"[*`#]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, [LatestRelease[@"notes"] length])];
    notes = [notes stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (notes.length > 600) notes = [[notes substringToIndex:600] stringByAppendingString:@"…"];
    NSAlert *a = [NSAlert new];
    a.messageText = [NSString stringWithFormat:@"Hay una versión nueva: %@ (tenés la %@)", version, BundleVersion()];
    a.informativeText = [NSString stringWithFormat:@"%@%@Se va a descargar el instalador y se abrirá. Seguí sus pasos y, al terminar, cerrá y volvé a abrir Horos.",
                         notes, notes.length ? @"\n\n" : @""];
    [a addButtonWithTitle:@"Descargar e instalar"];
    [a addButtonWithTitle:@"Ahora no"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;

    self.updateButton.enabled = NO;
    self.updateButton.title = @"Descargando la actualización…";
    NSURL *url = [NSURL URLWithString:LatestRelease[@"pkg"]];
    [[NSURLSession.sharedSession downloadTaskWithURL:url completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        NSURL *dest = nil;
        if (tmp && !err && status == 200) {
            NSURL *downloads = [NSFileManager.defaultManager URLsForDirectory:NSDownloadsDirectory inDomains:NSUserDomainMask].firstObject;
            dest = [downloads URLByAppendingPathComponent:[NSString stringWithFormat:@"Instalar SagitalApp Horos %@.pkg", version]];
            [NSFileManager.defaultManager removeItemAtURL:dest error:nil];
            if (![NSFileManager.defaultManager moveItemAtURL:tmp toURL:dest error:nil]) dest = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.updateButton.enabled = YES;
            [self showUpdateButton];
            if (dest) { [NSWorkspace.sharedWorkspace openURL:dest]; return; }
            NSAlert *e = [NSAlert new];
            e.messageText = @"No se pudo descargar la actualización.";
            e.informativeText = @"Revisá la conexión a internet o descargala desde la página del plugin en GitHub.";
            [e addButtonWithTitle:@"Abrir la página"];
            [e addButtonWithTitle:@"Cerrar"];
            if ([e runModal] == NSAlertFirstButtonReturn) {
                [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://github.com/bersonzini-glitch/horos-parametros-espinopelvicos/releases/latest"]];
            }
        });
    }] resume];
}

- (void)viewerClosed:(NSNotification *)n { [self.panel close]; }

- (void)windowWillClose:(NSNotification *)n {
    [self.timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [Controllers removeObject:self];
}

@end

#pragma mark - Plugin

@interface SpinopelvicParams : PluginFilter
@end

@implementation SpinopelvicParams

- (void)initPlugin {}

- (long)filterImage:(NSString *)menuName {
    ViewerController *v = [ViewerController frontMostDisplayed2DViewer];
    if (!v) {
        NSAlert *a = [NSAlert new];
        a.messageText = @"Abrí primero una radiografía de perfil en el visor.";
        [a runModal];
        return 0;
    }
    [SPController openForViewer:v];
    return 0;
}

@end
