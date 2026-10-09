/*
 *  LEDSAOptionsController.h
 *  LED Spectrum Analyser
 *
 *  The "LED Spectrum Analyser Options" window: Layout / Appearance / Advanced tabs laid out like
 *  the 3.0.7 panel. Built in code so no Interface Builder tooling is needed to compile it.
 *
 */

#import <Cocoa/Cocoa.h>

namespace led { class Engine; }


@protocol LEDSAOptionsDelegate <NSObject>
- (led::Engine*)optionsEngine;
- (double)optionsCurrentTime;
- (void)optionsShowManual;
@end


@interface LEDSAOptionsController : NSObject <NSWindowDelegate>

@property (nonatomic, weak) id<LEDSAOptionsDelegate> delegate;
@property (nonatomic, readonly) NSWindow* window;
@property (nonatomic, readonly) BOOL isOpen;

- (void)showWindow;
- (void)close;
- (void)refresh;						// update the controls from the current settings
- (void)selectTab:(NSInteger)index;		// 0-based

@end
