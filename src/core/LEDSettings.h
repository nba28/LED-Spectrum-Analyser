/*
 *  LEDSettings.h
 *  LED Spectrum Analyser
 *
 *  Every user setting, with the defaults and value ranges of LEDSA 3.0.7. The key names are the
 *  ones 3.0.7 itself used. Settings serialise to a flat string dictionary, which is how they are
 *  stored in the preferences and in user presets.
 *
 */

#ifndef LED_SETTINGS_H
#define LED_SETTINGS_H

#include <map>
#include <string>
#include "LEDTypes.h"


namespace led
{

typedef std::map<std::string, std::string> Dictionary;

enum LayoutMode
{
	kLayoutSideBySide		= 0,
	kLayoutBackToBack		= 1,
	kLayoutAnalogueVU		= 2,
	kLayoutCount			= 3
};

enum TrackInfoField
{
	kInfoTitle				= 1 << 0,
	kInfoArtist				= 1 << 1,
	kInfoAlbum				= 1 << 2,
	kInfoYear				= 1 << 3,
	kInfoStationIdent		= 1 << 4,
	kInfoAllFields			= 0x1F
};

// the four band counts offered by 3.x

static const int kBandChoices[] = { 10, 18, 24, 31 };
static const int kBandChoiceCount = 4;

// slider ranges, in seconds, from the 3.0.7 options panel

static const double kMinBarTime = 0.1, kMaxBarTime = 1.5;		// peak hold, peak decay, bar decay
static const double kMinVUDecay = 0.05, kMaxVUDecay = 0.8;
static const double kMinGain = 0.5, kMaxGain = 1.5;				// VU gain knob
static const double kMinSpectrumGain = 0.25, kMaxSpectrumGain = 4.0;


struct Settings
{
	// Layout tab

	int		layout;					// LayoutMode
	int		numberOfSpectrumBars;	// 10, 18, 24 or 31
	bool	showVU;					// VU bargraphs
	bool	scalesVisible;			// scale labels
	bool	showProgress;			// progress bar
	int		trackInfoMask;			// TrackInfoField bits; 0 hides track information
	bool	keepTextVisible;		// "Stay Visible"
	bool	textAbove;				// "Above Display"
	bool	sizeTextToFit;
	bool	coverArt;				// show cover art
	bool	coverArtBackgroundEffect;	// use as background image
	bool	coverArtColours;		// use artwork colours

	// Appearance tab

	Colour	spectrumBar;			// "spectrum_segments"
	Colour	spectrumBlend;			// "spectrum_alternate"
	Colour	spectrumPeak;
	Colour	vuBar;
	Colour	vuBlend;
	Colour	vuPeak;
	Colour	background;
	bool	blendEnabled;
	bool	randomiseColours;
	bool	blendToValue;			// "Blend to Current Value"
	bool	animateColours;
	bool	peakIndicatorsEnabled;
	bool	unlitSegments;
	bool	reflections;
	bool	perspective;

	// Advanced tab

	bool	logResponse;
	bool	binUsingPeak;			// "Bin Using Peak Values"
	bool	expDecay;
	bool	preventSleep;
	double	peakHoldTime;			// seconds
	double	peakDecayTime;
	double	barDecayTime;
	double	vuDecayTime;			// analogue VU meters
	double	vuMeterGain;			// analogue VU meters
	double	spectrumGain;			// new in this port: scales the host's spectrum data

	Settings();

	void		Validate();						// clamp everything into range
	Dictionary	ToDictionary() const;
	void		FromDictionary( const Dictionary& d );	// missing / bad keys keep their current value

	void		CycleLayout();
	void		CycleNumberOfBars();
	static int	NearestBandChoice( int bands );
};

}	// namespace led

#endif
