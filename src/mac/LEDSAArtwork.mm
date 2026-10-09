/*
 *  LEDSAArtwork.mm
 *  LED Spectrum Analyser
 *
 */

#import "LEDSAArtwork.h"
#include "LEDAnalysis.h"


static CGContextRef		CreateContext( CGSize size, CGFloat scale, size_t* outW, size_t* outH )
{
	size_t w = (size_t) MAX( 1.0, ceil( size.width * scale ));
	size_t h = (size_t) MAX( 1.0, ceil( size.height * scale ));

	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );
	CGContextRef ctx = CGBitmapContextCreate( NULL, w, h, 8, 0, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrderDefault );
	CGColorSpaceRelease( space );

	if ( outW ) *outW = w;
	if ( outH ) *outH = h;
	return ctx;
}


static CGImageRef		FinishContext( CGContextRef ctx ) CF_RETURNS_RETAINED;
static CGImageRef		FinishContext( CGContextRef ctx )
{
	if ( ctx == NULL )
		return NULL;

	CGImageRef image = CGBitmapContextCreateImage( ctx );
	CGContextRelease( ctx );
	return image;
}


CGColorRef		LEDCreateSRGBColour( CGFloat r, CGFloat g, CGFloat b, CGFloat a )
{
	// CGColorCreateSRGB needs 10.15; this works back to 10.13 (the x86_64 deployment target)
	
	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );
	CGFloat components[4] = { r, g, b, a };
	CGColorRef colour = CGColorCreate( space, components );
	CGColorSpaceRelease( space );
	return colour;
}


static void		SetFill( CGContextRef ctx, CGFloat r, CGFloat g, CGFloat b, CGFloat a = 1.0 )
{
	CGContextSetRGBFillColor( ctx, r, g, b, a );
}


static void		SetStroke( CGContextRef ctx, CGFloat r, CGFloat g, CGFloat b, CGFloat a = 1.0 )
{
	CGContextSetRGBStrokeColor( ctx, r, g, b, a );
}


// ---------------------------------------------------------------------------------------------

CGImageRef	LEDCreateSegmentGridImage( CGSize size, CGFloat scale, int segments, int pitchPx, int gapPx,
									   BOOL vertical, BOOL fromRight, CGColorRef gapColour )
{
	size_t w, h;
	CGContextRef ctx = CreateContext( size, scale, &w, &h );

	if ( ctx == NULL )
		return NULL;

	// work in pixels so every edge is crisp

	CGContextSetFillColorWithColor( ctx, gapColour );

	for ( int i = 0; i < segments; i++ )
	{
		CGFloat start = i * pitchPx + ( pitchPx - gapPx );		// gap sits at the far end of each segment

		if ( vertical )
			CGContextFillRect( ctx, CGRectMake( 0, start, w, gapPx ));
		else if ( fromRight )
			CGContextFillRect( ctx, CGRectMake( w - start - gapPx, 0, gapPx, h ));
		else
			CGContextFillRect( ctx, CGRectMake( start, 0, gapPx, h ));
	}

	return FinishContext( ctx );
}


CGImageRef	LEDCreateProgressDotsImage( CGSize size, CGFloat scale, CGColorRef dotColour )
{
	CGContextRef ctx = CreateContext( size, scale, NULL, NULL );

	if ( ctx == NULL )
		return NULL;

	CGContextScaleCTM( ctx, scale, scale );
	CGContextSetFillColorWithColor( ctx, dotColour );

	CGFloat d = MAX( 1.5, size.height * 0.28 );
	CGFloat spacing = MAX( 4.0, size.height * 1.2 );
	CGFloat y = ( size.height - d ) / 2;

	for ( CGFloat x = size.width - d - spacing * 0.25; x > 0; x -= spacing )
		CGContextFillEllipseInRect( ctx, CGRectMake( x, y, d, d ));

	return FinishContext( ctx );
}


// ---------------------------------------------------------------------------------------------
// analogue VU meter

LEDMeterGeometry	LEDMeterGeometryForSize( CGSize size )
{
	LEDMeterGeometry g;
	CGFloat h = size.height;
	CGFloat bezel = MAX( 2.0, 0.028 * h );

	g.scaleCentre	= CGPointMake( size.width / 2, -0.35 * h );
	g.scaleRadius	= 0.98 * h;
	g.scaleMaxAngle	= 36.0 * M_PI / 180.0;
	g.pivot			= CGPointMake( size.width / 2, bezel + 0.01 * h );
	g.needleLength	= 0.80 * h;
	return g;
}


CGFloat		LEDMeterScaleAngle( LEDMeterGeometry g, double position )
{
	position = MAX( -0.03, MIN( 1.1, position ));
	return g.scaleMaxAngle * ( 1.0 - 2.0 * position );
}


// polar point around the scale centre; angle measured from vertical, positive to the left

static CGPoint	Polar( LEDMeterGeometry g, CGFloat radius, CGFloat angleFromVertical )
{
	return CGPointMake( g.scaleCentre.x - radius * sin( angleFromVertical ), g.scaleCentre.y + radius * cos( angleFromVertical ));
}


CGFloat		LEDMeterNeedleAngle( LEDMeterGeometry g, double position )
{
	CGPoint target = Polar( g, g.scaleRadius, LEDMeterScaleAngle( g, position ));
	return atan2( -( target.x - g.pivot.x ), target.y - g.pivot.y );
}


static void		DrawCentredText( NSString* text, NSFont* font, NSColor* colour, CGPoint centre )
{
	NSDictionary* attrs = @{ NSFontAttributeName : font, NSForegroundColorAttributeName : colour };
	NSSize s = [text sizeWithAttributes:attrs];
	[text drawAtPoint:NSMakePoint( centre.x - s.width / 2, centre.y - s.height / 2 ) withAttributes:attrs];
}


static NSFont*	Helvetica( CGFloat size, BOOL bold )
{
	NSFont* f = [NSFont fontWithName:( bold? @"Helvetica-Bold" : @"Helvetica" ) size:size];
	return f? f : ( bold? [NSFont boldSystemFontOfSize:size] : [NSFont systemFontOfSize:size] );
}


CGImageRef	LEDCreateMeterFaceImage( CGSize size, CGFloat scale )
{
	CGContextRef ctx = CreateContext( size, scale, NULL, NULL );

	if ( ctx == NULL )
		return NULL;

	CGContextScaleCTM( ctx, scale, scale );

	const CGFloat w = size.width, h = size.height;
	const CGFloat bezel = MAX( 2.0, 0.028 * h );
	CGRect face = CGRectInset( CGRectMake( 0, 0, w, h ), bezel, bezel );

	// black bezel

	SetFill( ctx, 0.04, 0.04, 0.04 );
	CGContextFillRect( ctx, CGRectMake( 0, 0, w, h ));

	// cream face: warm tan at the top fading to pale cream at the bottom, darker towards the corners

	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );

	CGFloat faceColours[] = { 0.98, 0.94, 0.84, 1.0,
							  0.91, 0.82, 0.64, 1.0,
							  0.78, 0.64, 0.44, 1.0 };
	CGFloat faceLocations[] = { 0.0, 0.62, 1.0 };
	CGGradientRef faceGradient = CGGradientCreateWithColorComponents( space, faceColours, faceLocations, 3 );

	CGContextSaveGState( ctx );
	CGContextClipToRect( ctx, face );
	CGContextDrawLinearGradient( ctx, faceGradient, CGPointMake( 0, face.origin.y ), CGPointMake( 0, CGRectGetMaxY( face )), 0 );

	CGFloat vignette[] = { 0.40, 0.25, 0.10, 0.0,
						   0.40, 0.25, 0.10, 0.28 };
	CGFloat vignetteLocations[] = { 0.55, 1.0 };
	CGGradientRef vignetteGradient = CGGradientCreateWithColorComponents( space, vignette, vignetteLocations, 2 );
	CGPoint centre = CGPointMake( w / 2, h * 0.45 );
	CGContextDrawRadialGradient( ctx, vignetteGradient, centre, 0, centre, hypot( w / 2, h * 0.6 ), kCGGradientDrawsAfterEndLocation );
	CGContextRestoreGState( ctx );

	CGGradientRelease( faceGradient );
	CGGradientRelease( vignetteGradient );
	CGColorSpaceRelease( space );

	// scale

	LEDMeterGeometry g = LEDMeterGeometryForSize( size );
	const double zeroDB = led::VUFractionForDB( 0 );
	const CGFloat aStart = LEDMeterScaleAngle( g, led::VUFractionForDB( -20 ));
	const CGFloat aZero = LEDMeterScaleAngle( g, zeroDB );
	const CGFloat aEnd = LEDMeterScaleAngle( g, 1.0 );

	// CG arcs are measured from +x, anticlockwise: angle-from-vertical a -> pi/2 + a

	CGContextSetLineCap( ctx, kCGLineCapButt );

	SetStroke( ctx, 0.05, 0.04, 0.03 );
	CGContextSetLineWidth( ctx, 0.022 * h );
	CGContextBeginPath( ctx );
	CGContextAddArc( ctx, g.scaleCentre.x, g.scaleCentre.y, g.scaleRadius, M_PI_2 + aStart, M_PI_2 + aZero, 1 );
	CGContextStrokePath( ctx );

	// red overload band, thickening towards +3

	SetFill( ctx, 0.93, 0.13, 0.06 );
	CGContextBeginPath( ctx );
	CGContextAddArc( ctx, g.scaleCentre.x, g.scaleCentre.y, g.scaleRadius + 0.011 * h, M_PI_2 + aZero, M_PI_2 + aEnd, 1 );
	CGPoint inner = Polar( g, g.scaleRadius - 0.045 * h, aEnd );
	CGContextAddLineToPoint( ctx, inner.x, inner.y );
	CGContextAddArc( ctx, g.scaleCentre.x, g.scaleCentre.y, g.scaleRadius - 0.011 * h, M_PI_2 + aEnd, M_PI_2 + aZero, 0 );
	CGContextClosePath( ctx );
	CGContextFillPath( ctx );

	// tick marks and numbers

	struct Mark { double db; const char* label; BOOL major; };
	static const Mark marks[] =
	{
		{ -20, "20", YES }, { -10, "10", YES }, { -7, "7", YES }, { -6, NULL, NO }, { -5, "5", YES }, { -4, NULL, NO },
		{ -3, "3", YES }, { -2, NULL, NO }, { -1, NULL, NO }, { 0, "0", YES }, { 1, NULL, NO }, { 2, NULL, NO }, { 3, "3", YES }
	};

	NSGraphicsContext* nsctx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:nsctx];

	NSFont* numberFont = Helvetica( 0.105 * h, NO );
	NSColor* ink = [NSColor colorWithSRGBRed:0.05 green:0.04 blue:0.03 alpha:1];

	for ( size_t i = 0; i < sizeof( marks ) / sizeof( marks[0] ); i++ )
	{
		CGFloat a = LEDMeterScaleAngle( g, led::VUFractionForDB( marks[i].db ));
		BOOL red = ( marks[i].db > 0 ) || ( marks[i].db == 0 );
		CGFloat len = marks[i].major? 0.13 * h : 0.075 * h;

		if ( marks[i].db == -20 )
			len = 0.17 * h;

		CGPoint p1 = Polar( g, g.scaleRadius, a );
		CGPoint p2 = Polar( g, g.scaleRadius + len, a );

		if ( red )
			SetStroke( ctx, 0.93, 0.13, 0.06 );
		else
			SetStroke( ctx, 0.05, 0.04, 0.03 );

		CGContextSetLineWidth( ctx, red? 0.016 * h : ( marks[i].major? 0.032 * h : 0.012 * h ));
		CGContextSetLineCap( ctx, marks[i].major && ! red? kCGLineCapRound : kCGLineCapButt );
		CGContextBeginPath( ctx );
		CGContextMoveToPoint( ctx, p1.x, p1.y );
		CGContextAddLineToPoint( ctx, p2.x, p2.y );
		CGContextStrokePath( ctx );

		if ( marks[i].label )
			DrawCentredText( @( marks[i].label ), numberFont, ink, Polar( g, g.scaleRadius + len + 0.085 * h, a ));
	}

	NSFont* signFont = Helvetica( 0.11 * h, NO );
	DrawCentredText( @"–", signFont, ink, CGPointMake( 0.085 * w, 0.80 * h ));
	DrawCentredText( @"+", signFont, ink, CGPointMake( 0.895 * w, 0.80 * h ));
	DrawCentredText( @"VU", Helvetica( 0.20 * h, YES ), ink, CGPointMake( w / 2, 0.42 * h ));

	[NSGraphicsContext restoreGraphicsState];

	return FinishContext( ctx );
}


CGImageRef	LEDCreateMeterHubImage( CGSize size, CGFloat scale )
{
	CGContextRef ctx = CreateContext( size, scale, NULL, NULL );

	if ( ctx == NULL )
		return NULL;

	CGContextScaleCTM( ctx, scale, scale );

	const CGFloat w = size.width, h = size.height;
	const CGFloat bezel = MAX( 2.0, 0.028 * h );

	// cream mounting plate along the bottom

	CGRect plate = CGRectMake( 0.26 * w, bezel - 1, 0.48 * w, 0.045 * h + 1 );
	SetFill( ctx, 0.96, 0.93, 0.84 );
	CGContextFillRect( ctx, plate );
	SetStroke( ctx, 0.05, 0.04, 0.03 );
	CGContextSetLineWidth( ctx, MAX( 0.75, 0.007 * h ));
	CGContextStrokeRect( ctx, CGRectInset( plate, 0.5, 0.5 ));

	// brown dome over the needle pivot

	CGFloat r = 0.175 * h;
	CGPoint c = CGPointMake( w / 2, bezel );

	SetFill( ctx, 0.96, 0.93, 0.84 );
	CGContextBeginPath( ctx );
	CGContextAddArc( ctx, c.x, c.y, r + 0.02 * h, 0, M_PI, 0 );
	CGContextClosePath( ctx );
	CGContextFillPath( ctx );

	CGContextSaveGState( ctx );
	CGContextBeginPath( ctx );
	CGContextAddArc( ctx, c.x, c.y, r, 0, M_PI, 0 );
	CGContextClosePath( ctx );
	CGContextClip( ctx );

	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );
	CGFloat dome[] = { 0.78, 0.48, 0.22, 1.0,
					   0.55, 0.30, 0.12, 1.0,
					   0.28, 0.14, 0.05, 1.0 };
	CGFloat locations[] = { 0.0, 0.45, 1.0 };
	CGGradientRef gradient = CGGradientCreateWithColorComponents( space, dome, locations, 3 );
	CGPoint highlight = CGPointMake( c.x - 0.25 * r, c.y + 0.55 * r );
	CGContextDrawRadialGradient( ctx, gradient, highlight, 0, c, r * 1.05, kCGGradientDrawsAfterEndLocation );
	CGGradientRelease( gradient );
	CGColorSpaceRelease( space );
	CGContextRestoreGState( ctx );

	SetStroke( ctx, 0.05, 0.04, 0.03, 0.8 );
	CGContextBeginPath( ctx );
	CGContextAddArc( ctx, c.x, c.y, r, 0, M_PI, 0 );
	CGContextStrokePath( ctx );

	return FinishContext( ctx );
}


CGRect		LEDPeakLEDFrameInMeter( CGSize meterSize )
{
	CGFloat h = meterSize.height;
	CGFloat s = 0.17 * h;
	return CGRectMake( 0.885 * meterSize.width - s / 2, 0.40 * h - s / 2, s, s );
}


CGImageRef	LEDCreatePeakLEDImage( CGSize size, CGFloat scale, BOOL lit )
{
	CGContextRef ctx = CreateContext( size, scale, NULL, NULL );

	if ( ctx == NULL )
		return NULL;

	CGContextScaleCTM( ctx, scale, scale );

	const CGFloat w = size.width, h = size.height;
	CGFloat d = MIN( w, h ) * 0.55;
	CGRect led = CGRectMake(( w - d ) / 2, h - d - 0.04 * h, d, d );
	CGPoint c = CGPointMake( CGRectGetMidX( led ), CGRectGetMidY( led ));

	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );

	CGFloat litColours[] = { 1.00, 0.72, 0.62, 1.0,
							 0.96, 0.16, 0.06, 1.0,
							 0.45, 0.02, 0.00, 1.0 };
	CGFloat offColours[] = { 0.66, 0.36, 0.33, 1.0,
							 0.40, 0.07, 0.06, 1.0,
							 0.16, 0.02, 0.02, 1.0 };
	CGFloat locations[] = { 0.0, 0.5, 1.0 };
	CGGradientRef gradient = CGGradientCreateWithColorComponents( space, lit? litColours : offColours, locations, 3 );

	if ( lit )
	{
		// glow

		CGContextSaveGState( ctx );
		CGColorRef glow = LEDCreateSRGBColour( 1.0, 0.2, 0.05, 0.9 );
		CGContextSetShadowWithColor( ctx, CGSizeZero, d * 0.45, glow );
		CGColorRelease( glow );
		SetFill( ctx, 0.9, 0.1, 0.05 );
		CGContextFillEllipseInRect( ctx, led );
		CGContextRestoreGState( ctx );
	}

	CGContextSaveGState( ctx );
	CGContextAddEllipseInRect( ctx, led );
	CGContextClip( ctx );
	CGPoint highlight = CGPointMake( c.x - d * 0.18, c.y + d * 0.2 );
	CGContextDrawRadialGradient( ctx, gradient, highlight, 0, c, d * 0.6, kCGGradientDrawsAfterEndLocation );
	CGContextRestoreGState( ctx );

	CGGradientRelease( gradient );
	CGColorSpaceRelease( space );

	SetStroke( ctx, 0.05, 0.04, 0.03, 0.9 );
	CGContextSetLineWidth( ctx, MAX( 0.5, d * 0.05 ));
	CGContextStrokeEllipseInRect( ctx, led );

	NSGraphicsContext* nsctx = [NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
	[NSGraphicsContext saveGraphicsState];
	[NSGraphicsContext setCurrentContext:nsctx];
	DrawCentredText( @"PEAK", Helvetica( h * 0.2, NO ), [NSColor colorWithSRGBRed:0.05 green:0.04 blue:0.03 alpha:1],
					 CGPointMake( w / 2, h * 0.14 ));
	[NSGraphicsContext restoreGraphicsState];

	return FinishContext( ctx );
}
