/*
 *  LEDSARenderer.mm
 *  LED Spectrum Analyser
 *
 *  Layer tree (back to front):
 *
 *      root (background colour)
 *        cover art
 *        reflector (CAReplicatorLayer - draws its contents a second time, mirrored, when reflections are on)
 *          display group (perspective)
 *            left / right panels (tilted when perspective is on)
 *              bargraphs, frequency labels
 *            centre scale labels, VU bargraphs, "L VU R", analogue meters
 *        reflection fade
 *        progress bar, times
 *        track info
 *        keyboard feedback, diagnostics
 *
 *  Each bargraph is: a dark "unlit" gradient, a lit gradient (resized to the current value), a
 *  segment grid image that paints the gaps between LEDs, and a peak marker.
 *
 */

#import "LEDSARenderer.h"
#import "LEDSAArtwork.h"
#include "LEDEngine.h"

using namespace led;


static const CGFloat	kUnlitBrightness		= 0.18;
static const CGFloat	kPerspectiveAngle		= 20.0 * M_PI / 180.0;
static const CGFloat	kPerspectiveDistance	= 1.2;		// eye distance, in view widths
static const float		kReflectionAlpha		= 0.22f;


static CGColorRef	CreateColour( const Colour& c, float alphaScale = 1.0f ) CF_RETURNS_RETAINED;
static CGColorRef	CreateColour( const Colour& c, float alphaScale )
{
	return LEDCreateSRGBColour( c.r, c.g, c.b, c.a * alphaScale );
}


static NSString*	ToNSString( const std::string& s )
{
	NSString* str = [[NSString alloc] initWithBytes:s.data() length:s.size() encoding:NSUTF8StringEncoding];
	return str? str : @"";
}


static NSArray*		GradientColours( const Colour& a, const Colour& b )
{
	CGColorRef ca = CreateColour( a );
	CGColorRef cb = CreateColour( b );
	NSArray* colours = @[ (__bridge id) ca, (__bridge id) cb ];
	CGColorRelease( ca );
	CGColorRelease( cb );
	return colours;
}


static NSFont*		BoldFont( CGFloat size )
{
	NSFont* f = [NSFont fontWithName:@"Helvetica-Bold" size:size];
	return f? f : [NSFont boldSystemFontOfSize:size];
}


#pragma mark - bargraph

@interface LEDBargraph : NSObject
{
@public
	CALayer*			container;
	CAGradientLayer*	unlit;
	CAGradientLayer*	lit;
	CALayer*			grid;
	CALayer*			peak;

	BOOL				vertical;
	BOOL				fromRight;		// horizontal bar growing leftwards (segment 0 at the right)
	int					segments;
	CGFloat				pitch;			// points per segment
	CGFloat				gap;			// points
	CGFloat				length;			// segments * pitch
	int					peakSegments;

	int					shownLit;
	int					shownPeak;
	BOOL				shownUnlit;
	BOOL				shownBlendToValue;
}
@end

@implementation LEDBargraph

- (instancetype)initWithFrame:(CGRect)frame vertical:(BOOL)isVertical fromRight:(BOOL)right
					segments:(int)nSegments pitchPx:(int)pitchPx gapPx:(int)gapPx scale:(CGFloat)scale
				peakSegments:(int)nPeak
{
	self = [super init];

	if ( self )
	{
		vertical = isVertical;
		fromRight = right;
		segments = nSegments;
		pitch = pitchPx / scale;
		gap = gapPx / scale;
		length = segments * pitch;
		peakSegments = nPeak;
		shownLit = shownPeak = -2;
		shownUnlit = shownBlendToValue = NO;

		container = [CALayer layer];
		container.frame = frame;

		unlit = [CAGradientLayer layer];
		lit = [CAGradientLayer layer];
		grid = [CALayer layer];
		peak = [CALayer layer];

		grid.masksToBounds = YES;
		grid.contentsScale = scale;
		grid.contentsGravity = vertical? kCAGravityBottom : ( fromRight? kCAGravityRight : kCAGravityLeft );

		[container addSublayer:unlit];
		[container addSublayer:lit];
		[container addSublayer:grid];
		[container addSublayer:peak];

		unlit.frame = [self rectForSegments:segments];
		[self setGradientDirection:unlit fraction:1.0];
	}
	return self;
}


- (CGRect)rectForSegments:(int)n
{
	CGRect b = container.bounds;
	CGFloat len = n * pitch;

	if ( vertical )
		return CGRectMake( 0, 0, b.size.width, len );
	if ( fromRight )
		return CGRectMake( b.size.width - len, 0, len, b.size.height );
	return CGRectMake( 0, 0, len, b.size.height );
}


- (CGRect)rectForSegmentsFrom:(int)first count:(int)n
{
	CGRect b = container.bounds;
	CGFloat start = first * pitch;
	CGFloat len = n * pitch - gap;

	if ( vertical )
		return CGRectMake( 0, start, b.size.width, len );
	if ( fromRight )
		return CGRectMake( b.size.width - start - len, 0, len, b.size.height );
	return CGRectMake( start, 0, len, b.size.height );
}


- (void)setGradientDirection:(CAGradientLayer*)g fraction:(CGFloat)fraction
{
	// the gradient runs from the bar colour at segment 0 to the blend colour at full scale. When
	// only part of the bar is lit, the end point is pushed beyond the layer so the top segment
	// shows the colour for its position (unless blending to the current value)

	CGFloat reach = 1.0 / MAX( 1e-3, fraction );

	if ( vertical )
	{
		g.startPoint = CGPointMake( 0.5, 0 );
		g.endPoint = CGPointMake( 0.5, reach );
	}
	else if ( fromRight )
	{
		g.startPoint = CGPointMake( 1, 0.5 );
		g.endPoint = CGPointMake( 1 - reach, 0.5 );
	}
	else
	{
		g.startPoint = CGPointMake( 0, 0.5 );
		g.endPoint = CGPointMake( reach, 0.5 );
	}
}


- (void)setBar:(const Colour&)bar blend:(const Colour&)blend peak:(const Colour&)peakColour blendEnabled:(BOOL)blendEnabled
		 grid:(CGImageRef)gridImage
{
	Colour top = blendEnabled? blend : bar;

	lit.colors = GradientColours( bar, top );
	unlit.colors = GradientColours( bar.scaled( kUnlitBrightness ), top.scaled( kUnlitBrightness ));

	CGColorRef pc = CreateColour( peakColour );
	peak.backgroundColor = pc;
	CGColorRelease( pc );

	grid.contents = (__bridge id) gridImage;
}


- (void)setValue:(double)value peak:(double)peakValue showPeak:(BOOL)showPeak showUnlit:(BOOL)showUnlit
	blendToValue:(BOOL)blendToValue
{
	int n = (int) floor( clamp( value, 0.0, 1.0 ) * segments + 1e-9 );
	int pk = showPeak? (int) floor( clamp( peakValue, 0.0, 1.0 ) * segments + 1e-9 ) - 1 : -1;

	if ( n != shownLit || blendToValue != shownBlendToValue )
	{
		lit.hidden = ( n == 0 );
		lit.frame = [self rectForSegments:n];
		[self setGradientDirection:lit fraction:( blendToValue? 1.0 : (CGFloat) n / segments )];
		shownLit = n;
		shownBlendToValue = blendToValue;

		if ( ! showUnlit )
			grid.frame = [self rectForSegments:n];
	}

	if ( showUnlit != shownUnlit )
	{
		unlit.hidden = ! showUnlit;
		grid.frame = [self rectForSegments:( showUnlit? segments : n )];
		shownUnlit = showUnlit;
	}

	if ( pk != shownPeak )
	{
		if ( pk < 0 )
			peak.hidden = YES;
		else
		{
			int count = MIN( peakSegments, pk + 1 );
			peak.hidden = NO;
			peak.frame = [self rectForSegmentsFrom:( pk + 1 - count ) count:count];
		}
		shownPeak = pk;
	}
}

@end


#pragma mark - analogue meter

@interface LEDAnalogueMeter : NSObject
{
@public
	CALayer*	container;
	CALayer*	face;
	CALayer*	needle;
	CALayer*	hub;
	CALayer*	led;
	LEDMeterGeometry geometry;
	BOOL		ledLit;
	double		shownPosition;
}
@end

@implementation LEDAnalogueMeter
@end


#pragma mark - renderer

@interface LEDSARenderer ()
{
	Engine*				engine;
	CALayer*			root;
	CGSize				size;
	CGFloat				scale;
	uint32_t			builtLayoutSerial;
	uint32_t			appliedPaletteSerial;
	Layout				layout;
	BOOL				needsBuild;

	CALayer*			coverLayer;
	CAReplicatorLayer*	reflector;
	CALayer*			displayGroup;
	CALayer*			leftPanel;
	CALayer*			rightPanel;
	CAGradientLayer*	reflectionFade;
	CALayer*			progressDots;
	CAGradientLayer*	progressFill;
	CATextLayer*		elapsedLayer;
	CATextLayer*		totalLayer;
	CATextLayer*		textLayer;
	CATextLayer*		feedbackLayer;
	CATextLayer*		diagnosticsLayer;

	NSMutableArray<LEDBargraph*>*		spectrumBars[2];
	LEDBargraph*		vuBars[2];
	LEDAnalogueMeter*	meters[2];
	NSMutableArray<CATextLayer*>*		labelLayers;

	CGImageRef			spectrumGrid[2];
	CGImageRef			vuGrid[2];
	CGImageRef			ledLit;
	CGImageRef			ledUnlit;
	CGImageRef			artwork;

	BOOL				coverOnTop;
	std::string			shownText, shownElapsed, shownTotal, shownFeedback;
	CGFloat				shownTextFontSize;
}
@end


@implementation LEDSARenderer

- (instancetype)initWithRootLayer:(CALayer*)rootLayer engine:(Engine*)theEngine
{
	self = [super init];

	if ( self )
	{
		root = rootLayer;
		engine = theEngine;
		scale = 1.0;
		needsBuild = YES;
		labelLayers = [NSMutableArray array];
		spectrumBars[0] = [NSMutableArray array];
		spectrumBars[1] = [NSMutableArray array];

		root.masksToBounds = YES;
	}
	return self;
}


- (void)dealloc
{
	[self releaseImages];

	if ( artwork )
		CGImageRelease( artwork );
}


- (void)releaseImages
{
	for ( int c = 0; c < 2; c++ )
	{
		if ( spectrumGrid[c] ) CGImageRelease( spectrumGrid[c] );
		if ( vuGrid[c] ) CGImageRelease( vuGrid[c] );
		spectrumGrid[c] = vuGrid[c] = NULL;
	}
	if ( ledLit ) CGImageRelease( ledLit );
	if ( ledUnlit ) CGImageRelease( ledUnlit );
	ledLit = ledUnlit = NULL;
}


- (void)setViewSize:(CGSize)newSize scale:(CGFloat)newScale
{
	newScale = MAX( 1.0, newScale );

	if ( ! CGSizeEqualToSize( newSize, size ) || newScale != scale )
	{
		size = newSize;
		scale = newScale;
		needsBuild = YES;
	}
}


- (void)setArtwork:(CGImageRef)image
{
	if ( artwork )
		CGImageRelease( artwork );

	artwork = image? CGImageRetain( image ) : NULL;
	coverLayer.contents = (__bridge id) artwork;
}


#pragma mark building

- (CATextLayer*)textLayerWithFontSize:(CGFloat)fontSize
{
	CATextLayer* t = [CATextLayer layer];

	t.font = (__bridge CFTypeRef) BoldFont( fontSize );
	t.fontSize = fontSize;
	t.contentsScale = scale;
	t.foregroundColor = CGColorGetConstantColor( kCGColorWhite );
	t.alignmentMode = kCAAlignmentCenter;
	t.truncationMode = kCATruncationEnd;
	return t;
}


- (CATextLayer*)labelLayer:(const Label&)label fontSize:(CGFloat)fontSize origin:(CGPoint)origin
{
	CATextLayer* t = [self textLayerWithFontSize:fontSize];
	CGFloat lineH = ceil( fontSize * 1.25 );

	t.string = ToNSString( label.text );
	t.alignmentMode = ( label.align == kLabelAlignLeft )? kCAAlignmentLeft : ( label.align == kLabelAlignRight )? kCAAlignmentRight : kCAAlignmentCenter;
	t.frame = CGRectMake( label.frame.x - origin.x, label.frame.y - origin.y + ( label.frame.h - lineH ) / 2, label.frame.w, lineH );
	[labelLayers addObject:t];
	return t;
}


- (void)addGlow:(CALayer*)l radius:(CGFloat)radius
{
	CGColorRef glow = LEDCreateSRGBColour( 0.45, 0.72, 1.0, 1.0 );
	l.shadowColor = glow;
	CGColorRelease( glow );
	l.shadowOpacity = 0.95f;
	l.shadowRadius = radius;
	l.shadowOffset = CGSizeZero;
}


- (int)pitchPxForPitch:(CGFloat)pitch
{
	return MAX( 2, (int) lround( pitch * scale ));
}


- (int)gapPxForGap:(CGFloat)gapPoints pitchPx:(int)pitchPx
{
	return MAX( 1, MIN( pitchPx - 1, (int) lround( gapPoints * scale )));
}


- (LEDBargraph*)bargraphWithFrame:(CGRect)frame vertical:(BOOL)vertical fromRight:(BOOL)fromRight
						 segments:(int)nSegments pitch:(CGFloat)pitch gap:(CGFloat)gapPoints peakSegments:(int)nPeak
{
	int pitchPx = [self pitchPxForPitch:pitch];
	int gapPx = [self gapPxForGap:gapPoints pitchPx:pitchPx];
	CGFloat lengthAvailable = vertical? frame.size.height : frame.size.width;

	// snap the segment pitch to whole pixels so every LED edge is crisp

	int n = MIN( nSegments, (int) floor( lengthAvailable * scale / pitchPx ));
	n = MAX( 1, n );

	return [[LEDBargraph alloc] initWithFrame:frame vertical:vertical fromRight:fromRight segments:n
									  pitchPx:pitchPx gapPx:gapPx scale:scale peakSegments:nPeak];
}


- (void)build
{
	const Settings& s = engine->GetSettings();

	[root.sublayers makeObjectsPerformSelector:@selector( removeFromSuperlayer )];
	[labelLayers removeAllObjects];
	[spectrumBars[0] removeAllObjects];
	[spectrumBars[1] removeAllObjects];
	vuBars[0] = vuBars[1] = nil;
	meters[0] = meters[1] = nil;
	[self releaseImages];
	shownText = shownElapsed = shownTotal = shownFeedback = "";
	shownTextFontSize = 0;

	layout = ComputeLayout( size.width, size.height, s );

	const led::Rect& da = layout.displayArea;
	const double D = da.h;

	// cover art, behind everything

	coverLayer = [CALayer layer];
	coverLayer.contents = (__bridge id) artwork;
	coverLayer.contentsGravity = kCAGravityResizeAspect;
	coverLayer.opacity = 0;
	coverLayer.shadowRadius = 14;
	coverLayer.shadowOffset = CGSizeMake( 0, -4 );
	[root addSublayer:coverLayer];
	coverOnTop = NO;

	// the display, inside a replicator whose centre line is the reflection axis

	reflector = [CAReplicatorLayer layer];
	reflector.frame = CGRectMake( 0, layout.reflectionAxisY - D, size.width, 2 * D );
	reflector.instanceTransform = CATransform3DMakeScale( 1, -1, 1 );
	reflector.instanceCount = s.reflections? 2 : 1;
	reflector.instanceAlphaOffset = -( 1.0f - kReflectionAlpha );
	[root addSublayer:reflector];

	displayGroup = [CALayer layer];
	displayGroup.frame = CGRectMake( da.x, D, da.w, D );

	if ( s.perspective )
	{
		CATransform3D p = CATransform3DIdentity;
		p.m34 = -1.0 / ( kPerspectiveDistance * size.width );
		displayGroup.sublayerTransform = p;
	}
	[reflector addSublayer:displayGroup];

	CGPoint origin = CGPointMake( da.x, da.y );		// view -> display group coordinates

	// spectrum panels

	if ( layout.showSpectrum )
	{
		led::Rect panels[2] = { layout.leftPanel, layout.rightPanel };

		for ( int c = 0; c < 2; c++ )
		{
			CALayer* panel = [CALayer layer];
			const led::Rect& r = panels[c];

			panel.bounds = CGRectMake( 0, 0, r.w, r.h );
			panel.anchorPoint = CGPointMake( c == 0? 0 : 1, 0.5 );
			panel.position = CGPointMake(( c == 0? r.x : r.maxX()) - origin.x, r.midY() - origin.y );

			if ( s.perspective )
				panel.transform = CATransform3DMakeRotation( c == 0? kPerspectiveAngle : -kPerspectiveAngle, 0, 1, 0 );

			[displayGroup addSublayer:panel];

			if ( c == 0 ) leftPanel = panel; else rightPanel = panel;

			const std::vector<led::Rect>& bars = ( c == 0 )? layout.leftBars : layout.rightBars;
			BOOL fromRight = ! layout.barsVertical && ( c == 0 );

			for ( size_t b = 0; b < bars.size(); b++ )
			{
				const led::Rect& br = bars[b];
				LEDBargraph* bar = [self bargraphWithFrame:CGRectMake( br.x, br.y, br.w, br.h ) vertical:layout.barsVertical fromRight:fromRight
												  segments:layout.segments pitch:layout.segmentPitch gap:layout.segmentGap
											  peakSegments:layout.peakSegments];
				[panel addSublayer:bar->container];
				[spectrumBars[c] addObject:bar];
			}

			const std::vector<Label>& labels = ( c == 0 )? layout.leftLabels : layout.rightLabels;

			for ( size_t i = 0; i < labels.size(); i++ )
				[panel addSublayer:[self labelLayer:labels[i] fontSize:layout.scaleFontSize origin:CGPointZero]];
		}

		for ( size_t i = 0; i < layout.centreLabels.size(); i++ )
			[displayGroup addSublayer:[self labelLayer:layout.centreLabels[i] fontSize:layout.scaleFontSize origin:origin]];
	}

	// analogue meters

	if ( layout.analogue )
	{
		led::Rect mr[2] = { layout.leftMeter, layout.rightMeter };
		CGSize ms = CGSizeMake( mr[0].w, mr[0].h );
		CGImageRef faceImage = LEDCreateMeterFaceImage( ms, scale );
		CGImageRef hubImage = LEDCreateMeterHubImage( ms, scale );
		CGRect ledFrame = LEDPeakLEDFrameInMeter( ms );

		ledLit = LEDCreatePeakLEDImage( ledFrame.size, scale, YES );
		ledUnlit = LEDCreatePeakLEDImage( ledFrame.size, scale, NO );

		for ( int c = 0; c < 2; c++ )
		{
			LEDAnalogueMeter* m = [[LEDAnalogueMeter alloc] init];

			m->geometry = LEDMeterGeometryForSize( ms );
			m->container = [CALayer layer];
			m->container.frame = CGRectMake( mr[c].x - origin.x, mr[c].y - origin.y, ms.width, ms.height );
			m->container.masksToBounds = YES;

			m->face = [CALayer layer];
			m->face.frame = CGRectMake( 0, 0, ms.width, ms.height );
			m->face.contents = (__bridge id) faceImage;
			m->face.contentsScale = scale;

			CGColorRef red = LEDCreateSRGBColour( 0.86, 0.10, 0.05, 1.0 );
			m->needle = [CALayer layer];
			m->needle.bounds = CGRectMake( 0, 0, MAX( 1.2, 0.012 * ms.height ), m->geometry.needleLength );
			m->needle.anchorPoint = CGPointMake( 0.5, 0 );
			m->needle.position = m->geometry.pivot;
			m->needle.backgroundColor = red;
			m->needle.shadowOpacity = 0.45f;
			m->needle.shadowOffset = CGSizeMake( 1.5, -1.5 );
			m->needle.shadowRadius = 1.2;
			m->needle.transform = CATransform3DMakeRotation( LEDMeterNeedleAngle( m->geometry, 0 ), 0, 0, 1 );
			CGColorRelease( red );

			m->hub = [CALayer layer];
			m->hub.frame = m->face.frame;
			m->hub.contents = (__bridge id) hubImage;
			m->hub.contentsScale = scale;

			m->led = [CALayer layer];
			m->led.frame = ledFrame;
			m->led.contents = (__bridge id) ledUnlit;
			m->led.contentsScale = scale;
			m->ledLit = NO;
			m->shownPosition = -1;

			[m->container addSublayer:m->face];
			[m->container addSublayer:m->needle];
			[m->container addSublayer:m->hub];
			[m->container addSublayer:m->led];
			[displayGroup addSublayer:m->container];
			meters[c] = m;
		}

		CGImageRelease( faceImage );
		CGImageRelease( hubImage );
	}

	// VU bargraphs

	if ( layout.showVU )
	{
		led::Rect vr[2] = { layout.leftVU, layout.rightVU };

		for ( int c = 0; c < 2; c++ )
		{
			LEDBargraph* bar = [self bargraphWithFrame:CGRectMake( vr[c].x - origin.x, vr[c].y - origin.y, vr[c].w, vr[c].h )
											  vertical:NO fromRight:( c == 0 ) segments:layout.vuSegments
												 pitch:layout.vuPitch gap:layout.vuGap peakSegments:1];
			[displayGroup addSublayer:bar->container];
			vuBars[c] = bar;
		}

		[displayGroup addSublayer:[self labelLayer:layout.vuLabel fontSize:layout.scaleFontSize origin:origin]];
	}

	// fade the reflection out towards the bottom

	reflectionFade = [CAGradientLayer layer];
	reflectionFade.frame = CGRectMake( 0, layout.reflectionAxisY - D, size.width, D );
	reflectionFade.startPoint = CGPointMake( 0.5, 0 );
	reflectionFade.endPoint = CGPointMake( 0.5, 1 );
	reflectionFade.hidden = ! s.reflections;
	[root addSublayer:reflectionFade];

	// progress bar

	const led::Rect& pt = layout.progressTrack;

	progressDots = [CALayer layer];
	progressDots.frame = CGRectMake( pt.x, pt.y, pt.w, pt.h );
	progressDots.contentsScale = scale;
	[root addSublayer:progressDots];

	progressFill = [CAGradientLayer layer];
	progressFill.frame = CGRectMake( pt.x, pt.y, pt.h, pt.h );
	progressFill.cornerRadius = pt.h / 2;
	progressFill.startPoint = CGPointMake( 0.5, 1 );
	progressFill.endPoint = CGPointMake( 0.5, 0 );
	progressFill.shadowOpacity = 0.9f;
	progressFill.shadowRadius = pt.h * 0.6;
	progressFill.shadowOffset = CGSizeZero;
	[root addSublayer:progressFill];

	elapsedLayer = [self labelLayer:layout.elapsedLabel fontSize:layout.timeFontSize origin:CGPointZero];
	totalLayer = [self labelLayer:layout.totalLabel fontSize:layout.timeFontSize origin:CGPointZero];
	[self addGlow:elapsedLayer radius:layout.timeFontSize * 0.2];
	[self addGlow:totalLayer radius:layout.timeFontSize * 0.2];
	[root addSublayer:elapsedLayer];
	[root addSublayer:totalLayer];

	BOOL showProgress = layout.showProgress;
	progressDots.hidden = progressFill.hidden = elapsedLayer.hidden = totalLayer.hidden = ! showProgress;

	// track info

	textLayer = [self textLayerWithFontSize:layout.textFontSize];
	textLayer.frame = CGRectMake( layout.textArea.x, layout.textArea.y, layout.textArea.w, layout.textArea.h );
	[self addGlow:textLayer radius:layout.textFontSize * 0.22];
	textLayer.opacity = 0;
	textLayer.zPosition = 10;
	[root addSublayer:textLayer];

	// transient text

	feedbackLayer = [self textLayerWithFontSize:12];
	feedbackLayer.alignmentMode = kCAAlignmentLeft;
	feedbackLayer.frame = CGRectMake( layout.feedbackArea.x, layout.feedbackArea.y, layout.feedbackArea.w, layout.feedbackArea.h );
	feedbackLayer.opacity = 0;
	feedbackLayer.zPosition = 10;
	[root addSublayer:feedbackLayer];

	diagnosticsLayer = [CATextLayer layer];
	diagnosticsLayer.contentsScale = scale;
	NSFont* mono = [NSFont fontWithName:@"Menlo" size:10];
	diagnosticsLayer.font = (__bridge CFTypeRef)( mono? mono : [NSFont userFixedPitchFontOfSize:10] );
	diagnosticsLayer.fontSize = 10;
	diagnosticsLayer.wrapped = YES;
	CGColorRef yellow = LEDCreateSRGBColour( 1.0, 0.9, 0.3, 1.0 );
	CGColorRef shade = LEDCreateSRGBColour( 0, 0, 0, 0.72 );
	diagnosticsLayer.foregroundColor = yellow;
	diagnosticsLayer.backgroundColor = shade;
	CGColorRelease( yellow );
	CGColorRelease( shade );
	diagnosticsLayer.frame = CGRectMake( layout.diagnosticsArea.x, layout.diagnosticsArea.y, layout.diagnosticsArea.w, layout.diagnosticsArea.h );
	diagnosticsLayer.hidden = YES;
	diagnosticsLayer.zPosition = 10;
	[root addSublayer:diagnosticsLayer];

	builtLayoutSerial = engine->LayoutSerial();
	appliedPaletteSerial = 0;		// force colours to be applied
	needsBuild = NO;
}


#pragma mark colours

- (CGImageRef)gridImageForBar:(LEDBargraph*)bar colour:(CGColorRef)gapColour CF_RETURNS_RETAINED
{
	CGSize s = bar->vertical? CGSizeMake( bar->container.bounds.size.width, bar->length )
							: CGSizeMake( bar->length, bar->container.bounds.size.height );
	int pitchPx = (int) lround( bar->pitch * scale );
	int gapPx = (int) lround( bar->gap * scale );

	return LEDCreateSegmentGridImage( s, scale, bar->segments, pitchPx, gapPx, bar->vertical, bar->fromRight, gapColour );
}


- (void)applyPalette
{
	const Settings& s = engine->GetSettings();
	const Palette& p = engine->CurrentPalette();

	CGColorRef bg = CreateColour( p.background );
	root.backgroundColor = bg;

	// one grid image per bar shape (all spectrum bars of a side share theirs)

	[self releaseImages];

	for ( int c = 0; c < 2; c++ )
	{
		if ( spectrumBars[c].count )
			spectrumGrid[c] = [self gridImageForBar:spectrumBars[c][0] colour:bg];

		for ( LEDBargraph* bar in spectrumBars[c] )
			[bar setBar:p.spectrumBar blend:p.spectrumBlend peak:p.spectrumPeak blendEnabled:s.blendEnabled grid:spectrumGrid[c]];

		if ( vuBars[c] )
		{
			vuGrid[c] = [self gridImageForBar:vuBars[c] colour:bg];
			[vuBars[c] setBar:p.vuBar blend:p.vuBlend peak:p.vuPeak blendEnabled:s.blendEnabled grid:vuGrid[c]];
		}
	}

	if ( layout.analogue && ! ledLit )
	{
		CGRect ledFrame = LEDPeakLEDFrameInMeter( CGSizeMake( layout.leftMeter.w, layout.leftMeter.h ));
		ledLit = LEDCreatePeakLEDImage( ledFrame.size, scale, YES );
		ledUnlit = LEDCreatePeakLEDImage( ledFrame.size, scale, NO );

		for ( int c = 0; c < 2; c++ )
			if ( meters[c] )
				meters[c]->led.contents = (__bridge id)( meters[c]->ledLit? ledLit : ledUnlit );
	}

	// reflection fade: background colour at the bottom, clear at the axis

	CGColorRef bgClear = CreateColour( p.background, 0.0f );
	reflectionFade.colors = @[ (__bridge id) bg, (__bridge id) bgClear ];
	CGColorRelease( bgClear );

	// progress bar: a shiny capsule in the spectrum bar colour, glowing

	Colour bar = p.spectrumBar;
	CGColorRef hi = CreateColour( bar.mix( Colour( 1, 1, 1 ), 0.45f ));
	CGColorRef mid = CreateColour( bar );
	CGColorRef lo = CreateColour( bar.scaled( 0.72f ));
	progressFill.colors = @[ (__bridge id) hi, (__bridge id) mid, (__bridge id) lo ];
	progressFill.locations = @[ @0.0, @0.45, @1.0 ];
	progressFill.shadowColor = mid;
	CGColorRelease( hi );
	CGColorRelease( mid );
	CGColorRelease( lo );

	CGColorRef dot = LEDCreateSRGBColour( 0.33, 0.43, 0.58, 1.0 );
	CGImageRef dots = LEDCreateProgressDotsImage( progressDots.bounds.size, scale, dot );
	progressDots.contents = (__bridge id) dots;
	CGImageRelease( dots );
	CGColorRelease( dot );

	CGColorRelease( bg );
	appliedPaletteSerial = engine->PaletteSerial();
}


#pragma mark per frame

- (void)updateAtTime:(double)now
{
	if ( size.width < 1 || size.height < 1 )
		return;

	[CATransaction begin];
	[CATransaction setDisableActions:YES];

	if ( needsBuild || builtLayoutSerial != engine->LayoutSerial())
		[self build];

	if ( appliedPaletteSerial != engine->PaletteSerial())
		[self applyPalette];

	const Settings& s = engine->GetSettings();
	const Palette& p = engine->CurrentPalette();

	// meters

	for ( int c = 0; c < 2; c++ )
	{
		NSArray<LEDBargraph*>* bars = spectrumBars[c];
		NSUInteger n = MIN( bars.count, (NSUInteger) engine->Bands());

		for ( NSUInteger b = 0; b < n; b++ )
			[bars[b] setValue:engine->BarValue( c, (int) b ) peak:engine->BarPeak( c, (int) b ) showPeak:s.peakIndicatorsEnabled
					showUnlit:s.unlitSegments blendToValue:s.blendToValue];

		if ( vuBars[c] )
			[vuBars[c] setValue:engine->VUValue( c ) peak:engine->VUPeak( c ) showPeak:s.peakIndicatorsEnabled
					  showUnlit:s.unlitSegments blendToValue:s.blendToValue];

		LEDAnalogueMeter* m = meters[c];

		if ( m )
		{
			double pos = engine->NeedlePosition( c );

			if ( fabs( pos - m->shownPosition ) > 1e-4 )
			{
				m->needle.transform = CATransform3DMakeRotation( LEDMeterNeedleAngle( m->geometry, pos ), 0, 0, 1 );
				m->shownPosition = pos;
			}

			BOOL lit = engine->PeakLEDLit( c );

			if ( lit != m->ledLit )
			{
				m->led.contents = (__bridge id)( lit? ledLit : ledUnlit );
				m->ledLit = lit;
			}
		}
	}

	// cover art

	CoverArtState cover = engine->CoverArt( now );
	coverLayer.hidden = ( cover.opacity <= 0 || artwork == NULL );

	if ( ! coverLayer.hidden )
	{
		CGFloat side = MIN( size.width, size.height ) * 0.62;
		CGRect centred = CGRectMake(( size.width - side ) / 2, ( size.height - side ) / 2, side, side );
		CGRect full = CGRectMake( 0, 0, size.width, size.height );
		CGFloat t = cover.centred;

		coverLayer.frame = CGRectMake( full.origin.x + ( centred.origin.x - full.origin.x ) * t,
									   full.origin.y + ( centred.origin.y - full.origin.y ) * t,
									   full.size.width + ( centred.size.width - full.size.width ) * t,
									   full.size.height + ( centred.size.height - full.size.height ) * t );
		coverLayer.contentsGravity = ( t > 0.5 )? kCAGravityResizeAspect : kCAGravityResizeAspectFill;
		coverLayer.opacity = (float) cover.opacity;
		
		// shown in the centre, the artwork sits over the meters (just under the track info);
		// as a background, behind everything. Reordering rather than zPosition works in every renderer
		
		BOOL onTop = ( t > 0.5 );
		
		if ( onTop != coverOnTop )
		{
			if ( onTop )
				[root insertSublayer:coverLayer below:textLayer];
			else
				[root insertSublayer:coverLayer atIndex:0];
			coverOnTop = onTop;
		}
		coverLayer.shadowOpacity = onTop? 0.6f : 0.0f;
	}

	// the reflection fade would hide a background image, so only use it on plain backgrounds

	reflectionFade.hidden = ! s.reflections || ( ! coverLayer.hidden && cover.centred < 0.5 );

	// progress

	if ( layout.showProgress )
	{
		const led::Rect& pt = layout.progressTrack;
		double f = engine->ProgressFraction();
		std::string total = engine->TotalText();

		progressFill.hidden = total.empty();
		progressFill.frame = CGRectMake( pt.x, pt.y, MAX( pt.h, f * pt.w ), pt.h );

		std::string elapsed = engine->ElapsedText();

		if ( elapsed != shownElapsed )
		{
			elapsedLayer.string = ToNSString( elapsed );
			shownElapsed = elapsed;
		}
		if ( total != shownTotal )
		{
			totalLayer.string = ToNSString( total );
			shownTotal = total;
		}
	}

	// track info

	double textOpacity = engine->TextOpacity( now );
	std::string text = engine->TrackText();

	if ( text != shownText )
	{
		NSString* str = ToNSString( text );
		CGFloat fontSize = layout.textFontSize;

		if ( s.sizeTextToFit )
		{
			// shrink a long line to fit (down to 40%), as 3.x did

			CGFloat width = [str sizeWithAttributes:@{ NSFontAttributeName : BoldFont( fontSize ) }].width;
			CGFloat available = layout.textArea.w - layout.textFontSize * 0.5;

			if ( width > available && width > 0 )
				fontSize = MAX( fontSize * 0.4, floor( fontSize * available / width ));
		}

		textLayer.string = str;

		if ( fontSize != shownTextFontSize )
		{
			textLayer.font = (__bridge CFTypeRef) BoldFont( fontSize );
			textLayer.fontSize = fontSize;
			textLayer.shadowRadius = fontSize * 0.22;

			// vertically centre the line in the text area

			CGFloat lineH = ceil( fontSize * 1.25 );
			const led::Rect& ta = layout.textArea;
			textLayer.frame = CGRectMake( ta.x, ta.y + ( ta.h - lineH ) / 2, ta.w, lineH );
			shownTextFontSize = fontSize;
		}
		shownText = text;
	}
	textLayer.opacity = (float) textOpacity;

	// keyboard feedback and diagnostics

	std::string fb = engine->FeedbackText();

	if ( fb != shownFeedback )
	{
		feedbackLayer.string = ToNSString( fb );
		shownFeedback = fb;
	}
	feedbackLayer.opacity = (float) engine->FeedbackOpacity( now );

	diagnosticsLayer.hidden = ! engine->DiagnosticsVisible();

	if ( engine->DiagnosticsVisible())
	{
		std::vector<std::string> lines = engine->DiagnosticLines();
		std::string all;

		for ( size_t i = 0; i < lines.size(); i++ )
			all += " " + lines[i] + "\n";

		diagnosticsLayer.string = ToNSString( all );
	}

	(void) p;
	[CATransaction commit];

	engine->NoteFrameDrawn( now );
}

@end
