/*
 *  PlugInMain.mm
 *  LED Spectrum Analyser
 *
 *  Entry point and message handling for the iTunes Visual Plug-in API (SDK 2.0, message version
 *  10.7), which is what iTunes 10.4+ (including the 10.7 that Retroactive installs) and the macOS
 *  Music app use. Built as a universal binary: arm64 for Music on Apple Silicon, x86_64 for Intel
 *  Macs and for iTunes 10.7 running under Rosetta.
 *
 */

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <IOKit/pwr_mgt/IOPMLib.h>

// the SDK types the host view as NSOpenGLView (deprecated since 10.14); we only ever treat it as an NSView
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#include "iTunesVisualAPI.h"
#pragma clang diagnostic pop

#include "LEDEngine.h"

#import "LEDSAView.h"
#import "LEDSARenderer.h"
#import "LEDSAOptionsController.h"

using namespace led;


#define kVisualizerName				@"LED Spectrum Analyser"
#define kPreferencesDomain			@"io.github.nba28.LEDSpectrumAnalyser"
#define kManualResource				@"LED Spectrum Analyser Manual"

enum
{
	kLEDSACreator				= 'LEDS',
	kLEDSAMajorVersion			= 3,
	kLEDSAMinorVersion			= 0x10,		// 3.1
	kLEDSAReleaseStage			= finalStage,
	kLEDSANonFinalRelease		= 0,
	kActivePulseRate			= 60,		// Hz, while anything is moving
	kIdlePulseRate				= 10		// Hz, when nothing is (saves energy, as 3.0.5 did)
};


extern "C" OSStatus iTunesPluginMainMachO( OSType message, PluginMessageInfo* messageInfo, void* refCon ) __attribute__(( visibility( "default" )));


static double	Now()
{
	return CACurrentMediaTime();
}


static NSString*	StringFromUniStr( const ITUniStr255 s )
{
	UniChar len = MIN( s[0], (UniChar) 255 );
	return len? [NSString stringWithCharacters:&s[1] length:len] : @"";
}


static std::string	StdString( NSString* s )
{
	const char* utf8 = s.UTF8String;
	return utf8? std::string( utf8 ) : std::string();
}


@class LEDSAPlugIn;

class HostBridge : public EngineHost
{
public:
	__weak LEDSAPlugIn*		owner;

	virtual void	OpenOptions();
	virtual void	SettingsDidChange();
	virtual void	PresetsDidChange();
};


@interface LEDSAPlugIn : NSObject <LEDSAViewDelegate, LEDSAOptionsDelegate>
{
@public
	void*					appCookie;
	ITAppProcPtr			appProc;
	Engine*					engine;
	HostBridge				bridge;
	NSView*					hostView;
	LEDSAView*				view;
	LEDSARenderer*			renderer;
	LEDSAOptionsController*	options;
	NSUserDefaults*			defaults;
	IOPMAssertionID			sleepAssertion;
	BOOL					sleepAssertionHeld;
	BOOL					loading;
}
@end


@implementation LEDSAPlugIn

- (instancetype)initWithCookie:(void*)cookie proc:(ITAppProcPtr)proc
{
	self = [super init];

	if ( self )
	{
		appCookie = cookie;
		appProc = proc;
		bridge.owner = self;
		engine = new Engine( &bridge );
		defaults = [[NSUserDefaults alloc] initWithSuiteName:kPreferencesDomain];
		[self loadSettings];
	}
	return self;
}


- (void)cleanup
{
	[self saveSettings];
	[self deactivate];
	[options close];
	options = nil;
	delete engine;
	engine = NULL;
}


#pragma mark preferences

static NSDictionary*	NSDictionaryFromDictionary( const Dictionary& d )
{
	NSMutableDictionary* out = [NSMutableDictionary dictionary];

	for ( Dictionary::const_iterator it = d.begin(); it != d.end(); ++it )
		out[ @( it->first.c_str()) ] = @( it->second.c_str());
	return out;
}


static Dictionary	DictionaryFromNSDictionary( NSDictionary* d )
{
	Dictionary out;

	if ( ! [d isKindOfClass:[NSDictionary class]] )
		return out;

	for ( id key in d )
	{
		id value = d[key];

		if ( [key isKindOfClass:[NSString class]] && [value isKindOfClass:[NSString class]] )
			out[ StdString( key ) ] = StdString( value );
	}
	return out;
}


// settings are kept per host app, so Music and iTunes can each have their own (Spectrum Gain in
// particular); presets are shared. A host with no settings of its own starts from the shared ones.

static NSString*	HostSettingsKey()
{
	NSString* host = NSBundle.mainBundle.bundleIdentifier;

	return host.length? [@"settings." stringByAppendingString:host] : @"settings";
}


- (void)loadSettings
{
	loading = YES;

	NSDictionary* stored = [defaults dictionaryForKey:HostSettingsKey()];

	if ( stored == nil )
		stored = [defaults dictionaryForKey:@"settings"];

	engine->GetSettings().FromDictionary( DictionaryFromNSDictionary( stored ));

	std::vector<Dictionary> presets;

	for ( id p in [defaults arrayForKey:@"user_presets"] )
		presets.push_back( DictionaryFromNSDictionary( p ));

	engine->SetPresets( presets, (int) [defaults integerForKey:@"current_preset"] );
	engine->SettingsEdited( Now());
	loading = NO;
}


- (void)saveSettings
{
	if ( engine == NULL || loading )
		return;

	NSDictionary* settings = NSDictionaryFromDictionary( engine->GetSettings().ToDictionary());

	[defaults setObject:settings forKey:HostSettingsKey()];
	[defaults setObject:settings forKey:@"settings"];		// the starting point for a host seen for the first time
}


- (void)savePresets
{
	if ( engine == NULL || loading )
		return;

	NSMutableArray* presets = [NSMutableArray array];

	for ( size_t i = 0; i < engine->Presets().size(); i++ )
		[presets addObject:NSDictionaryFromDictionary( engine->Presets()[i] )];

	[defaults setObject:presets forKey:@"user_presets"];
	[defaults setInteger:engine->CurrentPreset() forKey:@"current_preset"];
}


- (void)settingsDidChange
{
	[self saveSettings];
	[options refresh];
	[self updateSleepAssertion];
	[renderer updateAtTime:Now()];
}


#pragma mark activation

- (void)activateWithView:(NSView*)destView
{
	[self deactivate];

	hostView = destView;

	if ( hostView == nil )
		return;

	view = [[LEDSAView alloc] initWithFrame:hostView.bounds];
	view.delegate = self;
	renderer = [[LEDSARenderer alloc] initWithRootLayer:view.layer engine:engine];
	[hostView addSubview:view];

	[renderer setViewSize:view.bounds.size scale:( view.window? view.window.backingScaleFactor : NSScreen.mainScreen.backingScaleFactor )];
	[renderer updateAtTime:Now()];

	[self requestArtwork];
	[self updateSleepAssertion];
}


- (void)deactivate
{
	[view removeFromSuperview];
	view.delegate = nil;
	view = nil;
	renderer = nil;
	hostView = nil;
	[self updateSleepAssertion];
}


- (void)hostViewChanged
{
	if ( view && hostView )
		view.frame = hostView.bounds;
}


#pragma mark playback

- (void)updateTrack:(ITTrackInfo*)trackInfo stream:(ITStreamInfo*)streamInfo
{
	TrackInfo info;

	if ( trackInfo )
	{
		ITTIFieldMask valid = trackInfo->validFields;

		if ( valid & kITTINameFieldMask )		info.title = StdString( StringFromUniStr( trackInfo->name ));
		if ( valid & kITTIArtistFieldMask )		info.artist = StdString( StringFromUniStr( trackInfo->artist ));
		if ( valid & kITTIAlbumFieldMask )		info.album = StdString( StringFromUniStr( trackInfo->album ));
		if (( valid & kITTIYearFieldMask ) && trackInfo->year > 0 )
			info.year = StdString( [NSString stringWithFormat:@"%u", (unsigned) trackInfo->year] );
		if ( valid & kITTITotalTimeFieldMask )	info.totalTimeMS = trackInfo->totalTimeInMS;
	}

	if ( streamInfo )
	{
		// streams: iTunes puts the station in the track name, and "Artist - Title" in the stream title

		NSString* streamTitle = StringFromUniStr( streamInfo->streamTitle );
		NSString* streamName = StringFromUniStr( streamInfo->streamName );

		if ( streamTitle.length )
		{
			if ( info.stationIdent.empty())
				info.stationIdent = streamName.length? StdString( streamName ) : info.title;

			info.title.clear();
			info.artist.clear();
			ApplyStreamTitle( StdString( streamTitle ), &info );
		}
		else if ( streamName.length )
			info.stationIdent = StdString( streamName );
	}

	engine->SetTrack( info, Now());
}


- (void)setPlaying:(BOOL)isPlaying
{
	engine->SetPlaying( isPlaying, Now());
	[self updateSleepAssertion];
}


- (void)pulse:(VisualPluginPulseMessage*)msg
{
	double now = Now();
	RenderVisualData* rd = msg->renderData;

	const uint8_t ( *spectrum )[kSpectrumEntries] = NULL;
	const uint8_t ( *waveform )[kWaveformEntries] = NULL;
	int nSpectrum = 0, nWaveform = 0;

	if ( rd )
	{
		if ( rd->numSpectrumChannels > 0 )
		{
			spectrum = rd->spectrumData;
			nSpectrum = MIN( (int) rd->numSpectrumChannels, kVisualMaxDataChannels );
		}
		if ( rd->numWaveformChannels > 0 )
		{
			waveform = rd->waveformData;
			nWaveform = MIN( (int) rd->numWaveformChannels, kVisualMaxDataChannels );
		}
	}

	// the engine starts playing on its own when it is activated part way through a track, and
	// stops when the host pauses but keeps sending its last data (as Music does)

	BOOL wasPlaying = engine->IsPlaying();

	engine->Pulse( spectrum, nSpectrum, waveform, nWaveform, msg->currentPositionInMS, now );

	if ( engine->IsPlaying() != wasPlaying )
		[self updateSleepAssertion];

	if ( renderer )
		[renderer updateAtTime:now];

	msg->newPulseRateInHz = engine->IsAnimating( now )? kActivePulseRate : kIdlePulseRate;
}


#pragma mark cover art

- (void)requestArtwork
{
	if ( view )
		PlayerRequestCurrentTrackCoverArt( appCookie, appProc );
}


static bool	AnalyseImage( CGImageRef image, ArtworkColours* out )
{
	const int side = 64;
	CGColorSpaceRef space = CGColorSpaceCreateWithName( kCGColorSpaceSRGB );
	CGContextRef ctx = CGBitmapContextCreate( NULL, side, side, 8, side * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big );
	CGColorSpaceRelease( space );

	if ( ctx == NULL )
		return false;

	CGContextSetInterpolationQuality( ctx, kCGInterpolationMedium );
	CGContextDrawImage( ctx, CGRectMake( 0, 0, side, side ), image );
	*out = AnalyseArtwork(( const uint8_t* ) CGBitmapContextGetData( ctx ), side, side, (int) CGBitmapContextGetBytesPerRow( ctx ));
	CGContextRelease( ctx );
	return true;
}


- (void)coverArt:(CFDataRef)data
{
	CGImageRef image = NULL;
	NSImage* nsImage = nil;

	if ( data && CFDataGetLength( data ) > 0 )
	{
		nsImage = [[NSImage alloc] initWithData:(__bridge NSData*) data];
		image = [nsImage CGImageForProposedRect:NULL context:nil hints:nil];
	}

	ArtworkColours colours;
	bool analysed = image && AnalyseImage( image, &colours );

	[renderer setArtwork:image];
	engine->SetArtwork( image != NULL, analysed? &colours : NULL, Now());
}


#pragma mark sleep

- (void)updateSleepAssertion
{
	BOOL want = engine && view && engine->IsPlaying() && engine->GetSettings().preventSleep;

	if ( want && ! sleepAssertionHeld )
	{
		sleepAssertionHeld = ( IOPMAssertionCreateWithName( kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn,
															 CFSTR( "LED Spectrum Analyser visualizer is showing" ), &sleepAssertion ) == kIOReturnSuccess );
	}
	else if ( ! want && sleepAssertionHeld )
	{
		IOPMAssertionRelease( sleepAssertion );
		sleepAssertionHeld = NO;
	}
}


#pragma mark options and manual

- (void)showOptions
{
	if ( options == nil )
	{
		options = [[LEDSAOptionsController alloc] init];
		options.delegate = self;
	}
	[options showWindow];
}


- (void)showManual
{
	NSBundle* bundle = [NSBundle bundleForClass:[self class]];
	NSURL* url = [bundle URLForResource:kManualResource withExtension:@"html"];

	if ( url )
		[[NSWorkspace sharedWorkspace] openURL:url];
}


- (Engine*)optionsEngine				{ return engine; }
- (double)optionsCurrentTime			{ return Now(); }
- (void)optionsShowManual				{ [self showManual]; }


#pragma mark view delegate

- (void)visualizerView:(NSView*)v didResize:(NSSize)size scale:(CGFloat)scale
{
	[renderer setViewSize:size scale:scale];
	[renderer updateAtTime:Now()];
}


- (BOOL)visualizerView:(NSView*)v handleCharacter:(unichar)character
{
	double now = Now();

	// with the options window open, 1-3 pick its tabs as in 2.x; otherwise they recall presets

	if ( options.isOpen && character >= '1' && character <= '3' )
	{
		[options selectTab:character - '1'];
		return YES;
	}

	BOOL handled = engine->HandleKey( character, now );

	if ( handled )
		[renderer updateAtTime:now];

	return handled;
}


- (void)visualizerViewShowOptions:(NSView*)v	{ [self showOptions]; }
- (void)visualizerViewShowManual:(NSView*)v		{ [self showManual]; }

@end


void	HostBridge::OpenOptions()			{ [owner showOptions]; }
void	HostBridge::SettingsDidChange()		{ [owner settingsDidChange]; }
void	HostBridge::PresetsDidChange()		{ [owner savePresets]; }


#pragma mark - message handler

static OSStatus	VisualPluginHandler( OSType message, VisualPluginMessageInfo* messageInfo, void* refCon )
{
	@autoreleasepool
	{
		LEDSAPlugIn* plugin = (__bridge LEDSAPlugIn*) refCon;
		OSStatus status = noErr;

		switch ( message )
		{
			case kVisualPluginInitMessage:
			{
				LEDSAPlugIn* p = [[LEDSAPlugIn alloc] initWithCookie:messageInfo->u.initMessage.appCookie
																 proc:messageInfo->u.initMessage.appProc];
				if ( p == nil )
				{
					status = memFullErr;
					break;
				}

				NSString* host = [NSBundle mainBundle].infoDictionary[@"CFBundleName"];
				NumVersion v = messageInfo->u.initMessage.appVersion;
				uint32_t packed = ((uint32_t) v.majorRev << 24 ) | ((uint32_t) v.minorAndBugRev << 16 ) | ((uint32_t) v.stage << 8 ) | v.nonRelRev;

				p->engine->SetHostInfo( StdString( host? host : NSProcessInfo.processInfo.processName ), packed,
										messageInfo->u.initMessage.messageMajorVersion, messageInfo->u.initMessage.messageMinorVersion );

				messageInfo->u.initMessage.refCon = (void*) CFBridgingRetain( p );
				break;
			}

			case kVisualPluginCleanupMessage:
				if ( plugin )
				{
					[plugin cleanup];
					CFBridgingRelease( refCon );
				}
				break;

			case kVisualPluginEnableMessage:
			case kVisualPluginDisableMessage:
			case kVisualPluginIdleMessage:
			case kVisualPluginDisplayChangedMessage:
			case kVisualPluginSetPositionMessage:
				break;

			case kVisualPluginConfigureMessage:
				[plugin showOptions];
				break;

			case kVisualPluginActivateMessage:
				[plugin activateWithView:(NSView*) messageInfo->u.activateMessage.view];
				break;

			case kVisualPluginDeactivateMessage:
				[plugin deactivate];
				break;

			case kVisualPluginWindowChangedMessage:
			case kVisualPluginFrameChangedMessage:
				[plugin hostViewChanged];
				break;

			case kVisualPluginPulseMessage:
				[plugin pulse:&messageInfo->u.pulseMessage];
				break;

			case kVisualPluginDrawMessage:
				// we draw with our own layer-hosting subview
				break;

			case kVisualPluginPlayMessage:
			{
				const AudioStreamBasicDescription& fmt = messageInfo->u.playMessage.audioFormat;
				plugin->engine->SetAudioFormat( fmt.mSampleRate, fmt.mChannelsPerFrame );
				[plugin updateTrack:messageInfo->u.playMessage.trackInfo stream:messageInfo->u.playMessage.streamInfo];
				[plugin setPlaying:YES];
				[plugin requestArtwork];
				break;
			}

			case kVisualPluginChangeTrackMessage:
				[plugin updateTrack:messageInfo->u.changeTrackMessage.trackInfo stream:messageInfo->u.changeTrackMessage.streamInfo];
				[plugin requestArtwork];
				break;

			case kVisualPluginStopMessage:
				[plugin setPlaying:NO];
				break;

			case kVisualPluginCoverArtMessage:
				[plugin coverArt:(CFDataRef) messageInfo->u.coverArtMessage.coverArt];
				break;

			default:
				status = unimpErr;
				break;
		}

		return status;
	}
}


#pragma mark - registration

static OSStatus	RegisterVisualPlugin( PluginMessageInfo* messageInfo )
{
	PlayerMessageInfo playerMessageInfo;

	memset( &playerMessageInfo, 0, sizeof( playerMessageInfo ));

	PlayerRegisterVisualPluginMessage& reg = playerMessageInfo.u.registerVisualPluginMessage;

	NSString* name = kVisualizerName;
	NSUInteger len = MIN( name.length, (NSUInteger) 255 );
	reg.name[0] = (UniChar) len;
	[name getCharacters:&reg.name[1] range:NSMakeRange( 0, len )];

	SetNumVersion( &reg.pluginVersion, kLEDSAMajorVersion, kLEDSAMinorVersion, kLEDSAReleaseStage, kLEDSANonFinalRelease );

	reg.options				= kVisualWantsConfigure | kVisualUsesSubview | kVisualSupportsMuxedGraphics;
	reg.handler				= (VisualPluginProcPtr) VisualPluginHandler;
	reg.registerRefCon		= 0;
	reg.creator				= kLEDSACreator;
	reg.pulseRateInHz		= kIdlePulseRate;
	reg.numWaveformChannels	= 2;		// for the VU meters
	reg.numSpectrumChannels	= 2;
	reg.minWidth			= 64;
	reg.minHeight			= 64;
	reg.maxWidth			= 0;		// no limit
	reg.maxHeight			= 0;

	return PlayerRegisterVisualPlugin( messageInfo->u.initMessage.appCookie, messageInfo->u.initMessage.appProc, &playerMessageInfo );
}


OSStatus	iTunesPluginMainMachO( OSType message, PluginMessageInfo* messageInfo, void* refCon )
{
	(void) refCon;

	switch ( message )
	{
		case kPluginInitMessage:
			return RegisterVisualPlugin( messageInfo );

		case kPluginCleanupMessage:
		case kPluginPrepareToQuitMessage:
			return noErr;

		default:
			return unimpErr;
	}
}
