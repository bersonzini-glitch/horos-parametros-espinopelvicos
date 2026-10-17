// Minimal declarations of the Horos classes this plugin uses.
// The real classes live in the Horos executable; we link with -bundle_loader.
// Signatures come from Horos' own headers (github.com/horosproject/horos, Horos/Sources).

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(short, ToolMode) {
    tMesure = 5,
    tText = 13,
    t2DPoint = 19,
};

enum { ROI_sleep = 0, ROI_drawing = 1, ROI_selected = 2, ROI_selectedModify = 3 };

@interface PluginFilter : NSObject
- (void)initPlugin;
- (long)filterImage:(NSString *)menuName;
@end

@interface MyPoint : NSObject
+ (MyPoint *)point:(NSPoint)a;
@property (assign) NSPoint point;
@end

@interface DCMPix : NSObject
@property double pixelSpacingX, pixelSpacingY;
@end

@interface ROI : NSObject
@property (nonatomic) BOOL hidden, locked, selectable;
@property (nonatomic, copy) NSString *name;
@property ToolMode type;
@property (nonatomic, setter=setROIMode:) long ROImode;
@property (strong) NSMutableArray *points;
@property (setter=setROIRect:) NSRect rect;
@property (nonatomic) float thickness;
@property BOOL displayTextualData;
- (void)setNSColor:(NSColor *)color globally:(BOOL)g;
@end

@interface DCMView : NSOpenGLView
@property (readonly) short curImage;
@property (readonly, strong) DCMPix *curDCM;
@property (nonatomic) float scaleValue;
@end

@interface ViewerController : NSWindowController
+ (ViewerController *)frontMostDisplayed2DViewer;
- (DCMView *)imageView;
- (NSMutableArray *)roiList;  // one NSMutableArray<ROI *> per image
// Returns an autoreleased ROI despite the "new" prefix.
- (ROI *)newROI:(ToolMode)type NS_RETURNS_NOT_RETAINED;
- (void)setROIToolTag:(ToolMode)roitype;
- (void)deleteROI:(ROI *)roi;
@end
