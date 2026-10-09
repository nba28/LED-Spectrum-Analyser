/*
 *  LEDSARenderer.h
 *  LED Spectrum Analyser
 *
 *  Builds and drives the Core Animation layer tree that draws the visualizer. All drawing is
 *  composited on the GPU by Core Animation (Metal on current macOS); per frame only the sizes of
 *  the lit parts of the bars, the peak markers and the needles change, plus a few opacities.
 *
 */

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

namespace led { class Engine; }


@interface LEDSARenderer : NSObject

- (instancetype)initWithRootLayer:(CALayer*)root engine:(led::Engine*)engine;

- (void)setViewSize:(CGSize)size scale:(CGFloat)scale;
- (void)setArtwork:(CGImageRef)image;			// NULL removes it
- (void)updateAtTime:(double)now;				// call once per frame

@end
