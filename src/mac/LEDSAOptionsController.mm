/*
 *  LEDSAOptionsController.mm
 *  LED Spectrum Analyser
 *
 */

#import "LEDSAOptionsController.h"
#import "CGColourConversion.h"
#include "LEDEngine.h"

using namespace led;


enum
{
	// Layout
	kTagLayoutSideBySide = 100, kTagLayoutBackToBack, kTagLayoutAnalogue,
	kTagBands10 = 110, kTagBands18, kTagBands24, kTagBands31,
	kTagShowVU = 120, kTagScales, kTagProgress, kTagHelp,
	kTagInfoTitle = 130, kTagInfoArtist, kTagInfoAlbum, kTagInfoYear, kTagInfoStation,
	kTagStayVisible = 140, kTagAbove, kTagSizeToFit,
	kTagCoverShow = 150, kTagCoverBackground, kTagCoverColours,

	// Appearance
	kTagSpectrumPeak = 200, kTagSpectrumBar, kTagSpectrumBlend, kTagVUPeak, kTagVUBar, kTagVUBlend, kTagBackground,
	kTagBlend = 210, kTagRandomise, kTagBlendToValue, kTagAnimate,
	kTagPeaks = 220, kTagUnlit, kTagReflections, kTagPerspective,
	kTagSavePreset = 230, kTagClearPresets,

	// Advanced
	kTagLog = 300, kTagBinPeak, kTagExpDecay, kTagPreventSleep,
	kTagPeakHold = 310, kTagPeakDecay, kTagBarDecay, kTagVUDecay, kTagVUGain, kTagSpectrumGain,
	kTagDiagnostics = 320
};


@interface LEDSAFlippedView : NSView
@end

@implementation LEDSAFlippedView
- (BOOL)isFlipped { return YES; }
@end


@interface LEDSAOptionsController ()
{
	NSWindow*		window;
	NSTabView*		tabs;
	NSView*			currentPane;
	NSMutableDictionary<NSNumber*, NSControl*>*	controls;
	NSMutableDictionary<NSNumber*, NSTextField*>*	valueLabels;
}
@end


@implementation LEDSAOptionsController

- (instancetype)init
{
	self = [super init];

	if ( self )
	{
		controls = [NSMutableDictionary dictionary];
		valueLabels = [NSMutableDictionary dictionary];
	}
	return self;
}


- (NSWindow*)window
{
	return window;
}


- (BOOL)isOpen
{
	return window != nil && window.isVisible;
}


#pragma mark construction

- (NSButton*)checkbox:(NSString*)title tag:(NSInteger)tag x:(CGFloat)x y:(CGFloat)y
{
	NSButton* b = [[NSButton alloc] initWithFrame:NSMakeRect( x, y, 240, 18 )];

	b.buttonType = NSButtonTypeSwitch;
	b.title = title;
	b.tag = tag;
	b.target = self;
	b.action = @selector( controlChanged: );
	b.font = [NSFont systemFontOfSize:13];
	[b sizeToFit];
	[currentPane addSubview:b];
	controls[@( tag )] = b;
	return b;
}


- (NSButton*)radio:(NSString*)title tag:(NSInteger)tag x:(CGFloat)x y:(CGFloat)y group:(SEL)groupAction
{
	// AppKit groups radio buttons that share a superview and an action, so each group gets its own
	
	NSButton* b = [self checkbox:title tag:tag x:x y:y];
	b.buttonType = NSButtonTypeRadio;
	b.action = groupAction;
	[b sizeToFit];
	return b;
}


- (void)layoutRadioChanged:(id)sender
{
	[self controlChanged:sender];
}


- (void)bandsRadioChanged:(id)sender
{
	[self controlChanged:sender];
}


- (NSTextField*)label:(NSString*)text x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w size:(CGFloat)size
{
	NSTextField* t = [[NSTextField alloc] initWithFrame:NSMakeRect( x, y, w, size + 6 )];

	t.stringValue = text;
	t.editable = NO;
	t.selectable = NO;
	t.bordered = NO;
	t.drawsBackground = NO;
	t.font = [NSFont systemFontOfSize:size];
	[currentPane addSubview:t];
	return t;
}


- (NSBox*)groupBoxX:(CGFloat)x y:(CGFloat)y width:(CGFloat)w height:(CGFloat)h
{
	NSBox* box = [[NSBox alloc] initWithFrame:NSMakeRect( x, y, w, h )];

	box.boxType = NSBoxCustom;
	box.borderColor = [NSColor colorWithWhite:0.0 alpha:0.12];
	box.fillColor = [NSColor colorWithWhite:0.0 alpha:0.04];
	box.cornerRadius = 4;
	box.titlePosition = NSNoTitle;
	[currentPane addSubview:box];
	return box;
}


- (NSColorWell*)colourWellTag:(NSInteger)tag x:(CGFloat)x y:(CGFloat)y label:(NSString*)label
{
	NSColorWell* well = [[NSColorWell alloc] initWithFrame:NSMakeRect( x, y, 44, 22 )];

	well.tag = tag;
	well.target = self;
	well.action = @selector( colourChanged: );
	well.continuous = YES;
	[currentPane addSubview:well];
	controls[@( tag )] = well;

	[self label:label x:x + 52 y:y + 2 width:110 size:12];
	return well;
}


- (NSSlider*)sliderTag:(NSInteger)tag title:(NSString*)title y:(CGFloat)y min:(double)lo max:(double)hi width:(CGFloat)w
{
	[self label:title x:16 y:y width:120 size:12];

	NSSlider* s = [[NSSlider alloc] initWithFrame:NSMakeRect( 126, y - 2, w, 22 )];

	s.minValue = lo;
	s.maxValue = hi;
	s.tag = tag;
	s.target = self;
	s.action = @selector( controlChanged: );
	s.continuous = YES;
	[currentPane addSubview:s];
	controls[@( tag )] = s;

	NSTextField* value = [self label:@"" x:126 y:y + 20 width:w size:11];
	value.alignment = NSTextAlignmentCenter;
	valueLabels[@( tag )] = value;
	return s;
}


- (NSButton*)pushButton:(NSString*)title tag:(NSInteger)tag frame:(NSRect)frame
{
	NSButton* b = [[NSButton alloc] initWithFrame:frame];

	b.bezelStyle = NSBezelStyleRounded;
	b.controlSize = NSControlSizeSmall;
	b.font = [NSFont systemFontOfSize:11];
	b.title = title;
	b.tag = tag;
	b.target = self;
	b.action = @selector( controlChanged: );
	[currentPane addSubview:b];
	return b;
}


- (NSView*)paneForTab:(NSString*)title
{
	NSTabViewItem* item = [[NSTabViewItem alloc] initWithIdentifier:title];
	item.label = title;

	LEDSAFlippedView* pane = [[LEDSAFlippedView alloc] initWithFrame:NSMakeRect( 0, 0, 300, 440 )];
	item.view = pane;
	[tabs addTabViewItem:item];
	currentPane = pane;
	return pane;
}


- (void)buildLayoutTab
{
	[self paneForTab:@"Layout"];

	[self radio:@"Side By Side" tag:kTagLayoutSideBySide x:16 y:16 group:@selector( layoutRadioChanged: )];
	[self radio:@"Back To Back" tag:kTagLayoutBackToBack x:16 y:36 group:@selector( layoutRadioChanged: )];
	[self radio:@"Analogue VU Meters" tag:kTagLayoutAnalogue x:16 y:56 group:@selector( layoutRadioChanged: )];

	[self radio:@"10 Bands" tag:kTagBands10 x:196 y:16 group:@selector( bandsRadioChanged: )];
	[self radio:@"18 Bands" tag:kTagBands18 x:196 y:36 group:@selector( bandsRadioChanged: )];
	[self radio:@"24 Bands" tag:kTagBands24 x:196 y:56 group:@selector( bandsRadioChanged: )];
	[self radio:@"31 Bands" tag:kTagBands31 x:196 y:76 group:@selector( bandsRadioChanged: )];

	[self checkbox:@"VU Bargraphs" tag:kTagShowVU x:16 y:106];
	[self checkbox:@"Scale Labels" tag:kTagScales x:16 y:126];
	[self checkbox:@"Progress Bar" tag:kTagProgress x:16 y:146];

	NSButton* help = [[NSButton alloc] initWithFrame:NSMakeRect( 254, 140, 25, 25 )];
	help.bezelStyle = NSBezelStyleHelpButton;
	help.title = @"";
	help.tag = kTagHelp;
	help.target = self;
	help.action = @selector( controlChanged: );
	[currentPane addSubview:help];

	[self label:@"Track Information" x:16 y:178 width:200 size:11];
	[self groupBoxX:12 y:196 width:276 height:112];
	[self checkbox:@"Title" tag:kTagInfoTitle x:24 y:206];
	[self checkbox:@"Artist" tag:kTagInfoArtist x:24 y:226];
	[self checkbox:@"Album" tag:kTagInfoAlbum x:24 y:246];
	[self checkbox:@"Year" tag:kTagInfoYear x:24 y:266];
	[self checkbox:@"Station Ident" tag:kTagInfoStation x:24 y:286];
	[self checkbox:@"Stay Visible" tag:kTagStayVisible x:150 y:206];
	[self checkbox:@"Above Display" tag:kTagAbove x:150 y:226];
	[self checkbox:@"Size To Fit" tag:kTagSizeToFit x:150 y:246];

	NSTextField* note = [self label:@"← Uncheck all to hide\n  track information [i]" x:150 y:268 width:134 size:10];
	note.frame = NSMakeRect( 150, 268, 134, 30 );

	[self label:@"Cover Art" x:16 y:318 width:200 size:11];
	[self groupBoxX:12 y:336 width:276 height:74];
	[self checkbox:@"Show" tag:kTagCoverShow x:24 y:346];
	[self checkbox:@"Use as Background Image" tag:kTagCoverBackground x:40 y:366];
	[self checkbox:@"Use Artwork Colours" tag:kTagCoverColours x:40 y:386];
}


- (void)buildAppearanceTab
{
	[self paneForTab:@"Appearance"];

	[self label:@"Spectrum" x:16 y:10 width:100 size:11];
	[self groupBoxX:12 y:28 width:124 height:110];
	[self colourWellTag:kTagSpectrumPeak x:22 y:40 label:@"Peak"];
	[self colourWellTag:kTagSpectrumBar x:22 y:72 label:@"Bar"];
	[self colourWellTag:kTagSpectrumBlend x:22 y:104 label:@"Blend"];

	[self label:@"VU" x:160 y:10 width:100 size:11];
	[self groupBoxX:156 y:28 width:124 height:110];
	[self colourWellTag:kTagVUPeak x:166 y:40 label:@"Peak"];
	[self colourWellTag:kTagVUBar x:166 y:72 label:@"Bar"];
	[self colourWellTag:kTagVUBlend x:166 y:104 label:@"Blend"];

	[self colourWellTag:kTagBackground x:36 y:150 label:@"Background"];

	[self checkbox:@"Blend" tag:kTagBlend x:16 y:190];
	[self checkbox:@"Randomise on Track Change" tag:kTagRandomise x:16 y:210];
	[self checkbox:@"Blend to Current Value" tag:kTagBlendToValue x:16 y:230];
	[self checkbox:@"Animated Colours" tag:kTagAnimate x:16 y:250];

	[self checkbox:@"Peak Indicators" tag:kTagPeaks x:16 y:286];
	[self checkbox:@"Unlit Segments" tag:kTagUnlit x:16 y:306];
	[self checkbox:@"Reflections" tag:kTagReflections x:16 y:326];
	[self checkbox:@"Perspective" tag:kTagPerspective x:16 y:346];

	[self pushButton:@"Save Preset" tag:kTagSavePreset frame:NSMakeRect( 12, 392, 100, 24 )];
	[self pushButton:@"Clear Presets" tag:kTagClearPresets frame:NSMakeRect( 184, 392, 104, 24 )];
}


- (void)buildAdvancedTab
{
	[self paneForTab:@"Advanced"];

	[self checkbox:@"Logarithmic Response" tag:kTagLog x:16 y:14];
	[self checkbox:@"Bin Using Peak Values" tag:kTagBinPeak x:16 y:34];
	[self checkbox:@"Exponential Decay" tag:kTagExpDecay x:16 y:54];
	[self checkbox:@"Prevent Sleep" tag:kTagPreventSleep x:16 y:74];

	[self sliderTag:kTagPeakHold title:@"Peak Hold Time" y:110 min:kMinBarTime max:kMaxBarTime width:150];
	[self sliderTag:kTagPeakDecay title:@"Peak Decay Time" y:156 min:kMinBarTime max:kMaxBarTime width:150];
	[self sliderTag:kTagBarDecay title:@"Bar Decay Time" y:202 min:kMinBarTime max:kMaxBarTime width:150];
	[self sliderTag:kTagVUDecay title:@"VU Decay Time" y:248 min:kMinVUDecay max:kMaxVUDecay width:104];

	NSSlider* knob = [[NSSlider alloc] initWithFrame:NSMakeRect( 246, 238, 32, 32 )];
	knob.sliderType = NSSliderTypeCircular;
	knob.minValue = kMinGain;
	knob.maxValue = kMaxGain;
	knob.numberOfTickMarks = 8;
	knob.tag = kTagVUGain;
	knob.target = self;
	knob.action = @selector( controlChanged: );
	knob.continuous = YES;
	knob.toolTip = @"Analogue VU meter gain";
	[currentPane addSubview:knob];
	controls[@( kTagVUGain )] = knob;
	NSTextField* gainLabel = [self label:@"+ Gain –" x:236 y:272 width:52 size:10];
	gainLabel.alignment = NSTextAlignmentCenter;

	// additions in the 64-bit version, for matching Apple Music to iTunes

	NSSlider* sg = [self sliderTag:kTagSpectrumGain title:@"Spectrum Gain" y:300 min:log2( kMinSpectrumGain ) max:log2( kMaxSpectrumGain ) width:150];
	sg.toolTip = @"Scales the spectrum data supplied by iTunes / Music before it is displayed";
	[self checkbox:@"Show Diagnostics [=]" tag:kTagDiagnostics x:16 y:350];

	NSTextField* version = [self label:@"LED Spectrum Analyser version 3.1 (64-bit: Apple Silicon & Intel)\n©2014 Graham Cox; 64-bit port 2026"
									 x:16 y:390 width:276 size:10];
	version.frame = NSMakeRect( 16, 390, 276, 30 );
}


- (void)buildWindow
{
	NSRect frame = NSMakeRect( 0, 0, 324, 486 );

	window = [[NSWindow alloc] initWithContentRect:frame
										 styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
										   backing:NSBackingStoreBuffered
											 defer:YES];
	window.title = @"LED Spectrum Analyser Options";
	window.releasedWhenClosed = NO;
	window.delegate = self;
	window.hidesOnDeactivate = NO;
	[window setFrameAutosaveName:@"LEDSpectrumAnalyserOptions"];

	tabs = [[NSTabView alloc] initWithFrame:NSMakeRect( 10, 10, 304, 470 )];
	[window.contentView addSubview:tabs];

	[self buildLayoutTab];
	[self buildAppearanceTab];
	[self buildAdvancedTab];

	if ( ! [window setFrameUsingName:@"LEDSpectrumAnalyserOptions"] )
		[window center];

	[NSColorPanel sharedColorPanel].showsAlpha = YES;
}


#pragma mark state

- (void)setState:(BOOL)on tag:(NSInteger)tag
{
	NSButton* b = (NSButton*) controls[@( tag )];
	b.state = on? NSControlStateValueOn : NSControlStateValueOff;
}


- (void)setEnabled:(BOOL)enabled tag:(NSInteger)tag
{
	controls[@( tag )].enabled = enabled;
}


- (void)setColour:(const Colour&)c tag:(NSInteger)tag
{
	NSColorWell* well = (NSColorWell*) controls[@( tag )];
	well.color = [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a];
}


- (void)setSlider:(double)value tag:(NSInteger)tag
{
	NSSlider* s = (NSSlider*) controls[@( tag )];
	s.doubleValue = value;
	[self updateValueLabelForTag:tag];
}


- (void)updateValueLabelForTag:(NSInteger)tag
{
	NSTextField* label = valueLabels[@( tag )];
	NSSlider* s = (NSSlider*) controls[@( tag )];

	if ( label == nil || s == nil )
		return;

	if ( tag == kTagSpectrumGain )
		label.stringValue = [NSString stringWithFormat:@"×%.2f", pow( 2.0, s.doubleValue )];
	else
		label.stringValue = [NSString stringWithFormat:@"%.0f mS", s.doubleValue * 1000.0];
}


- (void)refresh
{
	Engine* engine = [self.delegate optionsEngine];

	if ( window == nil || engine == NULL )
		return;

	const Settings& s = engine->GetSettings();

	[self setState:s.layout == kLayoutSideBySide tag:kTagLayoutSideBySide];
	[self setState:s.layout == kLayoutBackToBack tag:kTagLayoutBackToBack];
	[self setState:s.layout == kLayoutAnalogueVU tag:kTagLayoutAnalogue];
	[self setState:s.numberOfSpectrumBars == 10 tag:kTagBands10];
	[self setState:s.numberOfSpectrumBars == 18 tag:kTagBands18];
	[self setState:s.numberOfSpectrumBars == 24 tag:kTagBands24];
	[self setState:s.numberOfSpectrumBars == 31 tag:kTagBands31];
	[self setState:s.showVU tag:kTagShowVU];
	[self setState:s.scalesVisible tag:kTagScales];
	[self setState:s.showProgress tag:kTagProgress];
	[self setState:( s.trackInfoMask & kInfoTitle ) != 0 tag:kTagInfoTitle];
	[self setState:( s.trackInfoMask & kInfoArtist ) != 0 tag:kTagInfoArtist];
	[self setState:( s.trackInfoMask & kInfoAlbum ) != 0 tag:kTagInfoAlbum];
	[self setState:( s.trackInfoMask & kInfoYear ) != 0 tag:kTagInfoYear];
	[self setState:( s.trackInfoMask & kInfoStationIdent ) != 0 tag:kTagInfoStation];
	[self setState:s.keepTextVisible tag:kTagStayVisible];
	[self setState:s.textAbove tag:kTagAbove];
	[self setState:s.sizeTextToFit tag:kTagSizeToFit];
	[self setState:s.coverArt tag:kTagCoverShow];
	[self setState:s.coverArtBackgroundEffect tag:kTagCoverBackground];
	[self setState:s.coverArtColours tag:kTagCoverColours];
	[self setEnabled:s.coverArt tag:kTagCoverBackground];
	[self setEnabled:s.coverArt tag:kTagCoverColours];

	BOOL bands = ( s.layout != kLayoutAnalogueVU );
	for ( NSInteger t = kTagBands10; t <= kTagBands31; t++ )
		[self setEnabled:bands tag:t];
	[self setEnabled:bands tag:kTagScales];

	[self setColour:s.spectrumPeak tag:kTagSpectrumPeak];
	[self setColour:s.spectrumBar tag:kTagSpectrumBar];
	[self setColour:s.spectrumBlend tag:kTagSpectrumBlend];
	[self setColour:s.vuPeak tag:kTagVUPeak];
	[self setColour:s.vuBar tag:kTagVUBar];
	[self setColour:s.vuBlend tag:kTagVUBlend];
	[self setColour:s.background tag:kTagBackground];
	[self setEnabled:s.blendEnabled tag:kTagSpectrumBlend];
	[self setEnabled:s.blendEnabled tag:kTagVUBlend];

	[self setState:s.blendEnabled tag:kTagBlend];
	[self setState:s.randomiseColours tag:kTagRandomise];
	[self setState:s.blendToValue tag:kTagBlendToValue];
	[self setState:s.animateColours tag:kTagAnimate];
	[self setEnabled:s.blendEnabled tag:kTagBlendToValue];
	[self setState:s.peakIndicatorsEnabled tag:kTagPeaks];
	[self setState:s.unlitSegments tag:kTagUnlit];
	[self setState:s.reflections tag:kTagReflections];
	[self setState:s.perspective tag:kTagPerspective];

	[self setState:s.logResponse tag:kTagLog];
	[self setState:s.binUsingPeak tag:kTagBinPeak];
	[self setState:s.expDecay tag:kTagExpDecay];
	[self setState:s.preventSleep tag:kTagPreventSleep];
	[self setSlider:s.peakHoldTime tag:kTagPeakHold];
	[self setSlider:s.peakDecayTime tag:kTagPeakDecay];
	[self setSlider:s.barDecayTime tag:kTagBarDecay];
	[self setSlider:s.vuDecayTime tag:kTagVUDecay];
	[self setSlider:s.vuMeterGain tag:kTagVUGain];
	[self setSlider:log2( s.spectrumGain ) tag:kTagSpectrumGain];
	[self setState:engine->DiagnosticsVisible() tag:kTagDiagnostics];
}


#pragma mark actions

- (BOOL)isOn:(id)sender
{
	return [sender isKindOfClass:[NSButton class]] && [(NSButton*) sender state] == NSControlStateValueOn;
}


- (void)controlChanged:(id)sender
{
	Engine* engine = [self.delegate optionsEngine];

	if ( engine == NULL )
		return;

	Settings& s = engine->GetSettings();
	double now = [self.delegate optionsCurrentTime];
	NSInteger tag = [sender tag];
	BOOL on = [self isOn:sender];
	double v = [sender respondsToSelector:@selector( doubleValue )]? [sender doubleValue] : 0;

	switch ( tag )
	{
		case kTagLayoutSideBySide:	s.layout = kLayoutSideBySide; break;
		case kTagLayoutBackToBack:	s.layout = kLayoutBackToBack; break;
		case kTagLayoutAnalogue:	s.layout = kLayoutAnalogueVU; break;
		case kTagBands10:			s.numberOfSpectrumBars = 10; break;
		case kTagBands18:			s.numberOfSpectrumBars = 18; break;
		case kTagBands24:			s.numberOfSpectrumBars = 24; break;
		case kTagBands31:			s.numberOfSpectrumBars = 31; break;
		case kTagShowVU:			s.showVU = on; break;
		case kTagScales:			s.scalesVisible = on; break;
		case kTagProgress:			s.showProgress = on; break;
		case kTagHelp:				[self.delegate optionsShowManual]; return;

		case kTagInfoTitle:			s.trackInfoMask = on? ( s.trackInfoMask | kInfoTitle ) : ( s.trackInfoMask & ~kInfoTitle ); break;
		case kTagInfoArtist:		s.trackInfoMask = on? ( s.trackInfoMask | kInfoArtist ) : ( s.trackInfoMask & ~kInfoArtist ); break;
		case kTagInfoAlbum:			s.trackInfoMask = on? ( s.trackInfoMask | kInfoAlbum ) : ( s.trackInfoMask & ~kInfoAlbum ); break;
		case kTagInfoYear:			s.trackInfoMask = on? ( s.trackInfoMask | kInfoYear ) : ( s.trackInfoMask & ~kInfoYear ); break;
		case kTagInfoStation:		s.trackInfoMask = on? ( s.trackInfoMask | kInfoStationIdent ) : ( s.trackInfoMask & ~kInfoStationIdent ); break;
		case kTagStayVisible:		s.keepTextVisible = on; break;
		case kTagAbove:				s.textAbove = on; break;
		case kTagSizeToFit:			s.sizeTextToFit = on; break;
		case kTagCoverShow:			s.coverArt = on; break;
		case kTagCoverBackground:	s.coverArtBackgroundEffect = on; break;
		case kTagCoverColours:		s.coverArtColours = on; break;

		case kTagBlend:				s.blendEnabled = on; break;
		case kTagRandomise:			s.randomiseColours = on; break;
		case kTagBlendToValue:		s.blendToValue = on; break;
		case kTagAnimate:			s.animateColours = on; break;
		case kTagPeaks:				s.peakIndicatorsEnabled = on; break;
		case kTagUnlit:				s.unlitSegments = on; break;
		case kTagReflections:		s.reflections = on; break;
		case kTagPerspective:		s.perspective = on; break;
		case kTagSavePreset:		engine->SavePreset( now ); return;
		case kTagClearPresets:		engine->ClearPresets( now ); return;

		case kTagLog:				s.logResponse = on; break;
		case kTagBinPeak:			s.binUsingPeak = on; break;
		case kTagExpDecay:			s.expDecay = on; break;
		case kTagPreventSleep:		s.preventSleep = on; break;
		case kTagPeakHold:			s.peakHoldTime = v; break;
		case kTagPeakDecay:			s.peakDecayTime = v; break;
		case kTagBarDecay:			s.barDecayTime = v; break;
		case kTagVUDecay:			s.vuDecayTime = v; break;
		case kTagVUGain:			s.vuMeterGain = v; break;
		case kTagSpectrumGain:		s.spectrumGain = pow( 2.0, v ); break;
		case kTagDiagnostics:		engine->SetDiagnosticsVisible( on ); return;
		default:					return;
	}

	[self updateValueLabelForTag:tag];
	engine->SettingsEdited( now );		// calls back to refresh the window
}


- (void)colourChanged:(NSColorWell*)sender
{
	Engine* engine = [self.delegate optionsEngine];

	if ( engine == NULL )
		return;

	Settings& s = engine->GetSettings();
	Colour c = LEDColourFromNSColor( sender.color );

	switch ( sender.tag )
	{
		case kTagSpectrumPeak:	s.spectrumPeak = c; break;
		case kTagSpectrumBar:	s.spectrumBar = c; break;
		case kTagSpectrumBlend:	s.spectrumBlend = c; break;
		case kTagVUPeak:		s.vuPeak = c; break;
		case kTagVUBar:			s.vuBar = c; break;
		case kTagVUBlend:		s.vuBlend = c; break;
		case kTagBackground:	s.background = c; break;
		default:				return;
	}

	engine->SettingsEdited( [self.delegate optionsCurrentTime] );
}


#pragma mark window

- (void)showWindow
{
	if ( window == nil )
		[self buildWindow];

	[self refresh];
	[window makeKeyAndOrderFront:nil];
}


- (void)selectTab:(NSInteger)index
{
	if ( window && index >= 0 && index < tabs.numberOfTabViewItems )
		[tabs selectTabViewItemAtIndex:index];
}


- (void)close
{
	[[NSColorPanel sharedColorPanel] orderOut:nil];
	[window orderOut:nil];
}


- (void)windowWillClose:(NSNotification*)notification
{
	// stop the colour wells talking to the shared colour panel

	for ( NSControl* c in controls.allValues )
		if ( [c isKindOfClass:[NSColorWell class]] )
			[(NSColorWell*) c deactivate];
}

@end
