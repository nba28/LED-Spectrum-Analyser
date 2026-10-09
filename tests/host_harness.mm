/*
 *  host_harness.mm
 *  LED Spectrum Analyser
 *
 *  A stand-in for iTunes / Music. Loads the plug-in bundle, registers it through
 *  iTunesPluginMainMachO, then drives it with the same message sequence a host uses (init,
 *  activate, play, pulses with spectrum + waveform data, cover art, key presses, configure,
 *  deactivate, cleanup), and writes screenshots of what it draws.
 *
 *      host_harness <path to LED Spectrum Analyser.bundle> <output directory>
 *
 *  Exits non-zero if anything the host relies on is missing or broken.
 *
 *  Built without ARC: under ARC the SDK's NSOpenGLView* member makes VisualPluginMessageInfo a
 *  non-trivial C++ type that can't be declared on the stack (the plug-in itself only ever reads it
 *  through the host's pointer, so is unaffected). Objects created here simply live until exit.
 *
 */

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <algorithm>
#include <vector>

#include "iTunesVisualAPI.h"


static PlayerRegisterVisualPluginMessage	gRegistration;
static bool			gRegistered = false;
static int			gArtworkRequests = 0;
static void*		gRefCon = NULL;
static NSView*		gContainer = nil;
static NSString*	gOutDir = nil;
static int			gFailures = 0;
static uint32_t		gTimeStamp = 0;
static uint32_t		gPosition = 0;
static std::vector<double>	gPulseTimes;

#define kDomain		@"io.github.nba28.LEDSpectrumAnalyser"

#define EXPECT( cond, msg ) do { if ( !( cond )) { gFailures++; fprintf( stderr, "FAIL: %s\n", msg ); } else printf( "ok:   %s\n", msg ); } while ( 0 )


static OSStatus	AppProc( void* appCookie, OSType message, PlayerMessageInfo* info )
{
	switch ( message )
	{
		case kPlayerRegisterVisualPluginMessage:
			gRegistration = info->u.registerVisualPluginMessage;
			gRegistered = true;
			return noErr;

		case kPlayerRequestCurrentTrackCoverArtMessage:
			gArtworkRequests++;
			return noErr;

		default:
			return noErr;
	}
}


static OSStatus	Send( OSType message, VisualPluginMessageInfo* info )
{
	return gRegistration.handler( message, info, gRefCon );
}


static NSView*	PluginView()
{
	return gContainer.subviews.firstObject;
}


static void		SpinRunLoop( double seconds )
{
	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}


#pragma mark - rendering the layer tree to an image

static NSWindow*	gWindow;

static NSBitmapImageRep*	RenderWithCARenderer( CALayer* layer, int W, int H )
{
	if ( gWindow )
		return nil;		// the layer belongs to the window's render context
	
	// full fidelity (3D transforms, replicators, shadows) using the OpenGL software renderer;
	// headless build machines have no GPU

	CGLPixelFormatAttribute attrs[] =
	{
		kCGLPFARendererID, (CGLPixelFormatAttribute) kCGLRendererGenericFloatID,
		kCGLPFAColorSize, (CGLPixelFormatAttribute) 24,
		kCGLPFAAlphaSize, (CGLPixelFormatAttribute) 8,
		(CGLPixelFormatAttribute) 0
	};
	CGLPixelFormatObj pf = NULL;
	GLint n = 0;

	if ( CGLChoosePixelFormat( attrs, &pf, &n ) != kCGLNoError || pf == NULL )
		return nil;

	CGLContextObj ctx = NULL;
	CGLCreateContext( pf, NULL, &ctx );
	CGLDestroyPixelFormat( pf );

	if ( ctx == NULL )
		return nil;

	CGLSetCurrentContext( ctx );

	GLuint fbo = 0, rb = 0;
	glGenFramebuffersEXT( 1, &fbo );
	glBindFramebufferEXT( GL_FRAMEBUFFER_EXT, fbo );
	glGenRenderbuffersEXT( 1, &rb );
	glBindRenderbufferEXT( GL_RENDERBUFFER_EXT, rb );
	glRenderbufferStorageEXT( GL_RENDERBUFFER_EXT, GL_RGBA8, W, H );
	glFramebufferRenderbufferEXT( GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_RENDERBUFFER_EXT, rb );

	NSBitmapImageRep* rep = nil;

	if ( glCheckFramebufferStatusEXT( GL_FRAMEBUFFER_EXT ) == GL_FRAMEBUFFER_COMPLETE_EXT )
	{
		glViewport( 0, 0, W, H );
		glMatrixMode( GL_PROJECTION );
		glLoadIdentity();
		glOrtho( 0, W, 0, H, -1, 1 );
		glMatrixMode( GL_MODELVIEW );
		glLoadIdentity();
		glClearColor( 0, 0, 0, 1 );
		glClear( GL_COLOR_BUFFER_BIT );

		CARenderer* renderer = [CARenderer rendererWithCGLContext:ctx options:nil];
		renderer.layer = layer;
		renderer.bounds = CGRectMake( 0, 0, W, H );
		[renderer beginFrameAtTime:CACurrentMediaTime() timeStamp:NULL];
		[renderer addUpdateRect:renderer.bounds];
		[renderer render];
		[renderer endFrame];
		renderer.layer = nil;
		glFinish();

		rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4
														hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:W * 4 bitsPerPixel:32];
		std::vector<uint8_t> pixels( W * H * 4 );
		glReadPixels( 0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, &pixels[0] );

		for ( int y = 0; y < H; y++ )
			memcpy( rep.bitmapData + y * W * 4, &pixels[( H - 1 - y ) * W * 4], W * 4 );
	}

	glDeleteRenderbuffersEXT( 1, &rb );
	glDeleteFramebuffersEXT( 1, &fbo );
	CGLSetCurrentContext( NULL );
	CGLDestroyContext( ctx );
	return rep;
}


static NSBitmapImageRep*	RenderInContext( CALayer* layer, int W, int H )
{
	// fallback: no 3D transforms or replicators, but everything else

	NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:W pixelsHigh:H bitsPerSample:8 samplesPerPixel:4
																	  hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
	NSGraphicsContext* g = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
	[layer renderInContext:g.CGContext];
	return rep;
}


static bool		BitmapHasContent( NSBitmapImageRep* rep )
{
	// at least 1% of pixels not black

	long lit = 0, total = rep.pixelsWide * rep.pixelsHigh;

	for ( NSInteger y = 0; y < rep.pixelsHigh; y += 2 )
		for ( NSInteger x = 0; x < rep.pixelsWide; x += 2 )
		{
			NSUInteger p[4] = { 0, 0, 0, 0 };
			[rep getPixel:p atX:x y:y];
			if ( p[0] + p[1] + p[2] > 60 )
				lit += 4;
		}
	return lit > total / 100;
}


static void		Snapshot( NSString* name )
{
	NSView* v = PluginView();
	CALayer* layer = v.layer;
	int W = (int) gContainer.bounds.size.width, H = (int) gContainer.bounds.size.height;

	NSBitmapImageRep* rep = RenderWithCARenderer( layer, W, H );
	const char* how = "CARenderer (software OpenGL)";

	if ( rep == nil || ! BitmapHasContent( rep ))
	{
		rep = RenderInContext( layer, W, H );
		how = "renderInContext (no 3D / reflection)";
	}

	NSString* path = [gOutDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
	[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
	printf( "      wrote %s via %s\n", path.UTF8String, how );

	char msg[200];
	snprintf( msg, sizeof( msg ), "%s has visible content", name.UTF8String );
	EXPECT( BitmapHasContent( rep ), msg );
}


static void		SnapshotWindow( NSWindow* w, NSString* name )
{
	NSView* v = w.contentView;
	[v layoutSubtreeIfNeeded];
	[v display];
	NSBitmapImageRep* rep = [v bitmapImageRepForCachingDisplayInRect:v.bounds];
	[v cacheDisplayInRect:v.bounds toBitmapImageRep:rep];
	NSString* path = [gOutDir stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"png"]];
	[[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
	printf( "      wrote %s\n", path.UTF8String );
}


#pragma mark - driving the plug-in

static void		SetUniStr( ITUniStr255 dst, NSString* s )
{
	NSUInteger len = MIN( s.length, (NSUInteger) 255 );
	dst[0] = (UniChar) len;
	[s getCharacters:&dst[1] range:NSMakeRange( 0, len )];
}


static double	Seconds()
{
	return CACurrentMediaTime();
}


static RenderVisualData	gRenderData;		// the last data sent


static uint32_t		SendPulse( RenderVisualData* data, uint32_t rate )
{
	VisualPluginMessageInfo info;
	memset( &info, 0, sizeof( info ));
	info.u.pulseMessage.renderData = data;
	info.u.pulseMessage.timeStampID = ++gTimeStamp;
	info.u.pulseMessage.currentPositionInMS = gPosition;
	info.u.pulseMessage.newPulseRateInHz = rate;
	Send( kVisualPluginPulseMessage, &info );
	return info.u.pulseMessage.newPulseRateInHz;
}


static void		Pulse( double t, double loudness )
{
	RenderVisualData& rd = gRenderData;

	rd.numSpectrumChannels = 2;
	rd.numWaveformChannels = 2;

	// a music-like spectrum: strong bass, falling towards the top, with moving bumps

	for ( int c = 0; c < 2; c++ )
	{
		for ( int k = 0; k < kVisualNumSpectrumEntries; k++ )
		{
			double base = 235.0 * exp( -k / 70.0 ) + 18.0;
			double wobble = 0.55 + 0.45 * sin( t * ( 2.1 + c * 0.7 ) + k * 0.09 ) * sin( t * 0.37 + k * 0.013 + c );
			double v = loudness * base * wobble + ( arc4random_uniform( 16 ));
			rd.spectrumData[c][k] = (UInt8) MAX( 0.0, MIN( 255.0, v ));
		}
		for ( int i = 0; i < kVisualNumWaveformEntries; i++ )
		{
			double s = loudness * ( 0.42 * sin( i * 0.11 + t * 9 ) + 0.18 * sin( i * 0.53 + c ));
			rd.waveformData[c][i] = (UInt8) MAX( 0.0, MIN( 255.0, 128.0 + 127.0 * s ));
		}
	}

	double before = Seconds();
	SendPulse( &rd, 60 );
	gPulseTimes.push_back(( Seconds() - before ) * 1000.0 );
}


static void		Run( double seconds, double loudness = 1.0 )
{
	double start = Seconds();

	while ( Seconds() - start < seconds )
	{
		Pulse( Seconds(), loudness );
		gPosition += 17;
		SpinRunLoop( 1.0 / 60 );
	}
}


static void		Key( NSString* chars )
{
	NSEvent* e = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
								   context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:0];
	[PluginView() keyDown:e];
}


static NSData*	MakeCoverArt()
{
	// a stand-in album cover: deep blue with a big orange disc and white text

	NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize( 600, 600 )];
	[img lockFocus];
	[[NSColor colorWithSRGBRed:0.05 green:0.18 blue:0.55 alpha:1] setFill];
	NSRectFill( NSMakeRect( 0, 0, 600, 600 ));
	[[NSColor colorWithSRGBRed:0.98 green:0.55 blue:0.12 alpha:1] setFill];
	[[NSBezierPath bezierPathWithOvalInRect:NSMakeRect( 120, 140, 360, 360 )] fill];
	[@"LEDSA" drawAtPoint:NSMakePoint( 150, 40 ) withAttributes:@{ NSFontAttributeName : [NSFont boldSystemFontOfSize:96],
																	NSForegroundColorAttributeName : [NSColor whiteColor] }];
	[img unlockFocus];

	NSBitmapImageRep* rep = [[NSBitmapImageRep alloc] initWithData:img.TIFFRepresentation];
	return [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
}


static void		StartSession( NSDictionary* settings )
{
	// fresh preferences for the plug-in, plus any overrides

	NSUserDefaults* d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
	[d removeObjectForKey:@"settings"];
	[d removeObjectForKey:@"user_presets"];
	[d removeObjectForKey:@"current_preset"];
	if ( settings )
		[d setObject:settings forKey:@"settings"];
	[d synchronize];

	VisualPluginMessageInfo info;
	memset( &info, 0, sizeof( info ));
	info.u.initMessage.messageMajorVersion = kITVisualPluginMajorMessageVersion;
	info.u.initMessage.messageMinorVersion = kITVisualPluginMinorMessageVersion;
	info.u.initMessage.appVersion.majorRev = 10;
	info.u.initMessage.appVersion.minorAndBugRev = 0x70;
	info.u.initMessage.appVersion.stage = finalStage;
	info.u.initMessage.appCookie = (void*) 0x1234;
	info.u.initMessage.appProc = AppProc;

	OSStatus err = gRegistration.handler( kVisualPluginInitMessage, &info, gRegistration.registerRefCon );
	gRefCon = info.u.initMessage.refCon;
	EXPECT( err == noErr && gRefCon != NULL, "visual init returns a refCon" );

	gContainer = [[NSView alloc] initWithFrame:NSMakeRect( 0, 0, 1280, 720 )];
	
	gWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect( 40, 40, 1280, 720 ) styleMask:NSWindowStyleMaskBorderless
											backing:NSBackingStoreBuffered defer:NO];
	gWindow.releasedWhenClosed = NO;
	gWindow.contentView = gContainer;
	[gWindow orderFrontRegardless];

	memset( &info, 0, sizeof( info ));
	info.u.activateMessage.view = (NSOpenGLView*) gContainer;
	err = Send( kVisualPluginActivateMessage, &info );
	EXPECT( err == noErr && PluginView() != nil, "activate adds the visualizer view" );
	EXPECT( PluginView().layer.sublayers.count > 0, "visualizer view has a layer tree" );

	ITTrackInfo track;
	ITStreamInfo stream;
	memset( &track, 0, sizeof( track ));
	memset( &stream, 0, sizeof( stream ));
	track.recordLength = sizeof( track );
	track.validFields = kITTINameFieldMask | kITTIArtistFieldMask | kITTIAlbumFieldMask | kITTIYearFieldMask | kITTITotalTimeFieldMask;
	SetUniStr( track.name, @"Sahara Mahala" );
	SetUniStr( track.artist, @"The Jezabels" );
	SetUniStr( track.album, @"Dark Storm - EP" );
	track.year = 2011;
	track.totalTimeInMS = 303000;

	memset( &info, 0, sizeof( info ));
	info.u.playMessage.trackInfo = &track;
	info.u.playMessage.streamInfo = &stream;
	info.u.playMessage.audioFormat.mSampleRate = 44100;
	info.u.playMessage.audioFormat.mChannelsPerFrame = 2;
	info.u.playMessage.bitRate = 256;
	gArtworkRequests = 0;
	err = Send( kVisualPluginPlayMessage, &info );
	EXPECT( err == noErr, "play message accepted" );
	EXPECT( gArtworkRequests > 0, "plug-in requests cover art when playback starts" );
	gPosition = 219000;
}


static void		EndSession()
{
	VisualPluginMessageInfo info;
	memset( &info, 0, sizeof( info ));

	EXPECT( Send( kVisualPluginStopMessage, &info ) == noErr, "stop accepted" );
	EXPECT( Send( kVisualPluginDeactivateMessage, &info ) == noErr, "deactivate accepted" );
	EXPECT( PluginView() == nil, "deactivate removes the visualizer view" );
	EXPECT( Send( kVisualPluginCleanupMessage, &info ) == noErr, "cleanup accepted" );
	gRefCon = NULL;
	[gWindow orderOut:nil];
	gWindow = nil;
	gContainer = nil;
}


static NSWindow*	OptionsWindow()
{
	for ( NSWindow* w in NSApp.windows )
		if ( [w.title isEqualToString:@"LED Spectrum Analyser Options"] )
			return w;
	return nil;
}


int main( int argc, const char* argv[] )
{
	@autoreleasepool
	{
		if ( argc < 3 )
		{
			fprintf( stderr, "usage: %s <bundle> <output dir>\n", argv[0] );
			return 2;
		}

#if defined( __arm64__ )
		printf( "harness architecture: arm64\n" );
#else
		printf( "harness architecture: x86_64\n" );
#endif
		printf( "API layout: sizeof(VisualPluginMessageInfo) %zu, PlayerMessageInfo %zu, ITTrackInfo %zu, RenderVisualData %zu, "
				"offsetof(initMessage.appCookie) %zu, offsetof(pulseMessage.currentPositionInMS) %zu, offsetof(playMessage.audioFormat) %zu\n",
				sizeof( VisualPluginMessageInfo ), sizeof( PlayerMessageInfo ), sizeof( ITTrackInfo ), sizeof( RenderVisualData ),
				offsetof( VisualPluginInitMessage, appCookie ), offsetof( VisualPluginPulseMessage, currentPositionInMS ),
				offsetof( VisualPluginPlayMessage, audioFormat ));

		gOutDir = @( argv[2] );
		[[NSFileManager defaultManager] createDirectoryAtPath:gOutDir withIntermediateDirectories:YES attributes:nil error:NULL];

		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
		[NSApp finishLaunching];

		// load the plug-in exactly as a host does

		NSBundle* bundle = [NSBundle bundleWithPath:@( argv[1] )];
		NSString* exe = bundle.executablePath;
		EXPECT( exe != nil, "bundle has an executable" );
		EXPECT( [bundle.infoDictionary[@"CFBundlePackageType"] isEqualToString:@"hvpl"], "bundle package type is hvpl" );

		void* lib = exe? dlopen( exe.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL ) : NULL;
		if ( lib == NULL )
		{
			fprintf( stderr, "FAIL: dlopen: %s\n", dlerror());
			return 1;
		}

		PluginProcPtr mainProc = (PluginProcPtr) dlsym( lib, "iTunesPluginMainMachO" );
		EXPECT( mainProc != NULL, "iTunesPluginMainMachO is exported" );
		if ( mainProc == NULL )
			return 1;

		PluginMessageInfo pmi;
		memset( &pmi, 0, sizeof( pmi ));
		pmi.u.initMessage.majorVersion = kITPluginMajorMessageVersion;
		pmi.u.initMessage.minorVersion = kITPluginMinorMessageVersion;
		pmi.u.initMessage.appCookie = (void*) 0x1234;
		pmi.u.initMessage.appProc = AppProc;

		EXPECT( mainProc( kPluginInitMessage, &pmi, NULL ) == noErr && gRegistered, "plug-in registers a visualizer" );
		if ( ! gRegistered )
			return 1;

		NSString* name = [NSString stringWithCharacters:&gRegistration.name[1] length:gRegistration.name[0]];
		char creator[5] = { (char)( gRegistration.creator >> 24 ), (char)( gRegistration.creator >> 16 ), (char)( gRegistration.creator >> 8 ), (char) gRegistration.creator, 0 };
		printf( "      registered '%s', options 0x%x, creator '%s', %u spectrum / %u waveform channels, pulse %u Hz, version %d.%x\n",
				name.UTF8String, (unsigned) gRegistration.options, creator,
				(unsigned) gRegistration.numSpectrumChannels, (unsigned) gRegistration.numWaveformChannels, (unsigned) gRegistration.pulseRateInHz,
				gRegistration.pluginVersion.majorRev, gRegistration.pluginVersion.minorAndBugRev );
		EXPECT( [name isEqualToString:@"LED Spectrum Analyser"], "visualizer name" );
		EXPECT( gRegistration.handler != NULL, "handler supplied" );
		EXPECT(( gRegistration.options & kVisualUsesSubview ) && ( gRegistration.options & kVisualWantsConfigure ), "uses a subview and offers options" );
		EXPECT( gRegistration.numSpectrumChannels == 2 && gRegistration.numWaveformChannels == 2, "asks for stereo spectrum and waveform" );

		// ---- session 1: each layout. Without a GPU the screenshots come from a
		// software renderer that can't draw perspective or the reflection's fade; those are
		// switched off here and exercised separately below ----
		
		StartSession( @{ @"showProgress" : @"1", @"trackInfoMask" : @"3", @"perspective" : @"0", @"reflections" : @"0" } );
		Run( 1.5 );
		Snapshot( @"01-side-by-side" );
		
		Key( @"x" );
		Run( 1.0 );
		Snapshot( @"02-back-to-back" );
		
		Key( @"x" );
		Run( 1.5, 0.85 );
		Snapshot( @"03-analogue-vu" );
		
		Key( @"x" );
		Key( @"t" );		// track info above
		Key( @"." );		// 24 bands
		Key( @"." );		// 31 bands
		Key( @"y" );		// add the year
		Run( 1.0 );
		Snapshot( @"04-31-bands-text-above" );
		
		Key( @"=" );		// diagnostics
		Run( 1.2 );
		Snapshot( @"05-diagnostics" );
		Key( @"=" );
		
		Key( @"h" );		// perspective on
		Key( @"f" );		// reflections on
		Run( 1.0 );
		Snapshot( @"11-perspective-and-reflections-software-render" );
		
		// options window

		VisualPluginMessageInfo info;
		memset( &info, 0, sizeof( info ));
		EXPECT( Send( kVisualPluginConfigureMessage, &info ) == noErr, "configure accepted" );
		SpinRunLoop( 0.2 );
		NSWindow* options = OptionsWindow();
		EXPECT( options != nil, "configure opens the options window" );

		if ( options )
		{
			Key( @"1" );
			SnapshotWindow( options, @"06-options-layout" );
			Key( @"2" );
			SnapshotWindow( options, @"07-options-appearance" );
			Key( @"3" );
			SnapshotWindow( options, @"08-options-advanced" );
			[options orderOut:nil];
		}

		// presets survive into the preferences

		Key( @"z" );
		NSUserDefaults* d = [[NSUserDefaults alloc] initWithSuiteName:kDomain];
		EXPECT( [[d arrayForKey:@"user_presets"] count] == 1, "z saves a preset to the preferences" );
		EXPECT( [[d dictionaryForKey:@"settings"][@"numberOfSpectrumBars"] isEqualToString:@"31"], "settings are saved to the preferences" );

		// paused the way Music pauses: no stop message, and the last data repeated

		Run( 0.5 );
		uint32_t rate = 60;
		for ( int i = 0; i < 400; i++ )
		{
			rate = SendPulse( &gRenderData, rate );
			SpinRunLoop( 1.0 / 60 );
		}
		printf( "      pulse rate requested while the host repeats stale data: %u Hz\n", (unsigned) rate );
		EXPECT( rate < 60, "a host repeating stale data is treated as paused" );

		Run( 0.5 );
		rate = SendPulse( &gRenderData, 60 );
		EXPECT( rate == 60, "changing data resumes playback" );

		// silence: the plug-in should settle and ask for fewer pulses

		memset( &info, 0, sizeof( info ));
		Send( kVisualPluginStopMessage, &info );
		rate = 60;
		for ( int i = 0; i < 400; i++ )
		{
			rate = SendPulse( NULL, rate );
			SpinRunLoop( 1.0 / 60 );
		}
		printf( "      idle pulse rate requested: %u Hz\n", (unsigned) rate );
		EXPECT( rate < 60, "idle visualizer lowers its pulse rate" );

		EndSession();

		// ---- session 2: cover art as background with artwork colours ----

		StartSession( @{ @"coverArtBackgroundEffect" : @"1", @"coverArtColours" : @"1", @"showProgress" : @"1",
						  @"trackInfoMask" : @"7" } );
		NSData* art = MakeCoverArt();
		memset( &info, 0, sizeof( info ));
		info.u.coverArtMessage.coverArt = (__bridge CFDataRef) art;
		info.u.coverArtMessage.coverArtSize = (UInt32) art.length;
		info.u.coverArtMessage.coverArtFormat = kVisualCoverArtFormatPNG;
		EXPECT( Send( kVisualPluginCoverArtMessage, &info ) == noErr, "cover art accepted" );
		Run( 2.0 );
		Snapshot( @"09-cover-art-centred" );
		Run( 6.0 );
		Snapshot( @"10-cover-art-background" );
		EndSession();

		// ---- performance ----

		std::vector<double> t = gPulseTimes;
		std::sort( t.begin(), t.end());
		if ( ! t.empty())
		{
			double sum = 0;
			for ( double v : t ) sum += v;
			printf( "pulse handling (meters + layer updates, %zu pulses): mean %.3f ms, median %.3f ms, 95th %.3f ms, max %.3f ms\n",
					t.size(), sum / t.size(), t[t.size() / 2], t[( t.size() * 95 ) / 100], t.back());
		}

		mainProc( kPluginCleanupMessage, &pmi, NULL );

		printf( gFailures? "%d FAILURE(S)\n" : "all harness checks passed\n", gFailures );
		return gFailures? 1 : 0;
	}
}
