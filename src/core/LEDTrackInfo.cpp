/*
 *  LEDTrackInfo.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDTrackInfo.h"
#include "LEDSettings.h"
#include <stdio.h>
#include <math.h>


namespace led
{

static std::string	Trim( const std::string& s )
{
	size_t b = s.find_first_not_of( " \t\r\n" );

	if ( b == std::string::npos )
		return "";

	size_t e = s.find_last_not_of( " \t\r\n" );
	return s.substr( b, e - b + 1 );
}


void		ApplyStreamTitle( const std::string& streamTitle, TrackInfo* info )
{
	std::string t = Trim( streamTitle );

	if ( t.empty())
		return;

	size_t sep = t.find( " - " );

	if ( sep != std::string::npos && sep > 0 && sep + 3 < t.size())
	{
		info->artist = Trim( t.substr( 0, sep ));
		info->title = Trim( t.substr( sep + 3 ));
	}
	else
		info->title = t;
}


std::string	ComposeTrackText( const TrackInfo& info, int mask )
{
	static const char* const kSeparator = " \xE2\x80\xA2 ";	// " • "

	const struct { int bit; const std::string* field; } parts[] =
	{
		{ kInfoTitle, &info.title },
		{ kInfoArtist, &info.artist },
		{ kInfoAlbum, &info.album },
		{ kInfoYear, &info.year },
		{ kInfoStationIdent, &info.stationIdent }
	};

	std::string out;

	for ( size_t i = 0; i < sizeof( parts ) / sizeof( parts[0] ); i++ )
	{
		if (( mask & parts[i].bit ) && ! parts[i].field->empty())
		{
			if ( ! out.empty())
				out += kSeparator;
			out += *parts[i].field;
		}
	}
	return out;
}


std::string	FormatTime( double seconds )
{
	if ( ! isfinite( seconds ) || seconds < 0 )
		seconds = 0;

	long total = (long) floor( seconds );
	char buf[32];

	if ( total >= 3600 )
		snprintf( buf, sizeof( buf ), "%ld:%02ld:%02ld", total / 3600, ( total / 60 ) % 60, total % 60 );
	else
		snprintf( buf, sizeof( buf ), "%ld:%02ld", total / 60, total % 60 );

	return buf;
}

}	// namespace led
