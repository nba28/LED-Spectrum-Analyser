/*
 *  LEDColours.h
 *  LED Spectrum Analyser
 *
 *  The set of colours actually drawn, which can come from the settings, from random choice on
 *  track change, from slow colour animation, or from the current cover artwork.
 *
 */

#ifndef LED_COLOURS_H
#define LED_COLOURS_H

#include <stdint.h>
#include "LEDSettings.h"


namespace led
{

struct Palette
{
	Colour	spectrumBar, spectrumBlend, spectrumPeak;
	Colour	vuBar, vuBlend, vuPeak;
	Colour	background;

	static Palette	FromSettings( const Settings& s );
	void			ApplyToSettings( Settings* s ) const;
	bool			operator==( const Palette& p ) const;
	bool			operator!=( const Palette& p ) const	{ return !( *this == p ); }
};


// "Animated Colours": all element hues rotate slowly together; one full turn per <period> seconds

Palette		AnimatePalette( const Palette& base, double seconds, double period = 90.0 );

// "Randomise on Track Change": a pleasing random scheme. <seed> drives the choice

Palette		RandomPalette( const Palette& base, uint32_t seed );


// colours extracted from cover art, in the style of Panic's ColorArt (which 3.x's
// GCImageColorAnalyser followed): the dominant edge colour becomes the background, and the
// most common colours that stand out against it become the primary / secondary / detail colours.

struct ArtworkColours
{
	Colour	background;
	Colour	primary;
	Colour	secondary;
	Colour	detail;
};

// pixels: RGBA, 8 bits per component, rows of <bytesPerRow>. Works best on a small (~64x64) image.

ArtworkColours	AnalyseArtwork( const uint8_t* pixels, int width, int height, int bytesPerRow );

Palette			PaletteFromArtwork( const ArtworkColours& art, const Palette& base );

}	// namespace led

#endif
