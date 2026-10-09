/*
 *  LEDAnalysis.h
 *  LED Spectrum Analyser
 *
 *  Turns the host's 512-entry spectrum and waveform arrays into display levels, and models the
 *  meter ballistics.
 *
 *  Frequency mapping: both LEDSA 2.0.6 (source) and 3.0.7 (binary) use the same calibration of
 *  78.047 Hz per spectrum entry, with bands spaced logarithmically over three decades from 20 Hz
 *  to 20 kHz. That mapping is kept exactly, so the bars line up the way they always did.
 *
 */

#ifndef LED_ANALYSIS_H
#define LED_ANALYSIS_H

#include <vector>
#include "LEDTypes.h"


namespace led
{

enum
{
	kSpectrumEntries	= 512,
	kWaveformEntries	= 512,
	kMaxBands			= 32
};

static const double kHzPerEntry = 78.047;


// which spectrum entries feed each display band

class BandMap
{
public:
	explicit BandMap( int bands = 18 );

	int		Bands() const						{ return (int) first.size(); }
	int		FirstEntry( int band ) const		{ return first[band]; }
	int		EntryCount( int band ) const		{ return count[band]; }
	double	LowerFrequency( int band ) const;	// nominal band edge, Hz

private:
	std::vector<int>	first;
	std::vector<int>	count;
};


// raw band levels (0..255) from one channel of spectrum data. Applies gain (clamped at 255) and
// averages the contributing entries, or takes their maximum ("Bin Using Peak Values").

void		BinSpectrum( const uint8_t spectrum[kSpectrumEntries], const BandMap& map, double gain, bool usePeak, double* outBands );

// display response: maps a raw 0..255 level onto 0..1. Logarithmic mode is the 2.x/3.x curve
// ln(v)/ln(255), which makes each tenth of the scale ~4.8 dB.

double		ResponseCurve( double raw, bool logarithmic );

// level of one waveform channel. The host supplies unsigned 8-bit samples centred on 128.

double		WaveformRMS( const uint8_t waveform[kWaveformEntries] );
bool		WaveformIsSilent( const uint8_t waveform[kWaveformEntries] );

// fallback level when the host sends no waveform: mean of the lower half of the spectrum, 0..1

double		SpectrumLevel( const uint8_t spectrum[kSpectrumEntries], double gain );

// VU scales. RMS level <kVUReferenceRMS> reads 0 VU; full scale is +3 VU.

static const double kVUReferenceRMS = 0.25;

double		VUFraction( double rms, double gain );			// linear (analogue meter), 0..1 = -inf..+3 VU (may exceed 1)
double		VUFractionForDB( double vuDB );					// position of a scale mark
double		VUBargraphFraction( double rms, double gain, bool logarithmic );	// -48..+3 dB in log mode


// bar + peak indicator ballistics. Times in seconds. Attack is instantaneous; decay is either an
// exponential (RC) with time constant <barDecay>, or linear, falling full scale in <barDecay>.

struct BarParams
{
	bool	expDecay;
	double	barDecay;
	double	peakHold;
	double	peakDecay;
};

class BarMeter
{
public:
	BarMeter();

	void	Reset();
	void	Update( double target, double now, const BarParams& p );		// target 0..1
	double	Value() const	{ return value; }
	double	Peak() const	{ return peak; }

private:
	double	value, attackValue, attackTime;
	double	peak, peakValueAtRelease, peakHoldUntil;
	bool	started;
};


// analogue VU needle: a damped second order system like a real moving coil movement. <response>
// is the time to settle within 1% after a step (300 ms for a standard VU meter), overshoot ~1.5%.
// The peak LED lights for 0.5 s whenever the instantaneous level exceeds 95% of full scale.

class NeedleMeter
{
public:
	NeedleMeter();

	void	Reset();
	void	Update( double target, double now, double response );
	double	Position() const	{ return position; }		// 0..~1.05
	bool	PeakLit() const		{ return peakLit; }

private:
	double	position, velocity, lastTime;
	bool	started;
	bool	peakLit;
	double	peakUntil;
};

}	// namespace led

#endif
