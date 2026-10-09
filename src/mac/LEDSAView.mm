/*
 *  LEDSAView.mm
 *  LED Spectrum Analyser
 *
 */

#import "LEDSAView.h"
#import <Carbon/Carbon.h>		// virtual key codes


@implementation LEDSAView

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	if ( self )
	{
		// layer-hosting view: we own the layer tree

		CALayer* root = [CALayer layer];
		root.backgroundColor = CGColorGetConstantColor( kCGColorBlack );
		root.layoutManager = nil;
		self.layer = root;
		self.wantsLayer = YES;
		self.layerContentsRedrawPolicy = NSViewLayerContentsRedrawNever;
		self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	}
	return self;
}


- (BOOL)isOpaque
{
	return YES;
}


- (BOOL)acceptsFirstResponder
{
	return YES;
}


- (BOOL)acceptsFirstMouse:(NSEvent*)event
{
	return YES;
}


- (CGFloat)currentScale
{
	NSWindow* w = self.window;
	CGFloat s = w? w.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor;
	return s > 0? s : 1.0;
}


- (void)notifyResize
{
	CGFloat s = [self currentScale];

	self.layer.contentsScale = s;
	[self.delegate visualizerView:self didResize:self.bounds.size scale:s];
}


- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	[self notifyResize];
}


- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];
	[self notifyResize];

	if ( self.window )
		[self.window makeFirstResponder:self];
}


- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
	[self notifyResize];
}


- (void)mouseDown:(NSEvent*)event
{
	[self.window makeFirstResponder:self];
	[super mouseDown:event];
}


- (void)keyDown:(NSEvent*)event
{
	// leave command / control / option combinations, and the keys the host uses itself (space,
	// tab, escape, return and the arrows), to iTunes / Music

	NSEventModifierFlags mods = event.modifierFlags & ( NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption );

	switch ( event.keyCode )
	{
		case kVK_Space:
		case kVK_Tab:
		case kVK_Escape:
		case kVK_Return:
		case kVK_ANSI_KeypadEnter:
		case kVK_LeftArrow:
		case kVK_RightArrow:
		case kVK_UpArrow:
		case kVK_DownArrow:
			[super keyDown:event];
			return;
	}

	NSString* chars = event.charactersIgnoringModifiers;

	if ( mods == 0 && chars.length == 1 && [self.delegate visualizerView:self handleCharacter:[chars characterAtIndex:0]] )
		return;

	[super keyDown:event];
}


- (NSMenu*)menuForEvent:(NSEvent*)event
{
	NSMenu* menu = [[NSMenu alloc] initWithTitle:@"LEDSA Contextual"];

	[menu addItemWithTitle:@"Visualizer Options…" action:@selector( showOptions: ) keyEquivalent:@""].target = self;
	[menu addItemWithTitle:@"User Manual…" action:@selector( showManual: ) keyEquivalent:@""].target = self;
	return menu;
}


- (IBAction)showOptions:(id)sender
{
	[self.delegate visualizerViewShowOptions:self];
}


- (IBAction)showManual:(id)sender
{
	[self.delegate visualizerViewShowManual:self];
}

@end
