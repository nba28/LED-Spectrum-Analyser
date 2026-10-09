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

// The scale is an arc centred well below the face; the needle pivots at the hub on the bottom
// edge (as on the 3.0.7 meter), and is angled to point exactly at the scale position.

typedef struct
{
	CGPoint		scaleCentre;	// centre of the scale arc, below the face
	CGFloat		scaleRadius;
	CGFloat		scaleMaxAngle;	// radians either side of vertical, about scaleCentre
	CGPoint		pivot;			// needle pivot, under the hub
	CGFloat		needleLength;
} LEDMeterGeometry;

LEDMeterGeometry	LEDMeterGeometryForSize( CGSize size );

// angle of a scale position 0..1 about the scale centre, from vertical (positive = left)

CGFloat		LEDMeterScaleAngle( LEDMeterGeometry g, double position );

// needle rotation (radians, anticlockwise positive as Core Animation uses) for a position 0..1

CGFloat		LEDMeterNeedleAngle( LEDMeterGeometry g, double position );

CGImageRef	LEDCreateMeterFaceImage( CGSize size, CGFloat scale ) CF_RETURNS_RETAINED;
CGImageRef	LEDCreateMeterHubImage( CGSize size, CGFloat scale ) CF_RETURNS_RETAINED;		// full meter size, mostly transparent
CGImageRef	LEDCreatePeakLEDImage( CGSize size, CGFloat scale, BOOL lit ) CF_RETURNS_RETAINED;
CGRect		LEDPeakLEDFrameInMeter( CGSize meterSize );
