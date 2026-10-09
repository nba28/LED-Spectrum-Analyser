/*
 *  LEDLayout.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDLayout.h"
#include <algorithm>


namespace led
{

const char* const kFrequencyLabels[9] = { "50Hz", "100", "200", "500", "1k", "2k", "5k", "10k", "20k" };

static const char* const kLogLevelLabels[7] = { "0", "-1", "-2", "-3", "-4", "-5", "-6" };
static const char* const kLinLevelLabels[7] = { "100", "83", "67", "50", "33", "17", "0" };


// proportions measured from the manual's screenshots (fractions of the view's width / height)

static const double kSideMargin			= 0.054;
static const double kCentreGap			= 0.115;
static const double kTopReserve			= 0.20;		// room for the progress bar / track info above
static const double kBottomReserve		= 0.16;		// room for the track info / progress bar below
static const double kSpectrumHeight		= 0.41;
static const double kLabelsHeight		= 0.040;
static const double kNoLabelsHeight		= 0.015;
static const double kVUGap				= 0.035;
static const double kVUHeight			= 0.061;
static const double kSlotCentreTop		= 0.143;	// progress bar (or track info above), from the top
static const double kSlotCentreBottom	= 0.895;	// track info (or progress bar below), from the top
static const double kSegmentPitch		= 2.8;		// points, at the reference size
static const double kVUSegmentPitch		= 4.5;


static inline double	Snap( double v )
{
	return floor( v + 0.5 );
}


// a label of width <w> centred on <centre>, kept within 0..<limit>

static inline Rect	LabelRect( double centre, double w, double limit, double h )
{
	w = std::min( w, limit );
	return Rect( clamp( centre - w / 2, 0.0, limit - w ), 0, w, h );
}


Layout	ComputeLayout( double W, double H, const Settings& s )
{
	Layout L;

	W = std::max( W, 1.0 );
	H = std::max( H, 1.0 );

	L.bounds = Rect( 0, 0, W, H );

	L.scaleFontSize	= clamp( 0.022 * H, 7.0, 18.0 );
	L.textFontSize	= clamp( 0.067 * H, 11.0, 96.0 );
	L.timeFontSize	= clamp( 0.035 * H, 8.0, 40.0 );

	L.analogue		= ( s.layout == kLayoutAnalogueVU );
	L.showSpectrum	= ! L.analogue;
	L.barsVertical	= ( s.layout != kLayoutBackToBack );
	L.showVU		= s.showVU;
	L.showProgress	= s.showProgress;

	// ---- vertical arrangement (computed top-down, converted to bottom-up at the end) ----

	double specH	= Snap( kSpectrumHeight * H );
	double labelsH	= Snap(( s.scalesVisible? kLabelsHeight : kNoLabelsHeight ) * H );
	double vuGap	= L.showVU? Snap( kVUGap * H ) : 0;
	double vuH		= L.showVU? Snap( kVUHeight * H ) : 0;
	double blockH	= specH + labelsH + vuGap + vuH;

	double regionTop	= kTopReserve * H;
	double regionBottom	= ( 1.0 - kBottomReserve ) * H;
	double blockTop		= Snap( regionTop + (( regionBottom - regionTop ) - blockH ) / 2.0 );

	// ---- horizontal arrangement ----

	double margin	= kSideMargin * W;
	double gap		= Snap( kCentreGap * W );
	double panelW	= floor(( W - 2 * margin - gap ) / 2.0 );

	// on very wide views keep the panels from becoming absurdly stretched

	panelW = std::max( 10.0, std::min( panelW, 2.4 * specH ));

	double leftX	= Snap( W / 2.0 - gap / 2.0 - panelW );
	double rightX	= Snap( W / 2.0 + gap / 2.0 );

	// top-down y -> bottom-up rect

	#define RECT_TD( x, top, w, h )		Rect(( x ), H - ( top ) - ( h ), ( w ), ( h ))

	// ---- spectrum panels ----

	int bands = s.numberOfSpectrumBars;

	L.leftPanel		= RECT_TD( leftX, blockTop, panelW, specH + labelsH );
	L.rightPanel	= RECT_TD( rightX, blockTop, panelW, specH + labelsH );

	L.segments = 0;
	L.segmentPitch = L.segmentGap = 0;
	L.peakSegments = 2;

	if ( L.showSpectrum )
	{
		if ( L.barsVertical )
		{
			// side by side: bars across, growing upwards; lowest band next to the centre

			double barW = panelW / bands;
			double colGap = std::max( 1.0, Snap( barW * 0.12 ));

			L.segments = clamp((int) lround( specH / kSegmentPitch ), 32, 80 );
			L.segmentPitch = specH / L.segments;

			for ( int b = 0; b < bands; b++ )
			{
				double xl = panelW - ( b + 1 ) * barW;		// left panel: band 0 at the inner (right) edge
				double xr = b * barW;						// right panel: band 0 at the inner (left) edge

				L.leftBars.push_back( Rect( Snap( xl ), labelsH, Snap( xl + barW - colGap ) - Snap( xl ), specH ));
				L.rightBars.push_back( Rect( Snap( xr + colGap ), labelsH, Snap( xr + barW ) - Snap( xr + colGap ), specH ));
			}

			if ( s.scalesVisible )
			{
				// frequency labels under each panel, evenly spread as in 3.x, 50Hz at the centre

				double lw = std::max( 30.0, panelW / 9.0 );

				for ( int i = 0; i < 9; i++ )
				{
					double c = ( 0.5 + i ) * panelW / 9.0;
					Label ll = { kFrequencyLabels[i], LabelRect( panelW - c, lw, panelW, labelsH ), kLabelAlignCentre };
					Label rl = { kFrequencyLabels[i], LabelRect( c, lw, panelW, labelsH ), kLabelAlignCentre };
					L.leftLabels.push_back( ll );
					L.rightLabels.push_back( rl );
				}

				// level scale up the centre

				double lh = L.scaleFontSize * 1.4;

				for ( int i = 0; i < 7; i++ )
				{
					double y = L.leftPanel.y + labelsH + specH * ( 1.0 - i / 6.0 ) - lh / 2;
					Label cl = { s.logResponse? kLogLevelLabels[i] : kLinLevelLabels[i], Rect( W / 2 - gap / 2, y, gap, lh ), kLabelAlignCentre };
					L.centreLabels.push_back( cl );
				}
			}
		}
		else
		{
			// back to back: bands stacked upwards (lowest at the bottom), bars growing outwards

			double barH = specH / bands;
			double rowGap = std::max( 1.0, Snap( barH * 0.12 ));

			L.segments = clamp((int) lround( panelW / kSegmentPitch ), 32, 96 );
			L.segmentPitch = panelW / L.segments;

			for ( int b = 0; b < bands; b++ )
			{
				double y = labelsH + b * barH;
				Rect r( 0, Snap( y + rowGap / 2 ), panelW, Snap( y + barH - rowGap / 2 ) - Snap( y + rowGap / 2 ));
				L.leftBars.push_back( r );
				L.rightBars.push_back( r );
			}

			if ( s.scalesVisible )
			{
				// level scale under each panel, full scale at the outer ends

				double lw = std::max( 24.0, panelW / 7.0 );

				for ( int i = 0; i < 7; i++ )
				{
					double w = std::min( lw, panelW );
					double c = w / 2 + i * ( panelW - w ) / 6.0;
					Label ll = { s.logResponse? kLogLevelLabels[i] : kLinLevelLabels[i], LabelRect( c, w, panelW, labelsH ), kLabelAlignCentre };
					Label rl = { s.logResponse? kLogLevelLabels[i] : kLinLevelLabels[i], LabelRect( panelW - c, w, panelW, labelsH ), kLabelAlignCentre };
					L.leftLabels.push_back( ll );
					L.rightLabels.push_back( rl );
				}

				// frequency scale up the centre

				double lh = L.scaleFontSize * 1.4;

				for ( int i = 0; i < 9; i++ )
				{
					double y = L.leftPanel.y + labelsH + specH * ( 0.5 + i ) / 9.0 - lh / 2;
					Label cl = { kFrequencyLabels[i], Rect( W / 2 - gap / 2, y, gap, lh ), kLabelAlignCentre };
					L.centreLabels.push_back( cl );
				}
			}
		}

		L.segmentGap = std::max( 0.6, L.segmentPitch * 0.28 );
	}

	// ---- analogue meters: 2:1, centred in the spectrum areas ----

	if ( L.analogue )
	{
		double mw = std::min( panelW * 0.96, specH * 2.0 );
		double mh = mw / 2.0;
		double top = blockTop + ( specH - mh ) / 2.0;

		L.leftMeter		= RECT_TD( Snap( leftX + ( panelW - mw ) / 2 ), Snap( top ), Snap( mw ), Snap( mh ));
		L.rightMeter	= RECT_TD( Snap( rightX + ( panelW - mw ) / 2 ), Snap( top ), Snap( mw ), Snap( mh ));
	}

	// ---- VU bargraphs ----

	if ( L.showVU )
	{
		double top = blockTop + specH + labelsH + vuGap;

		L.leftVU	= RECT_TD( leftX, top, panelW, vuH );
		L.rightVU	= RECT_TD( rightX, top, panelW, vuH );
		L.vuSegments = clamp((int) lround( panelW / kVUSegmentPitch ), 24, 120 );
		L.vuPitch = panelW / L.vuSegments;
		L.vuGap = std::max( 0.6, L.vuPitch * 0.3 );

		Label vl = { "L   VU   R", Rect( W / 2 - gap / 2, L.leftVU.y, gap, vuH ), kLabelAlignCentre };
		L.vuLabel = vl;
	}

	// ---- progress bar and track info slots ----

	double progressCentre	= ( s.textAbove? kSlotCentreBottom : kSlotCentreTop ) * H;
	double textCentre		= ( s.textAbove? kSlotCentreTop : kSlotCentreBottom ) * H;
	double thickness		= std::max( 4.0, Snap( 0.022 * H ));

	L.progressTrack = RECT_TD( Snap( 0.125 * W ), Snap( progressCentre - thickness / 2 ), Snap( 0.746 * W ), thickness );

	double th = L.timeFontSize * 1.4;
	Label el = { "", RECT_TD( Snap( margin ), Snap( progressCentre - th / 2 ), Snap( 0.125 * W - margin - 6 ), th ), kLabelAlignLeft };
	Label tl = { "", RECT_TD( Snap( L.progressTrack.maxX() + 6 ), Snap( progressCentre - th / 2 ), Snap( W - margin - L.progressTrack.maxX() - 6 ), th ), kLabelAlignRight };
	L.elapsedLabel = el;
	L.totalLabel = tl;

	double textH = L.textFontSize * 1.5;
	L.textArea = RECT_TD( Snap( margin ), Snap( textCentre - textH / 2 ), Snap( W - 2 * margin ), Snap( textH ));

	// ---- reflection ----

	L.displayArea = RECT_TD( leftX, blockTop, rightX + panelW - leftX, blockH );
	L.reflectionAxisY = L.displayArea.y;

	// ---- transient text ----

	L.feedbackArea		= RECT_TD( 10, 8, std::min( 420.0, W - 20 ), 18 );
	L.diagnosticsArea	= RECT_TD( 10, 30, std::min( 640.0, W - 20 ), 150 );

	#undef RECT_TD

	return L;
}

}	// namespace led
