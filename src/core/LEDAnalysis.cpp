/*
 *  LEDAnalysis.cpp
 *  LED Spectrum Analyser
 *
 */

#include "LEDAnalysis.h"
#include <algorithm>


namespace led
{

// ---------------------------------------------------------------------------------------------
// band mapping - Graham Cox's original log tables (ITBarDisplay.cpp, 2004)

static inline double linch( int inLogch, int nLogChannels )
{
	// returns the (fractional) spectrum entry corresponding to the nth log channel in a set:
	// band edges are 20 Hz * 10^(3n/N), at kHzPerEntry Hz per entry

	double dec = ( 3.0 / nLogChannels ) * inLogch;
	return (( 20 * pow( 10, dec )) - 20 ) / kHzPerEntry;
}


BandMap::BandMap( int bands )
{
	bands = clamp( bands, 1, (int) kMaxBands );

	double prev = 0;
	int k = 0;

	for ( int i = 0; i < bands; i++ )
	{
		double lin = linch( i + 1, bands );
		int m = (int) lround( lin - prev );

		prev = lin;

		if ( m < 1 )
			m = 1;

		// never run off the end of the data

		if ( k + m > kSpectrumEntries )
			m = std::max( 1, kSpectrumEntries - k );

		first.push_back( std::min( k, kSpectrumEntries - 1 ));
		count.push_back( m );
		k += m;
	}
}


double	BandMap::LowerFrequency( int band ) const
{
	return 20.0 * pow( 10.0, 3.0 * band / Bands());
}


void	BinSpectrum( const uint8_t spectrum[kSpectrumEntries], const BandMap& map, double gain, bool usePeak, double* outBands )
{
	for ( int i = 0; i < map.Bands(); i++ )
	{
		int first = map.FirstEntry( i );
		int n = map.EntryCount( i );
		double acc = 0;

		for ( int k = first; k < first + n && k < kSpectrumEntries; k++ )
		{
			double v = std::min( 255.0, spectrum[k] * gain );

			if ( usePeak )
				acc = std::max( acc, v );
			else
				acc += v;
		}

		outBands[i] = usePeak? acc : acc / n;
	}
}


double	ResponseCurve( double raw, bool logarithmic )
{
	raw = clamp( raw, 0.0, 255.0 );

	if ( logarithmic )
		return ( raw < 1.0 )? 0.0 : log( raw ) / log( 255.0 );

	return raw / 255.0;
}


double	WaveformRMS( const uint8_t waveform[kWaveformEntries] )
{
	double sum = 0;

	for ( int i = 0; i < kWaveformEntries; i++ )
	{
		double s = ( waveform[i] - 128.0 ) / 128.0;
		sum += s * s;
	}
	return sqrt( sum / kWaveformEntries );
}


bool	WaveformIsSilent( const uint8_t waveform[kWaveformEntries] )
{
	for ( int i = 0; i < kWaveformEntries; i++ )
		if ( waveform[i] != 128 && waveform[i] != 127 && waveform[i] != 0 )
			return false;
	return true;
}


double	SpectrumLevel( const uint8_t spectrum[kSpectrumEntries], double gain )
{
	double sum = 0;

	for ( int k = 0; k < 256; k++ )
		sum += std::min( 255.0, spectrum[k] * gain );

	return sum / ( 256.0 * 255.0 );
}


double	VUFractionForDB( double vuDB )
{
	// a VU meter's scale is linear in voltage; full scale is +3 VU

	return pow( 10.0, vuDB / 20.0 ) / pow( 10.0, 3.0 / 20.0 );
}


double	VUFraction( double rms, double gain )
{
	return ( rms * gain / kVUReferenceRMS ) * VUFractionForDB( 0 );
}


double	VUBargraphFraction( double rms, double gain, bool logarithmic )
{
	double level = rms * gain / kVUReferenceRMS;		// 1.0 = 0 VU

	if ( ! logarithmic )
		return clamp( level * VUFractionForDB( 0 ), 0.0, 1.0 );

	if ( level <= 0 )
		return 0;

	double db = 20.0 * log10( level );
	return clamp(( db + 48.0 ) / 51.0, 0.0, 1.0 );
}


// ---------------------------------------------------------------------------------------------
// bar ballistics

BarMeter::BarMeter()
{
	Reset();
}


void	BarMeter::Reset()
{
	value = attackValue = attackTime = 0;
	peak = peakValueAtRelease = peakHoldUntil = 0;
	started = false;
}


static double	Decay( double from, double elapsed, double timeConstant, bool exponential )
{
	if ( elapsed <= 0 )
		return from;

	timeConstant = std::max( 1e-3, timeConstant );

	if ( exponential )
		return from * exp( -elapsed / timeConstant );

	return from - ( elapsed / timeConstant );		// full scale falls in <timeConstant>
}


void	BarMeter::Update( double target, double now, const BarParams& p )
{
	target = clamp( target, 0.0, 1.0 );

	if ( ! started )
	{
		attackTime = peakHoldUntil = now;
		started = true;
	}

	// main bar

	if ( target >= value )
	{
		value = attackValue = target;
		attackTime = now;
	}
	else
	{
		value = std::max( target, Decay( attackValue, now - attackTime, p.barDecay, p.expDecay ));

		if ( value < 1e-4 )
			value = 0;
	}

	// peak indicator: hold, then decay, never below the bar

	if ( target >= peak )
	{
		peak = peakValueAtRelease = target;
		peakHoldUntil = now + p.peakHold;
	}
	else if ( now > peakHoldUntil )
	{
		peak = Decay( peakValueAtRelease, now - peakHoldUntil, p.peakDecay, p.expDecay );

		if ( peak < 1e-4 )
			peak = 0;
	}

	peak = clamp( std::max( peak, value ), 0.0, 1.0 );
}


// ---------------------------------------------------------------------------------------------
// VU needle

NeedleMeter::NeedleMeter()
{
	Reset();
}


void	NeedleMeter::Reset()
{
	position = velocity = lastTime = 0;
	started = false;
	peakLit = false;
	peakUntil = 0;
}


void	NeedleMeter::Update( double target, double now, double response )
{
	if ( ! started )
	{
		lastTime = now;
		started = true;
	}

	// peak LED

	if ( target > 0.95 )
		peakUntil = now + 0.5;

	peakLit = ( now < peakUntil );

	// mechanical limits: the needle can bang a little past full scale

	target = clamp( target, 0.0, 1.08 );

	double dt = now - lastTime;
	lastTime = now;

	if ( dt <= 0 )
		return;
	if ( dt > 0.25 )
		dt = 0.25;		// after a stall, don't integrate a huge step

	const double zeta = 0.8;									// ~1.5% overshoot
	const double omega = 6.5 / std::max( 0.02, response );		// settles to 1% in ~<response>

	int steps = (int) ceil( dt / 0.001 );
	double h = dt / steps;

	for ( int i = 0; i < steps; i++ )
	{
		double accel = omega * omega * ( target - position ) - 2.0 * zeta * omega * velocity;
		velocity += accel * h;
		position += velocity * h;
	}

	if ( position < 0 )
	{
		position = 0;
		velocity = std::max( 0.0, velocity );
	}
	if ( position > 1.1 )
	{
		position = 1.1;
		velocity = std::min( 0.0, velocity );
	}
}

}	// namespace led
