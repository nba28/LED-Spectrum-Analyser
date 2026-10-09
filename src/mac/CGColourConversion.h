/*
 *  CGColourConversion.h
 *  LED Spectrum Analyser
 *
 *  NSColor <-> core colour conversion (sRGB, with alpha).
 *
 */

#import <Cocoa/Cocoa.h>
#include "LEDTypes.h"


static inline led::Colour	LEDColourFromNSColor( NSColor* colour )
{
	NSColor* c = [colour colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
	
	if ( c == nil )
		return led::Colour( 0, 0, 0, 1 );
	
	return led::Colour( led::clamp( (float) c.redComponent, 0.0f, 1.0f ), led::clamp( (float) c.greenComponent, 0.0f, 1.0f ),
						led::clamp( (float) c.blueComponent, 0.0f, 1.0f ), led::clamp( (float) c.alphaComponent, 0.0f, 1.0f ));
}


static inline NSColor*		LEDNSColorFromColour( const led::Colour& c )
{
	return [NSColor colorWithSRGBRed:c.r green:c.g blue:c.b alpha:c.a];
}
