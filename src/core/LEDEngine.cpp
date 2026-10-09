/*
 *  LEDEngine.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDEngine.h"
#include <stdio.h>
#include <string.h>
#include <algorithm>


namespace led
{

Engine::Engine( EngineHost* theHost )
	: host( theHost ), bandMap( 18 ), playing( false ), textChangedAt( -1e9 ), savedInfoMask( kInfoTitle | kInfoArtist ),
	  positionMS( 0 ), positionAt( 0 ), hasArtwork( false ), hasArtworkColours( false ), artworkAt( -1e9 ), artworkSerial( 0 ),
	  paletteSerial( 1 ), animationStart( 0 ), randomSeed( 1 ), layoutSerial( 1 ), feedbackAt( -1e9 ), currentPreset( 0 ),
	  showDiagnostics( false ), hostVersion( 0 ), apiMajor( 0 ), apiMinor( 0 ), sampleRate( 0 ), audioChannels( 0 ),
	  windowStart( -1 ), pulses( 0 ), dataPulses( 0 ), frames( 0 ), waveformPulses( 0 ), pulseRate( 0 ), dataRate( 0 ),
	  frameRate( 0 ), spectrumPeakEntry( -1 ), vuFromWaveform( false )
{
	artworkColours = AnalyseArtwork( NULL, 0, 0, 0 );

	for ( int c = 0; c < 2; c++ )
	{
		spectrumSum[c] = waveformRMSSum[c] = spectrumMean[c] = waveformRMS[c] = 0;
		spectrumMax[c] = 0;
	}
	memset( peakEntryVotes, 0, sizeof( peakEntryVotes ));

	settings.Validate();
	bandMap = BandMap( settings.numberOfSpectrumBars );
	palette = Palette::FromSettings( settings );
}


// ---------------------------------------------------------------------------------------------
// settings

void		Engine::SettingsEdited( double now )
{
	Changed( now, true );
}


void		Engine::Changed( double now, bool layoutAffected )
{
	settings.Validate();

	if ( bandMap.Bands() != settings.numberOfSpectrumBars )
	{
		bandMap = BandMap( settings.numberOfSpectrumBars );
		ResetMeters();
	}

	if ( layoutAffected )
		layoutSerial++;

	UpdatePalette( now );

	if ( host )
		host->SettingsDidChange();
}


void		Engine::ResetMeters()
{
	for ( int c = 0; c < 2; c++ )
	{
		for ( int b = 0; b < kMaxBands; b++ )
			bars[c][b].Reset();
		vuBars[c].Reset();
	}
}


void		Engine::UpdatePalette( double now )
{
	Palette p = Palette::FromSettings( settings );

	if ( settings.coverArtColours && hasArtwork && hasArtworkColours )
		p = PaletteFromArtwork( artworkColours, p );
	else if ( settings.animateColours )
		p = AnimatePalette( p, floor(( now - animationStart ) * 4.0 ) / 4.0 );	// step 4 times a second

	if ( p != palette )
	{
		palette = p;
		paletteSerial++;
	}
}


// ---------------------------------------------------------------------------------------------
// host events

void		Engine::SetHostInfo( const std::string& name, uint32_t appVersion, uint32_t major, uint32_t minor )
{
	hostName = name;
	hostVersion = appVersion;
	apiMajor = major;
	apiMinor = minor;
}


void		Engine::SetAudioFormat( double rate, uint32_t channels )
{
	sampleRate = rate;
	audioChannels = channels;
}


void		Engine::SetPlaying( bool isPlaying, double now )
{
	playing = isPlaying;

	if ( ! playing )
		positionAt = now;
}


void		Engine::SetTrack( const TrackInfo& info, double now )
{
	if ( info == track && textChangedAt > -1e8 )
		return;

	bool newTrack = ( info.title != track.title || info.artist != track.artist || info.album != track.album );

	track = info;
	textChangedAt = now;

	if ( newTrack && settings.randomiseColours && ! ( settings.coverArtColours && hasArtwork ))
	{
		RandomPalette( Palette::FromSettings( settings ), randomSeed++ ).ApplyToSettings( &settings );
		Changed( now, false );
	}
}


void		Engine::SetArtwork( bool has, const ArtworkColours* colours, double now )
{
	hasArtwork = has;
	hasArtworkColours = ( colours != NULL );

	if ( colours )
		artworkColours = *colours;

	artworkAt = now;
	artworkSerial++;
	UpdatePalette( now );
}


void		Engine::Pulse( const uint8_t ( *spectrum )[kSpectrumEntries], int spectrumChannels,
						   const uint8_t ( *waveform )[kWaveformEntries], int waveformChannels,
						   uint32_t position, double now )
{
	if ( spectrum && spectrumChannels <= 0 )
		spectrum = NULL;
	if ( waveform && waveformChannels <= 0 )
		waveform = NULL;

	if ( playing )
	{
		positionMS = position;
		positionAt = now;
	}

	BarParams bp = { settings.expDecay, settings.barDecayTime, settings.peakHoldTime, settings.peakDecayTime };
	BarParams vp = bp;

	// spectrum bars

	const int bands = bandMap.Bands();
	double raw[kMaxBands];

	for ( int c = 0; c < 2; c++ )
	{
		if ( spectrum )
		{
			const uint8_t* data = spectrum[ std::min( c, spectrumChannels - 1 ) ];
			BinSpectrum( data, bandMap, settings.spectrumGain, settings.binUsingPeak, raw );
		}
		else
			std::fill( raw, raw + bands, 0.0 );

		for ( int b = 0; b < bands; b++ )
			bars[c][b].Update( ResponseCurve( raw[b], settings.logResponse ), now, bp );
	}

	// VU: from the waveform when the host sends one, otherwise from the spectrum

	double rms[2] = { 0, 0 };
	bool haveWaveform = false;

	if ( waveform )
	{
		for ( int c = 0; c < 2; c++ )
		{
			const uint8_t* w = waveform[ std::min( c, waveformChannels - 1 ) ];

			if ( ! WaveformIsSilent( w ))
				haveWaveform = true;
			rms[c] = WaveformRMS( w );
		}
	}

	if ( ! haveWaveform && spectrum )
	{
		// the mean spectrum level of loud music sits around 0.3 - scale that to roughly 0 VU

		for ( int c = 0; c < 2; c++ )
			rms[c] = SpectrumLevel( spectrum[ std::min( c, spectrumChannels - 1 ) ], 1.0 ) * ( kVUReferenceRMS / 0.3 );
	}

	vuFromWaveform = haveWaveform;

	for ( int c = 0; c < 2; c++ )
	{
		vuBars[c].Update( VUBargraphFraction( rms[c], settings.spectrumGain, settings.logResponse ), now, vp );
		needles[c].Update( VUFraction( rms[c], settings.vuMeterGain ), now, settings.vuDecayTime );
	}

	UpdatePalette( now );

	// diagnostics, measured over one second windows

	if ( windowStart < 0 || now < windowStart )
		windowStart = now;

	pulses++;

	if ( spectrum )
	{
		dataPulses++;

		int best = 0, bestValue = -1;

		for ( int c = 0; c < 2; c++ )
		{
			const uint8_t* data = spectrum[ std::min( c, spectrumChannels - 1 ) ];

			for ( int k = 0; k < kSpectrumEntries; k++ )
			{
				spectrumSum[c] += data[k];
				spectrumMax[c] = std::max( spectrumMax[c], (int) data[k] );

				if ( k > 0 && data[k] > bestValue )
				{
					bestValue = data[k];
					best = k;
				}
			}
		}

		if ( bestValue > 0 )
			peakEntryVotes[best]++;
	}

	if ( haveWaveform )
	{
		waveformPulses++;
		waveformRMSSum[0] += rms[0];
		waveformRMSSum[1] += rms[1];
	}

	double elapsed = now - windowStart;

	if ( elapsed >= 1.0 )
	{
		pulseRate = pulses / elapsed;
		dataRate = dataPulses / elapsed;
		frameRate = frames / elapsed;

		for ( int c = 0; c < 2; c++ )
		{
			spectrumMean[c] = dataPulses? spectrumSum[c] / ( (double) dataPulses * kSpectrumEntries ) : 0;
			waveformRMS[c] = waveformPulses? waveformRMSSum[c] / waveformPulses : 0;
			spectrumSum[c] = waveformRMSSum[c] = 0;
		}

		int votes = 0;
		spectrumPeakEntry = -1;

		for ( int k = 0; k < kSpectrumEntries; k++ )
		{
			if ( peakEntryVotes[k] > votes )
			{
				votes = peakEntryVotes[k];
				spectrumPeakEntry = k;
			}
		}

		memset( peakEntryVotes, 0, sizeof( peakEntryVotes ));
		pulses = dataPulses = frames = waveformPulses = 0;
		windowStart = now;
	}
}


void		Engine::NoteFrameDrawn( double now )
{
	frames++;
}


// ---------------------------------------------------------------------------------------------
// what to draw

std::string	Engine::TrackText() const
{
	return ComposeTrackText( track, settings.trackInfoMask );
}


double		Engine::TextOpacity( double now ) const
{
	if ( settings.trackInfoMask == 0 || TrackText().empty())
		return 0;

	if ( settings.keepTextVisible )
		return 1;

	double t = now - textChangedAt;

	if ( t < 0 )
		return 1;
	if ( t < kTextDisplayTime )
		return 1;
	if ( t < kTextDisplayTime + kFadeTime )
		return 1.0 - ( t - kTextDisplayTime ) / kFadeTime;
	return 0;
}


CoverArtState	Engine::CoverArt( double now ) const
{
	CoverArtState s = { 0, 1 };

	if ( ! hasArtwork || ! settings.coverArt )
		return s;

	double t = now - artworkAt;
	bool bg = settings.coverArtBackgroundEffect;

	if ( t < kCoverDisplayTime )
	{
		s.opacity = 1;
		s.centred = 1;
	}
	else if ( t < kCoverDisplayTime + kFadeTime )
	{
		double f = ( t - kCoverDisplayTime ) / kFadeTime;

		s.centred = bg? 1.0 - f : 1.0;
		s.opacity = bg? 1.0 - f * ( 1.0 - kCoverBackgroundOpacity ) : 1.0 - f;
	}
	else
	{
		s.centred = bg? 0 : 1;
		s.opacity = bg? kCoverBackgroundOpacity : 0;
	}
	return s;
}


double		Engine::ProgressFraction() const
{
	if ( track.totalTimeMS == 0 )
		return 0;

	return clamp( positionMS / (double) track.totalTimeMS, 0.0, 1.0 );
}


std::string	Engine::ElapsedText() const
{
	return FormatTime( positionMS / 1000.0 );
}


std::string	Engine::TotalText() const
{
	return track.totalTimeMS? FormatTime( track.totalTimeMS / 1000.0 ) : "";
}


double		Engine::FeedbackOpacity( double now ) const
{
	if ( feedback.empty())
		return 0;

	double t = now - feedbackAt;

	if ( t < 0 || t >= kFeedbackTime )
		return 0;
	if ( t < kFeedbackTime - kFadeTime )
		return 1;
	return ( kFeedbackTime - t ) / kFadeTime;
}


static inline bool	InWindow( double t, double start, double length )
{
	return t >= start - 0.15 && t < start + length + 0.15;
}


bool		Engine::IsAnimating( double now ) const
{
	// only things that actually change on screen count: text and artwork that is merely showing
	// doesn't need frames, only its fades do
	
	if ( playing || showDiagnostics || settings.animateColours )
		return true;
	
	if ( ! settings.keepTextVisible && InWindow( now - textChangedAt, kTextDisplayTime, kFadeTime ))
		return true;
	
	if ( hasArtwork && settings.coverArt && InWindow( now - artworkAt, kCoverDisplayTime, kFadeTime ))
		return true;
	
	if ( ! feedback.empty() && InWindow( now - feedbackAt, kFeedbackTime - kFadeTime, kFadeTime ))
		return true;
	
	for ( int c = 0; c < 2; c++ )
	{
		if ( vuBars[c].Value() > 0 || vuBars[c].Peak() > 0 )
			return true;
		if ( needles[c].Position() > 0.002 || needles[c].PeakLit())
			return true;
		for ( int b = 0; b < bandMap.Bands(); b++ )
			if ( bars[c][b].Value() > 0 || bars[c][b].Peak() > 0 )
				return true;
	}
	return false;
}


std::vector<std::string>	Engine::DiagnosticLines() const
{
	std::vector<std::string> lines;
	char buf[256];

	snprintf( buf, sizeof( buf ), "%.2f fps   pulses %.1f/s (%.1f/s with spectrum data)", frameRate, pulseRate, dataRate );
	lines.push_back( buf );

	snprintf( buf, sizeof( buf ), "host: %s  version %X.%X.%X  plug-in API %u.%u", hostName.c_str(),
			  ( hostVersion >> 24 ) & 0xFF, ( hostVersion >> 20 ) & 0x0F, ( hostVersion >> 16 ) & 0x0F, apiMajor, apiMinor );
	lines.push_back( buf );

	if ( sampleRate > 0 )
		snprintf( buf, sizeof( buf ), "audio: %.0f Hz, %u channels", sampleRate, audioChannels );
	else
		snprintf( buf, sizeof( buf ), "audio: format not reported" );
	lines.push_back( buf );

	snprintf( buf, sizeof( buf ), "spectrum: mean L %.1f R %.1f  max L %d R %d (0-255)  loudest entry %d (~%.0f Hz)",
			  spectrumMean[0], spectrumMean[1], spectrumMax[0], spectrumMax[1], spectrumPeakEntry,
			  spectrumPeakEntry >= 0? 20.0 + spectrumPeakEntry * kHzPerEntry : 0.0 );
	lines.push_back( buf );

	snprintf( buf, sizeof( buf ), "waveform: RMS L %.3f R %.3f   VU source: %s", waveformRMS[0], waveformRMS[1],
			  vuFromWaveform? "waveform" : "spectrum (no waveform data)" );
	lines.push_back( buf );

	snprintf( buf, sizeof( buf ), "bands %d  response %s  binning %s  spectrum gain %.2f  VU gain %.2f",
			  bandMap.Bands(), settings.logResponse? "log" : "linear", settings.binUsingPeak? "peak" : "average",
			  settings.spectrumGain, settings.vuMeterGain );
	lines.push_back( buf );

	return lines;
}


// ---------------------------------------------------------------------------------------------
// keyboard - the 3.0.7 shortcuts and feedback strings

void		Engine::SetFeedback( const std::string& text, double now )
{
	feedback = text;
	feedbackAt = now;
}


void		Engine::Toggle( bool* flag, const char* onText, const char* offText, double now, bool layoutAffected )
{
	*flag = ! *flag;
	SetFeedback( *flag? onText : offText, now );
	Changed( now, layoutAffected );
}


void		Engine::ToggleInfoField( int bit, const char* onText, const char* offText, double now )
{
	settings.trackInfoMask ^= bit;
	SetFeedback(( settings.trackInfoMask & bit )? onText : offText, now );
	textChangedAt = now;		// reshow the text so the change can be seen
	Changed( now, false );
}


bool		Engine::HandleKey( uint32_t ch, double now )
{
	if ( ch >= 'A' && ch <= 'Z' )
		ch = ch - 'A' + 'a';

	char buf[96];

	switch ( ch )
	{
		case 'p':	Toggle( &settings.showProgress, "P - Show Progress Bar", "P - Hide Progress Bar", now, true ); return true;
		case 'v':	Toggle( &settings.showVU, "V - Show VU Meters", "V - Hide VU Meters", now, true ); return true;
		case 't':	Toggle( &settings.textAbove, "T - Place Track Info Above", "T - Place Track Info Below", now, true ); return true;
		case 'k':	Toggle( &settings.peakIndicatorsEnabled, "K - Show Peak Indicators", "K - Hide Peak Indicators", now, false ); return true;
		case 'b':	Toggle( &settings.blendEnabled, "B - Show Blend Colour", "B - Hide Blend Colour", now, false ); return true;
		case 'm':	animationStart = now; Toggle( &settings.animateColours, "M - Animate Colours", "M - Do Not Animate Colours", now, false ); return true;
		case 'l':	Toggle( &settings.scalesVisible, "L - Show Scale Labels", "L - Hide Scale Labels", now, true ); return true;
		case 'u':	Toggle( &settings.unlitSegments, "U - Show Unlit Segments", "U - Hide Unlit Segments", now, false ); return true;
		case 'f':	Toggle( &settings.reflections, "F - Show Reflections", "F - Hide Reflections", now, true ); return true;
		case 'h':	settings.perspective = ! settings.perspective; SetFeedback( "H - Change Perspective", now ); Changed( now, true ); return true;
		case 'c':
			Toggle( &settings.coverArt, "C - Show Cover Art", "C - Hide Cover Art", now, false );
			if ( settings.coverArt )
				artworkAt = now;		// cycling "Show" reshows the artwork in the centre
			return true;

		case 'n':
			settings.logResponse = ! settings.logResponse;
			SetFeedback( settings.logResponse? "N - Logarithmic Response" : "N - Linear Response", now );
			Changed( now, true );
			return true;

		case 'x':
			settings.CycleLayout();
			SetFeedback( "X - Cycle Layout", now );
			Changed( now, true );
			return true;

		case '.':
		case '>':
			settings.CycleNumberOfBars();
			snprintf( buf, sizeof( buf ), "> - Cycle Number Of Bars %d", settings.numberOfSpectrumBars );
			SetFeedback( buf, now );
			Changed( now, true );
			return true;

		case 'i':
			if ( settings.trackInfoMask != 0 )
			{
				savedInfoMask = settings.trackInfoMask;
				settings.trackInfoMask = 0;
				SetFeedback( "I - Hide Track Info", now );
			}
			else
			{
				settings.trackInfoMask = savedInfoMask? savedInfoMask : ( kInfoTitle | kInfoArtist );
				textChangedAt = now;
				SetFeedback( "I - Show Track Info", now );
			}
			Changed( now, false );
			return true;

		case 's':	ToggleInfoField( kInfoTitle, "S - Show Song Title", "S - Hide Song Title", now ); return true;
		case 'r':	ToggleInfoField( kInfoArtist, "R - Show Artist", "R - Hide Artist", now ); return true;
		case 'a':	ToggleInfoField( kInfoAlbum, "A - Show Album", "A - Hide Album", now ); return true;
		case 'y':	ToggleInfoField( kInfoYear, "Y - Show Year", "Y - Hide Year", now ); return true;

		case 'd':
			if ( host )
				host->OpenOptions();
			return true;

		case 'z':
		{
			int n = SavePreset( now );
			snprintf( buf, sizeof( buf ), "Z - Saved Preset %d", n );
			SetFeedback( buf, now );
			return true;
		}

		case '/':
			CyclePreset( now );
			return true;

		case '=':
			showDiagnostics = ! showDiagnostics;
			SetFeedback( "= - Toggle frame rate", now );
			return true;

		case '1': case '2': case '3': case '4': case '5':
		case '6': case '7': case '8': case '9': case '0':
		{
			int n = ( ch == '0' )? 10 : (int)( ch - '0' );

			if ( ApplyPreset( n, now ))
			{
				snprintf( buf, sizeof( buf ), "Applied Preset %d", n );
				SetFeedback( buf, now );
				return true;
			}
			return false;
		}
	}

	return false;
}


// ---------------------------------------------------------------------------------------------
// presets

void		Engine::SetPresets( const std::vector<Dictionary>& p, int current )
{
	presets = p;

	if ( presets.size() > (size_t) kMaxPresets )
		presets.resize( kMaxPresets );

	currentPreset = clamp( current, 0, (int) presets.size());
}


int			Engine::SavePreset( double now )
{
	if ( presets.size() >= (size_t) kMaxPresets )
	{
		// full: overwrite the current one (or the last)

		int slot = currentPreset > 0? currentPreset : kMaxPresets;
		presets[ slot - 1 ] = settings.ToDictionary();
		currentPreset = slot;
	}
	else
	{
		presets.push_back( settings.ToDictionary());
		currentPreset = (int) presets.size();
	}

	if ( host )
		host->PresetsDidChange();

	return currentPreset;
}


bool		Engine::ApplyPreset( int number, double now )
{
	if ( number < 1 || number > (int) presets.size())
		return false;

	settings.FromDictionary( presets[ number - 1 ] );
	currentPreset = number;

	if ( host )
		host->PresetsDidChange();

	Changed( now, true );
	return true;
}


void		Engine::CyclePreset( double now )
{
	if ( presets.empty())
		return;

	int next = ( currentPreset % (int) presets.size()) + 1;

	if ( ApplyPreset( next, now ))
	{
		char buf[64];
		snprintf( buf, sizeof( buf ), "/ - Applied Preset %d", next );
		SetFeedback( buf, now );
	}
}


void		Engine::ClearPresets( double now )
{
	presets.clear();
	currentPreset = 0;
	SetFeedback( "All Presets Deleted", now );

	if ( host )
		host->PresetsDidChange();
}

}	// namespace led
