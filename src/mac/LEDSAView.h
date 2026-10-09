/*
 *  LEDSAView.h
 *  LED Spectrum Analyser
 *
 *  The visualizer's own view, added as a subview of the view iTunes / Music hands the plug-in.
 *  It hosts the Core Animation layer tree and takes keyboard input.
 *
 */

#import <Cocoa/Cocoa.h>


@protocol LEDSAViewDelegate <NSObject>
- (void)visualizerView:(NSView*)view didResize:(NSSize)size scale:(CGFloat)scale;
- (BOOL)visualizerView:(NSView*)view handleCharacter:(unichar)character;
- (void)visualizerViewShowOptions:(NSView*)view;
- (void)visualizerViewShowManual:(NSView*)view;
@end


@interface LEDSAView : NSView

@property (nonatomic, weak) id<LEDSAViewDelegate> delegate;

@end
