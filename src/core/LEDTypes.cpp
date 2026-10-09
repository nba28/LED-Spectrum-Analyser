/*
 *  LEDTypes.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDTypes.h"
#include <stdio.h>
#include <stdlib.h>


namespace led
{

std::string		Colour::toString() const
{
	char buf[96];
	snprintf( buf, sizeof( buf ), "%.4f %.4f %.4f %.4f", r, g, b, a );
	return buf;
}


bool			Colour::fromString( const std::string& s, Colour* out )
{
	float c[4];
	char extra;

	int n = sscanf( s.c_str(), "%f %f %f %f %c", &c[0], &c[1], &c[2], &c[3], &extra );

	if ( n != 4 )
		return false;

	for ( int i = 0; i < 4; i++ )
		if ( ! isfinite( c[i] ))
			return false;

	*out = Colour( clamp( c[0], 0.0f, 1.0f ), clamp( c[1], 0.0f, 1.0f ), clamp( c[2], 0.0f, 1.0f ), clamp( c[3], 0.0f, 1.0f ));
	return true;
}


Colour			Colour::mix( const Colour& o, float t ) const
{
	return Colour( r + ( o.r - r ) * t, g + ( o.g - g ) * t, b + ( o.b - b ) * t, a + ( o.a - a ) * t );
}


Colour			Colour::scaled( float k ) const
{
	return Colour( clamp( r * k, 0.0f, 1.0f ), clamp( g * k, 0.0f, 1.0f ), clamp( b * k, 0.0f, 1.0f ), a );
}


float			Colour::luminance() const
{
	return 0.2126f * r + 0.7152f * g + 0.0722f * b;
}


void			Colour::toHSB( float* h, float* s, float* v ) const
{
	float mx = fmaxf( r, fmaxf( g, b ));
	float mn = fminf( r, fminf( g, b ));
	float d = mx - mn;

	*v = mx;
	*s = ( mx > 0 )? d / mx : 0;

	if ( d <= 0 )
		*h = 0;
	else if ( mx == r )
		*h = fmodf(( g - b ) / d + 6.0f, 6.0f ) / 6.0f;
	else if ( mx == g )
		*h = (( b - r ) / d + 2.0f ) / 6.0f;
	else
		*h = (( r - g ) / d + 4.0f ) / 6.0f;
}


Colour			Colour::fromHSB( float h, float s, float v, float a )
{
	h = h - floorf( h );

	float hh = h * 6.0f;
	int   i = (int) floorf( hh ) % 6;
	float f = hh - floorf( hh );
	float p = v * ( 1 - s );
	float q = v * ( 1 - s * f );
	float t = v * ( 1 - s * ( 1 - f ));

	switch ( i )
	{
		case 0:	return Colour( v, t, p, a );
		case 1:	return Colour( q, v, p, a );
		case 2:	return Colour( p, v, t, a );
		case 3:	return Colour( p, q, v, a );
		case 4:	return Colour( t, p, v, a );
		default: return Colour( v, p, q, a );
	}
}

}	// namespace led
