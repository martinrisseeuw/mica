#import <AppKit/AppKit.h>
int main(int argc, char **argv) { @autoreleasepool {
    NSString *output=[NSString stringWithUTF8String:argv[1]];
    [[NSFileManager defaultManager] createDirectoryAtPath:output withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSNumber *number in @[@16,@32,@128,@256,@512]) for (NSNumber *scale in @[@1,@2]) {
        NSInteger pixels=number.integerValue*scale.integerValue;
        NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        NSGraphicsContext *context=[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext saveGraphicsState]; NSGraphicsContext.currentContext=context;
        NSAffineTransform *transform=[NSAffineTransform transform]; [transform scaleBy:pixels/1024.0]; [transform concat];
        NSBezierPath *background=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(72,72,880,880) xRadius:198 yRadius:198];
        [[NSColor colorWithSRGBRed:0.16 green:0.27 blue:0.36 alpha:1] setFill]; [background fill];
        for (NSInteger layer=0;layer<3;layer++) {
            CGFloat y=280+layer*140;
            NSBezierPath *sheet=[NSBezierPath bezierPath];
            [sheet moveToPoint:NSMakePoint(235,y+110)]; [sheet lineToPoint:NSMakePoint(510,y+245)];
            [sheet lineToPoint:NSMakePoint(790,y+110)]; [sheet lineToPoint:NSMakePoint(510,y-25)]; [sheet closePath];
            [[NSColor colorWithSRGBRed:0.72+layer*0.09 green:0.79+layer*0.07 blue:0.81+layer*0.07 alpha:1] setFill]; [sheet fill];
        }
        [NSGraphicsContext restoreGraphicsState];
        NSString *name=[NSString stringWithFormat:@"icon_%ldx%ld%@.png",number.integerValue,number.integerValue,scale.intValue==2?@"@2x":@""];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[output stringByAppendingPathComponent:name] atomically:YES];
    }
} return 0; }
