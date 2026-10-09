/*
 *  LEDSettings.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDSettings.h"
#include <stdio.h>
#include <stdlib.h>


namespace led
{

Settings::Settings()
{
	// defaults follow the 3.0.7 options panel and the colours of the screenshot in Graham's manual

	layout						= kLayoutSideBySide;
	numberOfSpectrumBars		= 18;
	showVU						= true;
	scalesVisible				= true;
	showProgress				= false;
	trackInfoMask				= kInfoTitle | kInfoArtist;
	keepTextVisible				= false;
	textAbove					= false;
	sizeTextToFit				= true;
	coverArt					= true;
	coverArtBackgroundEffect	= false;
	coverArtColours				= false;

	spectrumBar					= Colour( 0.937f, 0.478f, 0.094f );		// orange
	spectrumBlend				= Colour( 0.604f, 0.741f, 0.118f );		// yellow-green
	spectrumPeak				= Colour( 0.255f, 0.863f, 0.906f );		// cyan
	vuBar						= Colour( 0.890f, 0.380f, 0.231f );		// red-orange
	vuBlend						= Colour( 0.961f, 0.596f, 0.478f );		// salmon
	vuPeak						= Colour( 0.255f, 0.863f, 0.906f );
	background					= Colour( 0, 0, 0 );
	blendEnabled				= true;
	randomiseColours			= false;
	blendToValue				= false;
	animateColours				= false;
	peakIndicatorsEnabled		= true;
	unlitSegments				= true;
	reflections					= true;
	perspective					= true;

	logResponse					= true;
	binUsingPeak				= false;
	expDecay					= true;
	preventSleep				= true;
	peakHoldTime				= 0.6;
	peakDecayTime				= 0.6;
	barDecayTime				= 0.6;
	vuDecayTime					= 0.3;
	vuMeterGain					= 1.0;
	spectrumGain				= 1.0;
}


int		Settings::NearestBandChoice( int bands )
{
	int best = kBandChoices[0];

	for ( int i = 0; i < kBandChoiceCount; i++ )
		if ( abs( kBandChoices[i] - bands ) < abs( best - bands ))
			best = kBandChoices[i];

	return best;
}


static double	ClampTime( double v, double lo, double hi )
{
	return isfinite( v )? clamp( v, lo, hi ) : lo;
}


void	Settings::Validate()
{
	if ( layout < 0 || layout >= kLayoutCount )
		layout = kLayoutSideBySide;

	numberOfSpectrumBars = NearestBandChoice( numberOfSpectrumBars );
	trackInfoMask &= kInfoAllFields;

	peakHoldTime	= ClampTime( peakHoldTime, kMinBarTime, kMaxBarTime );
	peakDecayTime	= ClampTime( peakDecayTime, kMinBarTime, kMaxBarTime );
	barDecayTime	= ClampTime( barDecayTime, kMinBarTime, kMaxBarTime );
	vuDecayTime		= ClampTime( vuDecayTime, kMinVUDecay, kMaxVUDecay );
	vuMeterGain		= ClampTime( vuMeterGain, kMinGain, kMaxGain );
	spectrumGain	= ClampTime( spectrumGain, kMinSpectrumGain, kMaxSpectrumGain );
}


static std::string	B( bool v )		{ return v? "1" : "0"; }
static std::string	I( int v )		{ char b[32]; snprintf( b, sizeof( b ), "%d", v ); return b; }
static std::string	D( double v )	{ char b[48]; snprintf( b, sizeof( b ), "%.6g", v ); return b; }


Dictionary	Settings::ToDictionary() const
{
	Dictionary d;

	d["layout"]						= I( layout );
	d["numberOfSpectrumBars"]		= I( numberOfSpectrumBars );
	d["showVU"]						= B( showVU );
	d["scalesVisible"]				= B( scalesVisible );
	d["showProgress"]				= B( showProgress );
	d["trackInfoMask"]				= I( trackInfoMask );
	d["keepTextVisible"]			= B( keepTextVisible );
	d["textAbove"]					= B( textAbove );
	d["sizeTextToFit"]				= B( sizeTextToFit );
	d["coverArt"]					= B( coverArt );
	d["coverArtBackgroundEffect"]	= B( coverArtBackgroundEffect );
	d["coverArtColours"]			= B( coverArtColours );

	d["spectrum_segments"]			= spectrumBar.toString();
	d["spectrum_alternate"]			= spectrumBlend.toString();
	d["spectrum_peak"]				= spectrumPeak.toString();
	d["vu_segments"]				= vuBar.toString();
	d["vu_alternate"]				= vuBlend.toString();
	d["vu_peak"]					= vuPeak.toString();
	d["gen_background"]				= background.toString();
	d["blendEnabled"]				= B( blendEnabled );
	d["randomiseColours"]			= B( randomiseColours );
	d["blendToValue"]				= B( blendToValue );
	d["animateColours"]				= B( animateColours );
	d["peakIndicatorsEnabled"]		= B( peakIndicatorsEnabled );
	d["unlitSegments"]				= B( unlitSegments );
	d["reflections"]				= B( reflections );
	d["perspective"]				= B( perspective );

	d["response"]					= I( logResponse? 1 : 0 );
	d["binning"]					= I( binUsingPeak? 1 : 0 );
	d["bar_decayResponse"]			= I( expDecay? 1 : 0 );
	d["preventSleep"]				= B( preventSleep );
	d["bar_peakHold"]				= D( peakHoldTime );
	d["bar_peakDecay"]				= D( peakDecayTime );
	d["bar_barDecay"]				= D( barDecayTime );
	d["analogue_vu_decay"]			= D( vuDecayTime );
	d["vuMeterGain"]				= D( vuMeterGain );
	d["spectrumGain"]				= D( spectrumGain );

	return d;
}


static bool	ParseInt( const Dictionary& d, const char* key, int* out )
{
	Dictionary::const_iterator it = d.find( key );

	if ( it == d.end())
		return false;

	char* end = NULL;
	long v = strtol( it->second.c_str(), &end, 10 );

	if ( end == it->second.c_str() || *end != 0 )
		return false;

	*out = (int) v;
	return true;
}


static void	GetBool( const Dictionary& d, const char* key, bool* out )
{
	int v;

	if ( ParseInt( d, key, &v ))
		*out = ( v != 0 );
}


static void	GetInt( const Dictionary& d, const char* key, int* out )
{
	ParseInt( d, key, out );
}


static void	GetDouble( const Dictionary& d, const char* key, double* out )
{
	Dictionary::const_iterator it = d.find( key );

	if ( it == d.end())
		return;

	char* end = NULL;
	double v = strtod( it->second.c_str(), &end );

	if ( end != it->second.c_str() && *end == 0 && isfinite( v ))
		*out = v;
}


static void	GetColour( const Dictionary& d, const char* key, Colour* out )
{
	Dictionary::const_iterator it = d.find( key );

	if ( it != d.end())
		Colour::fromString( it->second, out );
}


void	Settings::FromDictionary( const Dictionary& d )
{
	int v;

	GetInt( d, "layout", &layout );
	GetInt( d, "numberOfSpectrumBars", &numberOfSpectrumBars );
	GetBool( d, "showVU", &showVU );
	GetBool( d, "scalesVisible", &scalesVisible );
	GetBool( d, "showProgress", &showProgress );
	GetInt( d, "trackInfoMask", &trackInfoMask );
	GetBool( d, "keepTextVisible", &keepTextVisible );
	GetBool( d, "textAbove", &textAbove );
	GetBool( d, "sizeTextToFit", &sizeTextToFit );
	GetBool( d, "coverArt", &coverArt );
	GetBool( d, "coverArtBackgroundEffect", &coverArtBackgroundEffect );
	GetBool( d, "coverArtColours", &coverArtColours );

	GetColour( d, "spectrum_segments", &spectrumBar );
	GetColour( d, "spectrum_alternate", &spectrumBlend );
	GetColour( d, "spectrum_peak", &spectrumPeak );
	GetColour( d, "vu_segments", &vuBar );
	GetColour( d, "vu_alternate", &vuBlend );
	GetColour( d, "vu_peak", &vuPeak );
	GetColour( d, "gen_background", &background );
	GetBool( d, "blendEnabled", &blendEnabled );
	GetBool( d, "randomiseColours", &randomiseColours );
	GetBool( d, "blendToValue", &blendToValue );
	GetBool( d, "animateColours", &animateColours );
	GetBool( d, "peakIndicatorsEnabled", &peakIndicatorsEnabled );
	GetBool( d, "unlitSegments", &unlitSegments );
	GetBool( d, "reflections", &reflections );
	GetBool( d, "perspective", &perspective );

	if ( ParseInt( d, "response", &v ))				logResponse = ( v != 0 );
	if ( ParseInt( d, "binning", &v ))				binUsingPeak = ( v != 0 );
	if ( ParseInt( d, "bar_decayResponse", &v ))	expDecay = ( v != 0 );
	GetBool( d, "preventSleep", &preventSleep );
	GetDouble( d, "bar_peakHold", &peakHoldTime );
	GetDouble( d, "bar_peakDecay", &peakDecayTime );
	GetDouble( d, "bar_barDecay", &barDecayTime );
	GetDouble( d, "analogue_vu_decay", &vuDecayTime );
	GetDouble( d, "vuMeterGain", &vuMeterGain );
	GetDouble( d, "spectrumGain", &spectrumGain );

	Validate();
}


void	Settings::CycleLayout()
{
	layout = ( layout + 1 ) % kLayoutCount;
}


void	Settings::CycleNumberOfBars()
{
	for ( int i = 0; i < kBandChoiceCount; i++ )
	{
		if ( kBandChoices[i] == numberOfSpectrumBars )
		{
			numberOfSpectrumBars = kBandChoices[( i + 1 ) % kBandChoiceCount];
			return;
		}
	}
	numberOfSpectrumBars = kBandChoices[0];
}

}	// namespace led
