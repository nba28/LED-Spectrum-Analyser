/*
 *  LEDColours.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDColours.h"
#include <algorithm>
#include <map>
#include <vector>


namespace led
{

Palette		Palette::FromSettings( const Settings& s )
{
	Palette p;

	p.spectrumBar	= s.spectrumBar;
	p.spectrumBlend	= s.spectrumBlend;
	p.spectrumPeak	= s.spectrumPeak;
	p.vuBar			= s.vuBar;
	p.vuBlend		= s.vuBlend;
	p.vuPeak		= s.vuPeak;
	p.background	= s.background;
	return p;
}


void		Palette::ApplyToSettings( Settings* s ) const
{
	s->spectrumBar		= spectrumBar;
	s->spectrumBlend	= spectrumBlend;
	s->spectrumPeak		= spectrumPeak;
	s->vuBar			= vuBar;
	s->vuBlend			= vuBlend;
	s->vuPeak			= vuPeak;
	s->background		= background;
}


bool		Palette::operator==( const Palette& p ) const
{
	return spectrumBar == p.spectrumBar && spectrumBlend == p.spectrumBlend && spectrumPeak == p.spectrumPeak &&
		   vuBar == p.vuBar && vuBlend == p.vuBlend && vuPeak == p.vuPeak && background == p.background;
}


static Colour	RotateHue( const Colour& c, float delta )
{
	float h, s, v;
	c.toHSB( &h, &s, &v );
	return Colour::fromHSB( h + delta, s, v, c.a );
}


Palette		AnimatePalette( const Palette& base, double seconds, double period )
{
	float delta = (float)( fmod( seconds / period, 1.0 ));
	Palette p = base;

	p.spectrumBar	= RotateHue( base.spectrumBar, delta );
	p.spectrumBlend	= RotateHue( base.spectrumBlend, delta );
	p.spectrumPeak	= RotateHue( base.spectrumPeak, delta );
	p.vuBar			= RotateHue( base.vuBar, delta );
	p.vuBlend		= RotateHue( base.vuBlend, delta );
	p.vuPeak		= RotateHue( base.vuPeak, delta );
	return p;
}


static uint32_t	NextRandom( uint32_t* state )
{
	// xorshift32 - deterministic for a given seed, which keeps the tests repeatable

	uint32_t x = *state? *state : 0x9E3779B9u;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	*state = x;
	return x;
}


static float	Unit( uint32_t* state )
{
	return ( NextRandom( state ) & 0xFFFFFF ) / (float) 0x1000000;
}


Palette		RandomPalette( const Palette& base, uint32_t seed )
{
	uint32_t st = seed * 2654435761u + 1;
	Palette p = base;

	float h = Unit( &st );
	float spread = 0.08f + 0.17f * Unit( &st );

	p.spectrumBar	= Colour::fromHSB( h, 0.75f + 0.25f * Unit( &st ), 0.80f + 0.20f * Unit( &st ));
	p.spectrumBlend	= Colour::fromHSB( h + spread, 0.70f + 0.30f * Unit( &st ), 0.85f + 0.15f * Unit( &st ));
	p.spectrumPeak	= Colour::fromHSB( h + 0.5f, 0.6f + 0.3f * Unit( &st ), 1.0f );

	float hv = h + 0.25f + 0.5f * Unit( &st );

	p.vuBar			= Colour::fromHSB( hv, 0.75f + 0.25f * Unit( &st ), 0.85f + 0.15f * Unit( &st ));
	p.vuBlend		= Colour::fromHSB( hv + spread, 0.6f + 0.3f * Unit( &st ), 0.95f );
	p.vuPeak		= p.spectrumPeak;
	return p;
}


// ---------------------------------------------------------------------------------------------
// artwork analysis

namespace
{
	struct Bucket
	{
		double	r, g, b;
		int		count;
	};

	typedef std::map<int, Bucket> Histogram;

	inline int	Key( int r, int g, int b )
	{
		// 4 bits per channel
		return (( r >> 4 ) << 8 ) | (( g >> 4 ) << 4 ) | ( b >> 4 );
	}

	void	Add( Histogram& h, int r, int g, int b )
	{
		Bucket& k = h[ Key( r, g, b ) ];
		k.r += r; k.g += g; k.b += b; k.count++;
	}

	Colour	Average( const Bucket& k )
	{
		return Colour((float)( k.r / k.count / 255.0 ), (float)( k.g / k.count / 255.0 ), (float)( k.b / k.count / 255.0 ));
	}

	std::vector<Bucket>	Sorted( const Histogram& h, int minimum )
	{
		std::vector<Bucket> v;
		for ( Histogram::const_iterator it = h.begin(); it != h.end(); ++it )
			if ( it->second.count >= minimum )
				v.push_back( it->second );
		std::sort( v.begin(), v.end(), []( const Bucket& a, const Bucket& b ) { return a.count > b.count; });
		return v;
	}

	float	Distance( const Colour& a, const Colour& b )
	{
		return sqrtf(( a.r - b.r ) * ( a.r - b.r ) + ( a.g - b.g ) * ( a.g - b.g ) + ( a.b - b.b ) * ( a.b - b.b ));
	}

	float	Contrast( const Colour& a, const Colour& b )
	{
		float la = a.luminance() + 0.05f, lb = b.luminance() + 0.05f;
		return la > lb? la / lb : lb / la;
	}

	bool	IsBlackOrWhite( const Colour& c )
	{
		return ( c.r > 0.91f && c.g > 0.91f && c.b > 0.91f ) || ( c.r < 0.09f && c.g < 0.09f && c.b < 0.09f );
	}

	// make sure a foreground colour is saturated / bright enough to read as an LED

	Colour	Vivid( const Colour& c, bool darkBackground )
	{
		// lift dark colours so they read as lit LEDs on a dark background; greys stay grey
		
		float h, s, v;
		c.toHSB( &h, &s, &v );
		v = darkBackground? std::max( v, 0.55f ) : v;
		return Colour::fromHSB( h, s, v );
	}
	
	bool	StandsOut( const Colour& c, const Colour& bg )
	{
		return Contrast( c, bg ) >= 1.6f || Distance( c, bg ) >= 0.45f;
	}
}


ArtworkColours	AnalyseArtwork( const uint8_t* pixels, int width, int height, int bytesPerRow )
{
	ArtworkColours out;

	out.background	= Colour( 0, 0, 0 );
	out.primary		= Colour( 1, 1, 1 );
	out.secondary	= Colour( 0.8f, 0.8f, 0.8f );
	out.detail		= Colour( 0.6f, 0.6f, 0.6f );

	if ( pixels == NULL || width <= 0 || height <= 0 )
		return out;

	Histogram edge, all;

	for ( int y = 0; y < height; y++ )
	{
		const uint8_t* row = pixels + (size_t) y * bytesPerRow;

		for ( int x = 0; x < width; x++ )
		{
			const uint8_t* p = row + x * 4;

			if ( p[3] < 128 )
				continue;

			Add( all, p[0], p[1], p[2] );

			if ( x < 2 || x >= width - 2 || y < 2 || y >= height - 2 )
				Add( edge, p[0], p[1], p[2] );
		}
	}

	std::vector<Bucket> edgeColours = Sorted( edge, 1 );

	if ( edgeColours.empty())
		return out;

	// background: the most common edge colour, preferring a non-black/white one if it is nearly as common

	Colour bg = Average( edgeColours[0] );

	if ( IsBlackOrWhite( bg ))
	{
		for ( size_t i = 1; i < edgeColours.size(); i++ )
		{
			Colour c = Average( edgeColours[i] );

			if ( edgeColours[i].count < edgeColours[0].count * 0.3 )
				break;
			if ( ! IsBlackOrWhite( c ))
			{
				bg = c;
				break;
			}
		}
	}
	out.background = bg;

	bool darkBackground = bg.luminance() < 0.5f;

	// foreground colours: common colours that contrast with the background and with each other

	std::vector<Bucket> colours = Sorted( all, std::max( 1, width * height / 400 ));
	std::vector<Colour> picked;

	for ( size_t i = 0; i < colours.size() && picked.size() < 3; i++ )
	{
		Colour c = Average( colours[i] );

		if ( ! StandsOut( c, bg ))
			continue;

		bool distinct = true;
		for ( size_t j = 0; j < picked.size(); j++ )
			if ( Distance( c, picked[j] ) < 0.18f )
				distinct = false;

		if ( distinct )
			picked.push_back( c );
	}

	// fall back to a light / dark version of the background

	Colour fallback = darkBackground? bg.mix( Colour( 1, 1, 1 ), 0.8f ) : bg.mix( Colour( 0, 0, 0 ), 0.8f );

	while ( picked.size() < 3 )
		picked.push_back( picked.empty()? fallback : picked.back().mix( fallback, 0.5f ));

	out.primary		= Vivid( picked[0], darkBackground );
	out.secondary	= Vivid( picked[1], darkBackground );
	out.detail		= Vivid( picked[2], darkBackground );
	return out;
}


Palette		PaletteFromArtwork( const ArtworkColours& art, const Palette& base )
{
	Palette p = base;

	p.background	= art.background;
	p.spectrumBar	= art.primary;
	p.spectrumBlend	= art.secondary;
	p.spectrumPeak	= art.detail;
	p.vuBar			= art.secondary;
	p.vuBlend		= art.primary;
	p.vuPeak		= art.detail;
	return p;
}

}	// namespace led
