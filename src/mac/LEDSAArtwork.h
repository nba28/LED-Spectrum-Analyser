/*
 *  LEDSAArtwork.h
 *  LED Spectrum Analyser
 *
 *  Procedurally drawn images: the LED segment grid, progress bar dots, and the analogue VU meter
 *  (face, needle hub and peak LED). The meter is drawn to resemble the one in LEDSA 3.0.7; none of
 *  the 3.0.7 artwork is used.
 *
 *  All functions return +1 retained CGImages (release with CGImageRelease). Sizes are in points;
 *  images are rendered at <scale> pixels per point.
 *
 */

#import <Cocoa/Cocoa.h>


CGColorRef	LEDCreateSRGBColour( CGFloat r, CGFloat g, CGFloat b, CGFloat a ) CF_RETURNS_RETAINED;


// the segment grid laid over every bargraph: transparent where the LED segments are, the
// background colour in the gaps between them. Segment 0 is at the bottom (vertical) or at the
// left / right end (horizontal, <fromRight> selects which).

CGImageRef	LEDCreateSegmentGridImage( CGSize size, CGFloat scale, int segments, int pitchPx, int gapPx,
									   BOOL vertical, BOOL fromRight, CGColorRef gapColour ) CF_RETURNS_RETAINED;

CGImageRef	LEDCreateProgressDotsImage( CGSize size, CGFloat scale, CGColorRef dotColour ) CF_RETURNS_RETAINED;


// analogue VU meter geometry, shared by the face drawing and the needle

typedef struct
{
	CGPoint		pivot;			// below the bottom edge of the face
	CGFloat		scaleRadius;
	CGFloat		needleLength;
	CGFloat		maxAngle;		// radians either side of vertical
} LEDMeterGeometry;

LEDMeterGeometry	LEDMeterGeometryForSize( CGSize size );

// rotation (radians, anticlockwise positive as Core Animation uses) for a needle position 0..1

CGFloat		LEDMeterNeedleAngle( LEDMeterGeometry g, double position );

CGImageRef	LEDCreateMeterFaceImage( CGSize size, CGFloat scale ) CF_RETURNS_RETAINED;
CGImageRef	LEDCreateMeterHubImage( CGSize size, CGFloat scale ) CF_RETURNS_RETAINED;		// full meter size, mostly transparent
CGImageRef	LEDCreatePeakLEDImage( CGSize size, CGFloat scale, BOOL lit ) CF_RETURNS_RETAINED;
CGRect		LEDPeakLEDFrameInMeter( CGSize meterSize );
