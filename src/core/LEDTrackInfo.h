/*
 *  LEDTrackInfo.h
 *  LED Spectrum Analyser
 *
 *  Track information as shown by the visualizer, and how it is composed into the single line of
 *  text 3.x displays ("Title • Artist • Album • Year • Station").
 *
 */

#ifndef LED_TRACKINFO_H
#define LED_TRACKINFO_H

#include <string>
#include <stdint.h>


namespace led
{

struct TrackInfo
{
	std::string		title;
	std::string		artist;
	std::string		album;
	std::string		year;
	std::string		stationIdent;		// name of the station for streamed audio
	uint32_t		totalTimeMS;		// 0 if unknown (e.g. streams)

	TrackInfo() : totalTimeMS( 0 ) {}

	bool	operator==( const TrackInfo& o ) const
	{
		return title == o.title && artist == o.artist && album == o.album && year == o.year &&
			   stationIdent == o.stationIdent && totalTimeMS == o.totalTimeMS;
	}
	bool	operator!=( const TrackInfo& o ) const	{ return !( *this == o ); }
	bool	IsEmpty() const	{ return title.empty() && artist.empty() && album.empty() && year.empty() && stationIdent.empty(); }
};


// fills in title / artist from a stream title. Most stations send "Artist - Title"; a few send
// only a title, which is left as is.

void			ApplyStreamTitle( const std::string& streamTitle, TrackInfo* info );

// the displayed line, honouring the Settings::trackInfoMask bits

std::string		ComposeTrackText( const TrackInfo& info, int mask );

// "m:ss" as 3.x showed it

std::string		FormatTime( double seconds );

}	// namespace led

#endif
