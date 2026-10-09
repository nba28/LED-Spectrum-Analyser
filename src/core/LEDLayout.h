/*
 *  LEDLayout.h
 *  LED Spectrum Analyser
 *
 *  Computes the geometry of every element of the display for a given view size and settings.
 *  Proportions are measured from the screenshots in Graham Cox's LEDSA 3.0 manual; everything
 *  scales with the view ("there is no longer a small, medium, or large option").
 *
 *  All rects are in points, origin bottom-left (Core Animation convention). Bars and their
 *  labels are given relative to their panel, because each panel is tilted as a unit when
 *  perspective is on.
 *
 */

#ifndef LED_LAYOUT_H
#define LED_LAYOUT_H

#include <vector>
#include "LEDSettings.h"


namespace led
{

enum LabelAlign
{
	kLabelAlignLeft		= 0,
	kLabelAlignCentre	= 1,
	kLabelAlignRight		= 2
};

struct Label
{
	std::string		text;
	Rect			frame;
	int				align;
};


struct Layout
{
	Rect				bounds;

	double				scaleFontSize;			// scale labels
	double				textFontSize;			// track info (preferred; may shrink to fit)
	double				timeFontSize;			// progress bar times

	// spectrum panels

	bool				showSpectrum;
	bool				barsVertical;			// side by side: bars grow upwards. back to back: outwards
	Rect				leftPanel, rightPanel;	// view coordinates, include the labels row
	std::vector<Rect>	leftBars, rightBars;	// panel coordinates, index = band (0 = lowest frequency)
	int					segments;
	double				segmentPitch;			// along the bar
	double				segmentGap;
	int					peakSegments;			// height of a peak marker, in segments
	std::vector<Label>	leftLabels, rightLabels;	// panel coordinates
	std::vector<Label>	centreLabels;			// view coordinates

	// VU bargraphs

	bool				showVU;
	Rect				leftVU, rightVU;		// view coordinates; left grows leftwards from its right edge
	int					vuSegments;
	double				vuPitch, vuGap;
	Label				vuLabel;

	// analogue VU meters

	bool				analogue;
	Rect				leftMeter, rightMeter;

	// progress bar

	bool				showProgress;
	Rect				progressTrack;
	Label				elapsedLabel, totalLabel;

	// track information

	Rect				textArea;

	// everything that is reflected, and the line it is reflected about

	Rect				displayArea;
	double				reflectionAxisY;

	// transient text

	Rect				feedbackArea;
	Rect				diagnosticsArea;
};


Layout		ComputeLayout( double width, double height, const Settings& settings );

// the nine frequency labels used by 3.x, lowest first

extern const char* const kFrequencyLabels[9];

}	// namespace led

#endif
