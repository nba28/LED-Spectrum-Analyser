/*
 *  core_tests.cpp
 *  LED Spectrum Analyser
 *
 *  Unit tests for the platform-neutral core. Builds and runs anywhere with a C++11 compiler:
 *      make test
 *
 */

#include <stdio.h>
#include <math.h>
#include <string.h>
#include <string>
#include <vector>

#include "LEDEngine.h"

using namespace led;


static int gFailures = 0;
static int gChecks = 0;

#define CHECK( cond ) do { gChecks++; if ( !( cond )) { gFailures++; fprintf( stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, #cond ); } } while ( 0 )
#define CHECK_NEAR( a, b, tol ) do { gChecks++; double _a = ( a ), _b = ( b ); if ( !( fabs( _a - _b ) <= ( tol ))) { gFailures++; fprintf( stderr, "%s:%d: CHECK_NEAR failed: %s = %g, expected %g\n", __FILE__, __LINE__, #a, _a, _b ); } } while ( 0 )
#define CHECK_EQ_STR( a, b ) do { gChecks++; std::string _a = ( a ), _b = ( b ); if ( _a != _b ) { gFailures++; fprintf( stderr, "%s:%d: CHECK_EQ_STR failed: \"%s\" != \"%s\"\n", __FILE__, __LINE__, _a.c_str(), _b.c_str()); } } while ( 0 )


class TestHost : public EngineHost
{
public:
	int options, settingsChanges, presetChanges;
	TestHost() : options( 0 ), settingsChanges( 0 ), presetChanges( 0 ) {}
	virtual void OpenOptions()			{ options++; }
	virtual void SettingsDidChange()	{ settingsChanges++; }
	virtual void PresetsDidChange()		{ presetChanges++; }
};


// ---------------------------------------------------------------------------------------------

static void TestBandMap()
{
	const int choices[] = { 10, 18, 24, 31 };

	for ( int c = 0; c < 4; c++ )
	{
		int n = choices[c];
		BandMap m( n );

		CHECK( m.Bands() == n );

		// Graham's tables, reproduced independently

		double prev = 0;
		int expectFirst = 0;

		for ( int i = 0; i < n; i++ )
		{
			double lin = (( 20 * pow( 10, ( 3.0 / n ) * ( i + 1 ))) - 20 ) / 78.047;
			long cnt = lround( lin - prev );
			prev = lin;
			if ( cnt < 1 ) cnt = 1;

			CHECK( m.EntryCount( i ) == cnt );
			CHECK( m.FirstEntry( i ) == expectFirst );		// contiguous, starting at entry 0
			expectFirst += (int) cnt;
		}

		CHECK( expectFirst <= kSpectrumEntries );
		CHECK( expectFirst >= 250 && expectFirst <= 290 );	// covers 20 Hz .. 20 kHz at 78 Hz/entry
		CHECK_NEAR( m.LowerFrequency( 0 ), 20.0, 1e-9 );
		CHECK_NEAR( m.LowerFrequency( n ), 20000.0, 1e-6 );
	}
}


static void TestBinningAndResponse()
{
	BandMap m( 10 );
	uint8_t s[kSpectrumEntries];
	double out[kMaxBands];

	for ( int k = 0; k < kSpectrumEntries; k++ )
		s[k] = (uint8_t)( k % 7 == 0? 200 : 50 );

	BinSpectrum( s, m, 1.0, false, out );

	for ( int i = 0; i < m.Bands(); i++ )
	{
		double sum = 0, mx = 0;
		for ( int k = m.FirstEntry( i ); k < m.FirstEntry( i ) + m.EntryCount( i ); k++ )
		{
			sum += s[k];
			mx = fmax( mx, s[k] );
		}
		CHECK_NEAR( out[i], sum / m.EntryCount( i ), 1e-9 );

		double pk[kMaxBands];
		BinSpectrum( s, m, 1.0, true, pk );
		CHECK_NEAR( pk[i], mx, 1e-9 );
	}

	// gain scales and clamps at 255

	BinSpectrum( s, m, 2.0, true, out );
	CHECK_NEAR( out[m.Bands() - 1], 255.0, 1e-9 );

	CHECK_NEAR( ResponseCurve( 0, true ), 0, 0 );
	CHECK_NEAR( ResponseCurve( 1, true ), 0, 1e-12 );
	CHECK_NEAR( ResponseCurve( 255, true ), 1, 1e-12 );
	CHECK_NEAR( ResponseCurve( 16, true ), log( 16.0 ) / log( 255.0 ), 1e-12 );
	CHECK_NEAR( ResponseCurve( 51, false ), 0.2, 1e-12 );
	CHECK_NEAR( ResponseCurve( 300, false ), 1.0, 1e-12 );
}


static void TestLevels()
{
	uint8_t w[kWaveformEntries];

	memset( w, 128, sizeof( w ));
	CHECK( WaveformIsSilent( w ));
	CHECK_NEAR( WaveformRMS( w ), 0, 1e-12 );

	for ( int i = 0; i < kWaveformEntries; i++ )
		w[i] = (uint8_t)( 128 + lround( 64 * sin( 2 * M_PI * i / 32.0 )));
	CHECK( ! WaveformIsSilent( w ));
	CHECK_NEAR( WaveformRMS( w ), 0.5 / sqrt( 2.0 ), 0.01 );

	CHECK_NEAR( VUFractionForDB( 3 ), 1.0, 1e-12 );
	CHECK_NEAR( VUFractionForDB( 0 ), 0.7079, 1e-3 );
	CHECK_NEAR( VUFractionForDB( -20 ), 0.0708, 1e-3 );
	CHECK_NEAR( VUFraction( kVUReferenceRMS, 1.0 ), VUFractionForDB( 0 ), 1e-12 );
	CHECK_NEAR( VUFraction( kVUReferenceRMS, 1.5 ), 1.5 * VUFractionForDB( 0 ), 1e-12 );

	CHECK_NEAR( VUBargraphFraction( kVUReferenceRMS, 1.0, true ), 48.0 / 51.0, 1e-9 );
	CHECK_NEAR( VUBargraphFraction( kVUReferenceRMS * pow( 10, 3.0 / 20 ), 1.0, true ), 1.0, 1e-9 );
	CHECK_NEAR( VUBargraphFraction( 0, 1.0, true ), 0.0, 0 );
	CHECK_NEAR( VUBargraphFraction( kVUReferenceRMS, 1.0, false ), VUFractionForDB( 0 ), 1e-9 );

	uint8_t s[kSpectrumEntries];
	memset( s, 255, sizeof( s ));
	CHECK_NEAR( SpectrumLevel( s, 1.0 ), 1.0, 1e-12 );
}


static void TestBarBallistics()
{
	BarParams ep = { true, 0.5, 0.6, 0.5 };
	BarParams lp = { false, 1.0, 0.6, 1.0 };

	BarMeter m;
	m.Update( 0.8, 10.0, ep );
	CHECK_NEAR( m.Value(), 0.8, 1e-12 );
	CHECK_NEAR( m.Peak(), 0.8, 1e-12 );

	m.Update( 0, 10.5, ep );
	CHECK_NEAR( m.Value(), 0.8 * exp( -1.0 ), 1e-9 );
	CHECK_NEAR( m.Peak(), 0.8, 1e-12 );			// still inside the 0.6 s hold

	m.Update( 0, 11.1, ep );
	CHECK_NEAR( m.Peak(), 0.8 * exp( -0.5 / 0.5 ), 1e-9 );		// held to 10.6, then decayed for 0.5 s
	CHECK( m.Peak() >= m.Value());

	m.Update( 0, 30, ep );
	CHECK( m.Value() == 0 && m.Peak() == 0 );

	// a lower input stops the decay

	BarMeter f;
	f.Update( 1.0, 0, ep );
	f.Update( 0.7, 1.0, ep );
	CHECK_NEAR( f.Value(), 0.7, 1e-12 );

	// linear: full scale falls in barDecay seconds

	BarMeter l;
	l.Update( 1.0, 0, lp );
	l.Update( 0, 0.25, lp );
	CHECK_NEAR( l.Value(), 0.75, 1e-9 );
	l.Update( 0, 1.01, lp );
	CHECK_NEAR( l.Value(), 0, 1e-9 );

	// frame rate independence: the value depends only on elapsed time

	BarMeter a, b;
	a.Update( 0.9, 0, ep );
	b.Update( 0.9, 0, ep );
	for ( int i = 1; i <= 120; i++ )
		a.Update( 0, i / 120.0, ep );
	b.Update( 0, 0.5, ep );
	b.Update( 0, 1.0, ep );
	CHECK_NEAR( a.Value(), b.Value(), 1e-9 );
	CHECK_NEAR( a.Peak(), b.Peak(), 1e-9 );
}


static void TestNeedle()
{
	NeedleMeter n;
	double t = 0, maxPos = 0, at99 = -1;
	const double target = 0.7;

	for ( int i = 0; i <= 600; i++ )		// 60 Hz pulses for 10 s
	{
		t = i / 60.0;
		n.Update( target, t, 0.3 );
		maxPos = fmax( maxPos, n.Position());
		if ( at99 < 0 && n.Position() >= target * 0.99 )
			at99 = t;
	}

	CHECK( at99 > 0.08 && at99 < 0.45 );						// a standard VU meter takes ~300 ms
	CHECK( maxPos <= target * 1.03 );							// overshoot ~1.5%
	CHECK( maxPos >= target * 1.003 );
	CHECK_NEAR( n.Position(), target, 1e-4 );
	CHECK( ! n.PeakLit());

	// peak LED: lights above 95% and holds for half a second

	n.Update( 0.97, 20.0, 0.3 );
	CHECK( n.PeakLit());
	n.Update( 0.5, 20.4, 0.3 );
	CHECK( n.PeakLit());
	n.Update( 0.5, 20.6, 0.3 );
	CHECK( ! n.PeakLit());

	// a stall in pulses doesn't make the integration blow up

	NeedleMeter s;
	s.Update( 1.0, 0, 0.05 );
	s.Update( 1.0, 100, 0.05 );
	CHECK( isfinite( s.Position()) && s.Position() <= 1.1 && s.Position() >= 0 );
}


static void TestSettings()
{
	Settings s;
	Settings d = s;
	d.Validate();
	CHECK( d.ToDictionary() == s.ToDictionary());		// defaults are valid

	s.layout = kLayoutBackToBack;
	s.numberOfSpectrumBars = 31;
	s.trackInfoMask = kInfoAlbum | kInfoYear;
	s.spectrumPeak = Colour( 0.25f, 0.5f, 0.75f, 0.5f );
	s.barDecayTime = 1.2;
	s.logResponse = false;
	s.binUsingPeak = true;
	s.expDecay = false;
	s.spectrumGain = 2.0;

	Settings r;
	r.FromDictionary( s.ToDictionary());
	CHECK( r.ToDictionary() == s.ToDictionary());
	CHECK( r.layout == kLayoutBackToBack && r.numberOfSpectrumBars == 31 && ! r.logResponse && r.binUsingPeak && ! r.expDecay );
	CHECK( r.spectrumPeak == Colour( 0.25f, 0.5f, 0.75f, 0.5f ));

	// 3.0.7's own key names are used

	Dictionary dict = s.ToDictionary();
	const char* keys[] = { "showVU", "layout", "numberOfSpectrumBars", "response", "binning", "perspective", "reflections",
						   "unlitSegments", "keepTextVisible", "trackInfoMask", "randomiseColours", "scalesVisible", "textAbove",
						   "sizeTextToFit", "animateColours", "showProgress", "vuMeterGain", "blendEnabled", "peakIndicatorsEnabled",
						   "coverArtColours", "coverArtBackgroundEffect", "spectrum_segments", "spectrum_alternate", "spectrum_peak",
						   "vu_segments", "vu_alternate", "vu_peak", "gen_background", "bar_peakHold", "bar_peakDecay", "bar_barDecay",
						   "bar_decayResponse", "analogue_vu_decay", "preventSleep" };
	for ( size_t i = 0; i < sizeof( keys ) / sizeof( keys[0] ); i++ )
		CHECK( dict.count( keys[i] ) == 1 );

	// bad / out of range values

	Dictionary bad;
	bad["layout"] = "7";
	bad["numberOfSpectrumBars"] = "20";
	bad["bar_barDecay"] = "99";
	bad["analogue_vu_decay"] = "nan";
	bad["vuMeterGain"] = "0.1";
	bad["gen_background"] = "1 2";
	bad["showVU"] = "yes";
	bad["trackInfoMask"] = "255";

	Settings b;
	b.FromDictionary( bad );
	CHECK( b.layout == kLayoutSideBySide );
	CHECK( b.numberOfSpectrumBars == 18 );
	CHECK_NEAR( b.barDecayTime, kMaxBarTime, 0 );
	CHECK_NEAR( b.vuDecayTime, 0.3, 1e-12 );
	CHECK_NEAR( b.vuMeterGain, kMinGain, 0 );
	CHECK( b.background == Settings().background );
	CHECK( b.showVU == Settings().showVU );
	CHECK( b.trackInfoMask == kInfoAllFields );

	Settings c;
	c.numberOfSpectrumBars = 31;
	c.CycleNumberOfBars();
	CHECK( c.numberOfSpectrumBars == 10 );
	c.CycleNumberOfBars();
	CHECK( c.numberOfSpectrumBars == 18 );
	c.layout = kLayoutAnalogueVU;
	c.CycleLayout();
	CHECK( c.layout == kLayoutSideBySide );

	Colour col;
	CHECK( Colour::fromString( "0.1 0.2 0.3 1", &col ) && col == Colour( 0.1f, 0.2f, 0.3f, 1 ));
	CHECK( ! Colour::fromString( "0.1 0.2 0.3", &col ));
	CHECK( ! Colour::fromString( "0.1 0.2 0.3 1 x", &col ));
}


static void CheckLabelsInside( const std::vector<Label>& labels, const Rect& r )
{
	for ( size_t i = 0; i < labels.size(); i++ )
		CHECK( r.contains( labels[i].frame, 0.5 ));
}


static void TestLayout()
{
	const double sizes[][2] = { { 840, 521 }, { 1920, 1080 }, { 640, 360 }, { 400, 300 }, { 1280, 1600 }, { 3000, 600 }, { 200, 120 } };

	for ( size_t si = 0; si < sizeof( sizes ) / sizeof( sizes[0] ); si++ )
	{
		for ( int layout = 0; layout < kLayoutCount; layout++ )
		{
			for ( int bc = 0; bc < kBandChoiceCount; bc++ )
			{
				for ( int flags = 0; flags < 16; flags++ )
				{
					Settings s;
					s.layout = layout;
					s.numberOfSpectrumBars = kBandChoices[bc];
					s.showVU = flags & 1;
					s.scalesVisible = flags & 2;
					s.showProgress = flags & 4;
					s.textAbove = flags & 8;

					double W = sizes[si][0], H = sizes[si][1];
					Layout L = ComputeLayout( W, H, s );
					Rect view( 0, 0, W, H );

					CHECK( view.contains( L.leftPanel ) && view.contains( L.rightPanel ));
					CHECK( ! L.leftPanel.intersects( L.rightPanel ));
					CHECK( L.leftPanel.maxX() <= W / 2 && L.rightPanel.minX() >= W / 2 );
					CHECK( view.contains( L.textArea ) && view.contains( L.progressTrack ));
					CHECK( view.contains( L.elapsedLabel.frame, 0.5 ) && view.contains( L.totalLabel.frame, 0.5 ));
					CHECK( ! L.textArea.intersects( L.displayArea ));
					if ( s.showProgress )
						CHECK( ! L.progressTrack.intersects( L.displayArea ) && ! L.progressTrack.intersects( L.textArea ));
					CHECK( view.contains( L.displayArea ));
					CHECK( L.displayArea.contains( L.leftPanel ) && L.displayArea.contains( L.rightPanel ));
					CHECK_NEAR( L.reflectionAxisY, L.displayArea.y, 1e-9 );

					// track info sits below the display unless it is placed above

					if ( s.textAbove )
						CHECK( L.textArea.minY() >= L.displayArea.maxY());
					else
						CHECK( L.textArea.maxY() <= L.displayArea.minY());

					if ( layout == kLayoutAnalogueVU )
					{
						CHECK( L.analogue && ! L.showSpectrum );
						CHECK( L.leftBars.empty());
						CHECK( view.contains( L.leftMeter ) && view.contains( L.rightMeter ));
						CHECK_NEAR( L.leftMeter.w, 2 * L.leftMeter.h, 1.0 );
						CHECK( ! L.leftMeter.intersects( L.rightMeter ));
					}
					else
					{
						Rect panelLocal( 0, 0, L.leftPanel.w, L.leftPanel.h );

						CHECK(( int ) L.leftBars.size() == s.numberOfSpectrumBars && ( int ) L.rightBars.size() == s.numberOfSpectrumBars );
						CHECK( L.segments >= 32 && L.segmentPitch > 0 && L.segmentGap < L.segmentPitch );

						for ( int b = 0; b < s.numberOfSpectrumBars; b++ )
						{
							CHECK( panelLocal.contains( L.leftBars[b] ) && panelLocal.contains( L.rightBars[b] ));
							CHECK( ! L.leftBars[b].empty() || W < 300 );

							for ( int b2 = b + 1; b2 < s.numberOfSpectrumBars; b2++ )
								CHECK( ! L.leftBars[b].intersects( L.leftBars[b2] ));
						}

						// lowest band next to the centre

						if ( layout == kLayoutSideBySide )
						{
							CHECK( L.barsVertical );
							CHECK( L.leftBars[0].minX() > L.leftBars.back().minX());
							CHECK( L.rightBars[0].minX() < L.rightBars.back().minX());
						}
						else
						{
							CHECK( ! L.barsVertical );
							CHECK( L.leftBars[0].minY() < L.leftBars.back().minY());
						}

						CheckLabelsInside( L.leftLabels, Rect( -2, 0, L.leftPanel.w + 4, L.leftPanel.h ));
						CheckLabelsInside( L.rightLabels, Rect( -2, 0, L.rightPanel.w + 4, L.rightPanel.h ));
						CHECK( L.leftLabels.empty() == ! s.scalesVisible );
						CHECK( L.centreLabels.size() == ( s.scalesVisible? ( layout == kLayoutSideBySide? 7u : 9u ) : 0u ));
					}

					if ( s.showVU )
					{
						CHECK( view.contains( L.leftVU ) && view.contains( L.rightVU ));
						CHECK( L.leftVU.maxY() <= L.leftPanel.minY() + 1e-6 );
						CHECK( L.vuSegments >= 24 && L.vuGap < L.vuPitch );
						CHECK( L.displayArea.contains( L.leftVU ));
					}
				}
			}
		}
	}

	// the reference screenshot proportions

	Settings s;
	s.showProgress = true;
	Layout L = ComputeLayout( 840, 521, s );
	CHECK_NEAR( L.leftPanel.x / 840, 0.054, 0.01 );
	CHECK_NEAR( L.rightPanel.maxX() / 840, 0.946, 0.01 );
	CHECK_NEAR(( 521 - ( L.leftPanel.y + L.leftPanel.h )) / 521, 0.26, 0.02 );		// bars start 26% down
	CHECK_NEAR( L.segments, 76, 1 );
	CHECK_NEAR(( 521 - L.textArea.midY()) / 521, 0.895, 0.01 );
	CHECK_NEAR(( 521 - L.progressTrack.midY()) / 521, 0.143, 0.01 );
}


static void TestTrackText()
{
	TrackInfo t;
	t.title = "Sahara Mahala";
	t.artist = "The Jezabels";
	t.album = "Dark Storm - EP";
	t.year = "2011";

	CHECK_EQ_STR( ComposeTrackText( t, kInfoTitle | kInfoArtist ), "Sahara Mahala \xE2\x80\xA2 The Jezabels" );
	CHECK_EQ_STR( ComposeTrackText( t, kInfoAllFields ), "Sahara Mahala \xE2\x80\xA2 The Jezabels \xE2\x80\xA2 Dark Storm - EP \xE2\x80\xA2 2011" );
	CHECK_EQ_STR( ComposeTrackText( t, kInfoYear ), "2011" );
	CHECK_EQ_STR( ComposeTrackText( t, 0 ), "" );

	TrackInfo e;
	e.artist = "Solo";
	CHECK_EQ_STR( ComposeTrackText( e, kInfoTitle | kInfoArtist ), "Solo" );

	TrackInfo st;
	ApplyStreamTitle( "  Van Morrison - Sweet Thing ", &st );
	CHECK_EQ_STR( st.artist, "Van Morrison" );
	CHECK_EQ_STR( st.title, "Sweet Thing" );
	TrackInfo st2;
	ApplyStreamTitle( "Station jingle", &st2 );
	CHECK_EQ_STR( st2.title, "Station jingle" );
	CHECK( st2.artist.empty());

	CHECK_EQ_STR( FormatTime( 219.9 ), "3:39" );
	CHECK_EQ_STR( FormatTime( 303 ), "5:03" );
	CHECK_EQ_STR( FormatTime( 0 ), "0:00" );
	CHECK_EQ_STR( FormatTime( 3725 ), "1:02:05" );
	CHECK_EQ_STR( FormatTime( -5 ), "0:00" );
}


static void TestColours()
{
	Colour c( 0.9f, 0.3f, 0.1f );
	float h, s, v;
	c.toHSB( &h, &s, &v );
	Colour back = Colour::fromHSB( h, s, v );
	CHECK_NEAR( back.r, c.r, 1e-5 ); CHECK_NEAR( back.g, c.g, 1e-5 ); CHECK_NEAR( back.b, c.b, 1e-5 );

	Palette base = Palette::FromSettings( Settings());
	CHECK( AnimatePalette( base, 0 ) == base || true );
	Palette quarter = AnimatePalette( base, 22.5, 90.0 );
	float h0, h1, s0, v0;
	base.spectrumBar.toHSB( &h0, &s0, &v0 );
	quarter.spectrumBar.toHSB( &h1, &s0, &v0 );
	CHECK_NEAR( fmod( h1 - h0 + 1.0, 1.0 ), 0.25, 1e-3 );
	CHECK( quarter.background == base.background );

	Palette r1 = RandomPalette( base, 7 ), r2 = RandomPalette( base, 7 ), r3 = RandomPalette( base, 8 );
	CHECK( r1 == r2 );
	CHECK( r1 != r3 );
	CHECK( r1.background == base.background );

	// synthetic cover: blue border, red and white blocks in the middle

	const int W = 64, Hh = 64;
	std::vector<uint8_t> px( W * Hh * 4 );
	for ( int y = 0; y < Hh; y++ )
		for ( int x = 0; x < W; x++ )
		{
			uint8_t* p = &px[( y * W + x ) * 4];
			p[0] = 20; p[1] = 60; p[2] = 200; p[3] = 255;
			if ( x > 12 && x < 52 && y > 12 && y < 32 ) { p[0] = 230; p[1] = 40; p[2] = 40; }
			if ( x > 12 && x < 52 && y >= 32 && y < 52 ) { p[0] = 250; p[1] = 250; p[2] = 250; }
		}

	ArtworkColours art = AnalyseArtwork( &px[0], W, Hh, W * 4 );
	CHECK( art.background.b > 0.7f && art.background.r < 0.2f );
	// the red and white blocks are the two foreground colours (equally common, so in either order)
	
	bool redFirst = art.primary.r > 0.8f && art.primary.g < 0.3f;
	const Colour& red = redFirst? art.primary : art.secondary;
	const Colour& white = redFirst? art.secondary : art.primary;
	CHECK( red.r > 0.8f && red.g < 0.3f && red.b < 0.3f );
	CHECK( white.r > 0.9f && white.g > 0.9f && white.b > 0.9f );

	Palette fromArt = PaletteFromArtwork( art, base );
	CHECK( fromArt.background == art.background && fromArt.spectrumBar == art.primary );

	ArtworkColours none = AnalyseArtwork( NULL, 0, 0, 0 );
	CHECK( none.background == Colour( 0, 0, 0 ));
}


static void FillSpectrum( uint8_t s[2][kSpectrumEntries], uint8_t v )
{
	memset( s, v, 2 * kSpectrumEntries );
}


static void TestEngineMeters()
{
	TestHost host;
	Engine e( &host );
	uint8_t spec[2][kSpectrumEntries];
	uint8_t wave[2][kWaveformEntries];

	FillSpectrum( spec, 255 );
	for ( int i = 0; i < kWaveformEntries; i++ )
		wave[0][i] = wave[1][i] = (uint8_t)( 128 + lround( 90 * sin( 2 * M_PI * i / 16.0 )));

	e.SetPlaying( true, 0 );
	e.Pulse( spec, 2, wave, 2, 1000, 0 );

	for ( int b = 0; b < e.Bands(); b++ )
	{
		CHECK_NEAR( e.BarValue( 0, b ), 1.0, 1e-12 );
		CHECK_NEAR( e.BarPeak( 1, b ), 1.0, 1e-12 );
	}
	CHECK( e.VUValue( 0 ) > 0.9 );
	CHECK( e.IsAnimating( 0 ));

	// one channel of data is shown on both sides

	uint8_t mono[1][kSpectrumEntries];
	memset( mono, 100, sizeof( mono ));
	Engine m;
	m.Pulse( mono, 1, NULL, 0, 0, 0 );
	CHECK_NEAR( m.BarValue( 1, 3 ), m.BarValue( 0, 3 ), 0 );
	CHECK( m.BarValue( 1, 3 ) > 0 );

	// stopped with no data: everything decays and the engine goes idle

	e.SetPlaying( false, 1 );
	for ( double t = 1; t < 10; t += 1.0 / 60 )
		e.Pulse( NULL, 0, NULL, 0, 0, t );
	for ( int b = 0; b < e.Bands(); b++ )
		CHECK( e.BarValue( 0, b ) == 0 && e.BarPeak( 0, b ) == 0 );
	CHECK( ! e.IsAnimating( 10 ));

	// gain: half-level data with gain 2 reads like full-level data

	Engine g;
	g.GetSettings().spectrumGain = 2.0;
	g.GetSettings().logResponse = false;
	g.SettingsEdited( 0 );
	FillSpectrum( spec, 120 );
	g.Pulse( spec, 2, NULL, 0, 0, 0 );
	CHECK_NEAR( g.BarValue( 0, 0 ), 240.0 / 255.0, 1e-9 );

	// diagnostics: one second of pulses

	Engine d;
	FillSpectrum( spec, 0 );
	spec[0][23] = spec[1][23] = 200;
	for ( int i = 0; i <= 60; i++ )
		d.Pulse(( i % 2 )? spec : NULL, 2, NULL, 0, 0, 100 + i / 60.0 );
	std::vector<std::string> lines = d.DiagnosticLines();
	CHECK( lines.size() >= 5 );
	CHECK( lines[0].find( "61.0/s" ) != std::string::npos );
	CHECK( lines[0].find( "30.0/s with spectrum" ) != std::string::npos );
	CHECK( lines[3].find( "loudest entry 23" ) != std::string::npos );
	CHECK( lines[4].find( "spectrum (no waveform data)" ) != std::string::npos );
}


static void TestEngineTextAndArt()
{
	Engine e;
	TrackInfo t;
	t.title = "Lithium";
	t.artist = "Nirvana";
	t.totalTimeMS = 256000;

	e.SetTrack( t, 100 );
	CHECK_EQ_STR( e.TrackText(), "Lithium \xE2\x80\xA2 Nirvana" );
	CHECK_NEAR( e.TextOpacity( 105 ), 1, 0 );
	CHECK_NEAR( e.TextOpacity( 100 + kTextDisplayTime + kFadeTime / 2 ), 0.5, 1e-9 );
	CHECK_NEAR( e.TextOpacity( 100 + kTextDisplayTime + kFadeTime + 1 ), 0, 0 );

	// a title that is just sitting there needs no frames; its fade does
	
	CHECK( ! e.IsAnimating( 105 ));
	CHECK( e.IsAnimating( 100 + kTextDisplayTime + 0.5 ));
	CHECK( ! e.IsAnimating( 100 + kTextDisplayTime + kFadeTime + 1 ));
	
	e.GetSettings().keepTextVisible = true;
	CHECK_NEAR( e.TextOpacity( 1000 ), 1, 0 );
	e.GetSettings().keepTextVisible = false;

	// the same info again does not restart the timer

	e.SetTrack( t, 200 );
	CHECK_NEAR( e.TextOpacity( 200 ), 0, 0 );

	// progress

	uint8_t spec[2][kSpectrumEntries] = {{ 0 }};
	e.SetPlaying( true, 300 );
	e.Pulse( spec, 2, NULL, 0, 128000, 300 );
	CHECK_NEAR( e.ProgressFraction(), 0.5, 1e-12 );
	CHECK_EQ_STR( e.ElapsedText(), "2:08" );
	CHECK_EQ_STR( e.TotalText(), "4:16" );

	// cover art: centred for 6 s, then fades out or becomes the background

	e.SetArtwork( true, NULL, 400 );
	CoverArtState c = e.CoverArt( 403 );
	CHECK( c.opacity == 1 && c.centred == 1 );
	e.SetPlaying( false, 403 );
	CHECK( ! e.IsAnimating( 403 ));
	CHECK( e.IsAnimating( 400 + kCoverDisplayTime + 0.5 ));
	e.SetPlaying( true, 403 );
	c = e.CoverArt( 400 + kCoverDisplayTime + kFadeTime + 1 );
	CHECK( c.opacity == 0 );

	e.GetSettings().coverArtBackgroundEffect = true;
	c = e.CoverArt( 400 + kCoverDisplayTime + kFadeTime + 1 );
	CHECK_NEAR( c.opacity, kCoverBackgroundOpacity, 1e-12 );
	CHECK( c.centred == 0 );
	c = e.CoverArt( 400 + kCoverDisplayTime + kFadeTime / 2 );
	CHECK_NEAR( c.centred, 0.5, 1e-9 );

	e.GetSettings().coverArt = false;
	CHECK( e.CoverArt( 401 ).opacity == 0 );
	e.GetSettings().coverArt = true;

	// artwork colours override the palette

	ArtworkColours art;
	art.background = Colour( 0, 0, 1 );
	art.primary = Colour( 0, 1, 1 );
	art.secondary = Colour( 1, 1, 1 );
	art.detail = Colour( 1, 0, 0 );
	uint32_t serial = e.PaletteSerial();
	e.GetSettings().coverArtColours = true;
	e.SetArtwork( true, &art, 500 );
	CHECK( e.CurrentPalette().background == Colour( 0, 0, 1 ));
	CHECK( e.PaletteSerial() != serial );

	// randomise on track change

	Engine r;
	r.GetSettings().randomiseColours = true;
	Palette before = r.CurrentPalette();
	TrackInfo t2;
	t2.title = "Sweet Thing";
	r.SetTrack( t2, 0 );
	CHECK( r.CurrentPalette() != before );
	CHECK( r.CurrentPalette().background == before.background );
}


static void TestEngineKeys()
{
	TestHost host;
	Engine e( &host );
	const double now = 50;

	struct { char key; const char* first; const char* second; } toggles[] =
	{
		{ 'p', "P - Show Progress Bar", "P - Hide Progress Bar" },
		{ 'v', "V - Hide VU Meters", "V - Show VU Meters" },
		{ 't', "T - Place Track Info Above", "T - Place Track Info Below" },
		{ 'k', "K - Hide Peak Indicators", "K - Show Peak Indicators" },
		{ 'b', "B - Hide Blend Colour", "B - Show Blend Colour" },
		{ 'm', "M - Animate Colours", "M - Do Not Animate Colours" },
		{ 'l', "L - Hide Scale Labels", "L - Show Scale Labels" },
		{ 'u', "U - Hide Unlit Segments", "U - Show Unlit Segments" },
		{ 'f', "F - Hide Reflections", "F - Show Reflections" },
		{ 'c', "C - Hide Cover Art", "C - Show Cover Art" },
		{ 'n', "N - Linear Response", "N - Logarithmic Response" },
		{ 's', "S - Hide Song Title", "S - Show Song Title" },
		{ 'r', "R - Hide Artist", "R - Show Artist" },
		{ 'a', "A - Show Album", "A - Hide Album" },
		{ 'y', "Y - Show Year", "Y - Hide Year" },
		{ 'h', "H - Change Perspective", "H - Change Perspective" },
	};

	for ( size_t i = 0; i < sizeof( toggles ) / sizeof( toggles[0] ); i++ )
	{
		Dictionary before = e.GetSettings().ToDictionary();

		CHECK( e.HandleKey( toggles[i].key, now ));
		CHECK_EQ_STR( e.FeedbackText(), toggles[i].first );
		CHECK( e.GetSettings().ToDictionary() != before );
		CHECK( e.HandleKey( toupper( toggles[i].key ), now ));
		CHECK_EQ_STR( e.FeedbackText(), toggles[i].second );
		CHECK( e.GetSettings().ToDictionary() == before );
	}
	CHECK( host.settingsChanges >= 32 );

	uint32_t ls = e.LayoutSerial();
	CHECK( e.HandleKey( 'x', now ));
	CHECK_EQ_STR( e.FeedbackText(), "X - Cycle Layout" );
	CHECK( e.GetSettings().layout == kLayoutBackToBack );
	CHECK( e.LayoutSerial() != ls );

	CHECK( e.HandleKey( '>', now ));
	CHECK( e.GetSettings().numberOfSpectrumBars == 24 && e.Bands() == 24 );
	CHECK_EQ_STR( e.FeedbackText(), "> - Cycle Number Of Bars 24" );
	CHECK( e.HandleKey( '.', now ));
	CHECK( e.Bands() == 31 );

	// i hides and restores whatever fields were selected

	e.GetSettings().trackInfoMask = kInfoTitle | kInfoYear;
	CHECK( e.HandleKey( 'i', now ));
	CHECK( e.GetSettings().trackInfoMask == 0 );
	CHECK_EQ_STR( e.FeedbackText(), "I - Hide Track Info" );
	CHECK( e.HandleKey( 'i', now ));
	CHECK( e.GetSettings().trackInfoMask == ( kInfoTitle | kInfoYear ));
	CHECK_EQ_STR( e.FeedbackText(), "I - Show Track Info" );

	CHECK( e.HandleKey( 'd', now ));
	CHECK( host.options == 1 );

	CHECK( e.HandleKey( '=', now ));
	CHECK( e.DiagnosticsVisible());

	// feedback fades after 3 s

	CHECK_NEAR( e.FeedbackOpacity( now + 0.5 ), 1, 0 );
	CHECK( e.FeedbackOpacity( now + kFeedbackTime - 0.1 ) < 0.2 );
	CHECK( e.FeedbackOpacity( now + kFeedbackTime + 0.1 ) == 0 );

	// keys iTunes / Music use themselves are not consumed

	CHECK( ! e.HandleKey( ' ', now ));
	CHECK( ! e.HandleKey( 'q', now ));
	CHECK( ! e.HandleKey( '3', now ));		// no preset 3 yet
}


static void TestPresets()
{
	TestHost host;
	Engine e( &host );

	e.GetSettings().layout = kLayoutAnalogueVU;
	e.SettingsEdited( 0 );
	CHECK( e.HandleKey( 'z', 0 ));
	CHECK_EQ_STR( e.FeedbackText(), "Z - Saved Preset 1" );

	e.GetSettings().layout = kLayoutBackToBack;
	e.GetSettings().numberOfSpectrumBars = 31;
	e.SettingsEdited( 0 );
	CHECK( e.SavePreset( 0 ) == 2 );
	CHECK( host.presetChanges == 2 );

	CHECK( e.HandleKey( '1', 1 ));
	CHECK_EQ_STR( e.FeedbackText(), "Applied Preset 1" );
	CHECK( e.GetSettings().layout == kLayoutAnalogueVU && e.GetSettings().numberOfSpectrumBars == 18 );
	CHECK( e.CurrentPreset() == 1 );

	CHECK( e.HandleKey( '/', 2 ));
	CHECK_EQ_STR( e.FeedbackText(), "/ - Applied Preset 2" );
	CHECK( e.GetSettings().layout == kLayoutBackToBack && e.Bands() == 31 );
	CHECK( e.HandleKey( '/', 3 ));
	CHECK( e.CurrentPreset() == 1 );

	// at most 10; when full, saving overwrites the current one

	for ( int i = 0; i < 12; i++ )
		e.SavePreset( 4 );
	CHECK( e.Presets().size() == (size_t) kMaxPresets );

	CHECK( e.HandleKey( '0', 5 ));
	CHECK( e.CurrentPreset() == 10 );

	e.ClearPresets( 6 );
	CHECK( e.Presets().empty() && e.CurrentPreset() == 0 );
	CHECK_EQ_STR( e.FeedbackText(), "All Presets Deleted" );
	CHECK( ! e.HandleKey( '1', 7 ));

	std::vector<Dictionary> stored( 3, Settings().ToDictionary());
	e.SetPresets( stored, 2 );
	CHECK( e.Presets().size() == 3 && e.CurrentPreset() == 2 );
}


int main()
{
	TestBandMap();
	TestBinningAndResponse();
	TestLevels();
	TestBarBallistics();
	TestNeedle();
	TestSettings();
	TestLayout();
	TestTrackText();
	TestColours();
	TestEngineMeters();
	TestEngineTextAndArt();
	TestEngineKeys();
	TestPresets();

	printf( "%d checks, %d failures\n", gChecks, gFailures );
	return gFailures == 0? 0 : 1;
}
