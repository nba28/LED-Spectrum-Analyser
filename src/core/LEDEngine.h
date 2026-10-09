/*
 *  LEDEngine.h
 *  LED Spectrum Analyser
 *
 *  The platform-neutral heart of the visualizer: receives what the host (iTunes / Music) sends,
 *  runs the meters, keeps track of what text / artwork should be visible and how opaque it is,
 *  handles keyboard commands and presets. The Mac layer asks it what to draw.
 *
 *  Time is in seconds from any monotonic clock.
 *
 */

#ifndef LED_ENGINE_H
#define LED_ENGINE_H

#include <string>
#include <vector>
#include "LEDAnalysis.h"
#include "LEDColours.h"
#include "LEDLayout.h"
#include "LEDTrackInfo.h"


namespace led
{

class EngineHost
{
public:
	virtual ~EngineHost(){}

	virtual void	OpenOptions() = 0;
	virtual void	SettingsDidChange() = 0;		// persist the settings and refresh the options window
	virtual void	PresetsDidChange() = 0;			// persist the presets
};


static const double kTextDisplayTime		= 20.0;		// track info visible after a change (3.x)
static const double kCoverDisplayTime		= 6.0;		// cover art shown in the centre (3.x)
static const double kFadeTime				= 1.25;
static const double kFeedbackTime			= 3.0;
static const double kCoverBackgroundOpacity	= 0.33;
static const int	kMaxPresets				= 10;


struct CoverArtState
{
	double	opacity;		// 0..1
	double	centred;		// 1 = shown in the centre, 0 = filling the view as a background
};


class Engine
{
public:
	explicit Engine( EngineHost* host = NULL );

	// settings

	Settings&			GetSettings()			{ return settings; }
	const Settings&		GetSettings() const		{ return settings; }
	void				SettingsEdited( double now );			// call after changing GetSettings()
	uint32_t			LayoutSerial() const	{ return layoutSerial; }	// changes when geometry may change

	// host

	void				SetHostInfo( const std::string& name, uint32_t appVersion, uint32_t apiMajor, uint32_t apiMinor );
	void				SetAudioFormat( double sampleRate, uint32_t channels );
	void				SetPlaying( bool isPlaying, double now );
	bool				IsPlaying() const		{ return playing; }
	void				SetTrack( const TrackInfo& info, double now );
	void				SetArtwork( bool hasArtwork, const ArtworkColours* colours, double now );
	void				Pulse( const uint8_t ( *spectrum )[kSpectrumEntries], int spectrumChannels,
							   const uint8_t ( *waveform )[kWaveformEntries], int waveformChannels,
							   uint32_t positionMS, double now );
	void				NoteFrameDrawn( double now );

	// keyboard

	bool				HandleKey( uint32_t character, double now );

	// presets

	const std::vector<Dictionary>&	Presets() const			{ return presets; }
	void				SetPresets( const std::vector<Dictionary>& p, int current );
	int					CurrentPreset() const				{ return currentPreset; }
	int					SavePreset( double now );			// returns its number (1-based)
	bool				ApplyPreset( int number, double now );	// 1-based
	void				CyclePreset( double now );
	void				ClearPresets( double now );

	// what to draw

	int					Bands() const			{ return bandMap.Bands(); }
	double				BarValue( int ch, int band ) const	{ return bars[ch][band].Value(); }
	double				BarPeak( int ch, int band ) const	{ return bars[ch][band].Peak(); }
	double				VUValue( int ch ) const				{ return vuBars[ch].Value(); }
	double				VUPeak( int ch ) const				{ return vuBars[ch].Peak(); }
	double				NeedlePosition( int ch ) const		{ return needles[ch].Position(); }
	bool				PeakLEDLit( int ch ) const			{ return needles[ch].PeakLit(); }

	const Palette&		CurrentPalette() const	{ return palette; }
	uint32_t			PaletteSerial() const	{ return paletteSerial; }

	std::string			TrackText() const;
	double				TextOpacity( double now ) const;

	bool				HasArtwork() const		{ return hasArtwork; }
	uint32_t			ArtworkSerial() const	{ return artworkSerial; }
	CoverArtState		CoverArt( double now ) const;

	double				ProgressFraction() const;
	std::string			ElapsedText() const;
	std::string			TotalText() const;

	std::string			FeedbackText() const	{ return feedback; }
	double				FeedbackOpacity( double now ) const;

	bool				DiagnosticsVisible() const	{ return showDiagnostics; }
	void				SetDiagnosticsVisible( bool show )	{ showDiagnostics = show; }
	std::vector<std::string>	DiagnosticLines() const;

	// true while anything on screen is still moving; the host lowers the pulse rate otherwise

	bool				IsAnimating( double now ) const;

private:
	void				Changed( double now, bool layoutAffected );
	void				UpdatePalette( double now );
	void				SetFeedback( const std::string& text, double now );
	void				ResetMeters();
	void				Toggle( bool* flag, const char* onText, const char* offText, double now, bool layoutAffected );
	void				ToggleInfoField( int bit, const char* onText, const char* offText, double now );

	EngineHost*			host;
	Settings			settings;
	BandMap				bandMap;
	BarMeter			bars[2][kMaxBands];
	BarMeter			vuBars[2];
	NeedleMeter			needles[2];
	bool				playing;

	TrackInfo			track;
	double				textChangedAt;
	int					savedInfoMask;
	uint32_t			positionMS;
	double				positionAt;

	bool				hasArtwork;
	bool				hasArtworkColours;
	ArtworkColours		artworkColours;
	double				artworkAt;
	uint32_t			artworkSerial;

	Palette				palette;
	uint32_t			paletteSerial;
	double				animationStart;
	uint32_t			randomSeed;
	uint32_t			layoutSerial;

	std::string			feedback;
	double				feedbackAt;

	std::vector<Dictionary>	presets;
	int					currentPreset;

	// diagnostics

	bool				showDiagnostics;
	std::string			hostName;
	uint32_t			hostVersion, apiMajor, apiMinor;
	double				sampleRate;
	uint32_t			audioChannels;
	double				windowStart;
	int					pulses, dataPulses, frames;
	double				spectrumSum[2], waveformRMSSum[2];
	int					spectrumMax[2];
	int					waveformPulses;
	double				pulseRate, dataRate, frameRate, spectrumMean[2], waveformRMS[2];
	int					spectrumPeakEntry, peakEntryVotes[kSpectrumEntries];
	bool				vuFromWaveform;
};

}	// namespace led

#endif
