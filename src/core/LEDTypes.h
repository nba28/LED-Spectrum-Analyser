/*
 *  LEDTypes.h
 *  LED Spectrum Analyser
 *
 *  Basic geometry and colour types for the platform-neutral core. Geometry uses the Core
 *  Animation / Quartz convention on macOS: origin at bottom-left, y increasing upwards, in points.
 *
 */

#ifndef LED_TYPES_H
#define LED_TYPES_H

#include <math.h>
#include <stdint.h>
#include <string>


namespace led
{

struct Rect
{
	double	x, y, w, h;

	Rect() : x( 0 ), y( 0 ), w( 0 ), h( 0 ) {}
	Rect( double ax, double ay, double aw, double ah ) : x( ax ), y( ay ), w( aw ), h( ah ) {}

	double	minX() const	{ return x; }
	double	maxX() const	{ return x + w; }
	double	minY() const	{ return y; }
	double	maxY() const	{ return y + h; }
	double	midX() const	{ return x + w * 0.5; }
	double	midY() const	{ return y + h * 0.5; }
	bool	empty() const	{ return w <= 0 || h <= 0; }

	bool	contains( const Rect& r, double tolerance = 1e-6 ) const
	{
		return r.x >= x - tolerance && r.y >= y - tolerance && r.maxX() <= maxX() + tolerance && r.maxY() <= maxY() + tolerance;
	}

	bool	intersects( const Rect& r ) const
	{
		return r.x < maxX() - 1e-6 && x < r.maxX() - 1e-6 && r.y < maxY() - 1e-6 && y < r.maxY() - 1e-6;
	}

	Rect	inset( double dx, double dy ) const	{ return Rect( x + dx, y + dy, w - 2 * dx, h - 2 * dy ); }
};


struct Colour
{
	float	r, g, b, a;

	Colour() : r( 0 ), g( 0 ), b( 0 ), a( 1 ) {}
	Colour( float ar, float ag, float ab, float aa = 1.0f ) : r( ar ), g( ag ), b( ab ), a( aa ) {}

	bool	operator==( const Colour& c ) const	{ return r == c.r && g == c.g && b == c.b && a == c.a; }
	bool	operator!=( const Colour& c ) const	{ return !( *this == c ); }

	// "r g b a" with components 0..1 - the form colours are stored in the preferences

	std::string		toString() const;
	static bool		fromString( const std::string& s, Colour* out );

	Colour			mix( const Colour& other, float t ) const;		// linear interpolation, t = 0 -> this
	Colour			scaled( float brightness ) const;				// multiply rgb
	float			luminance() const;

	void			toHSB( float* h, float* s, float* v ) const;
	static Colour	fromHSB( float h, float s, float v, float a = 1.0f );
};


template <typename T> inline T clamp( T v, T lo, T hi ) { return v < lo? lo : ( v > hi? hi : v ); }

}	// namespace led

#endif
