//
//  TwilioVoiceReactNative.m
//  TwilioVoiceReactNative
//
//  Copyright © 2021 Twilio, Inc. All rights reserved.
//

#import "TwilioVoicePushRegistry.h"
#import "TwilioVoiceReactNative.h"

NSString * const kTwilioVoiceReactNativeEventVoice = @"Voice";
NSString * const kTwilioVoiceReactNativeEventCall = @"Call";

@import TwilioVoice;

@interface TwilioVoiceReactNative () <TVOCallDelegate>

@property (nonatomic, strong) NSMutableDictionary *callMap;
@property (nonatomic, strong) TVOCall *activeCall;
@property (nonatomic, strong) TVODefaultAudioDevice *audioDevice;

@end


@implementation TwilioVoiceReactNative

- (instancetype)init {
    if (self = [super init]) {
        _callMap = [NSMutableDictionary dictionary];
        _audioDevice = [TVODefaultAudioDevice audioDevice];
        TwilioVoiceSDK.audioDevice = _audioDevice;
        
        [self subscribeToNotifications];
    }

    return self;
}

- (void)subscribeToNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handlePushRegistryNotification:)
                                                 name:kTwilioVoicePushRegistryNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handlePushRegistryNotification:(NSNotification *)notification {
    NSDictionary *eventBody = notification.userInfo;
    if ([eventBody[kTwilioVoicePushRegistryType] isEqualToString:kTwilioVoicePushRegistryDeviceTokenUpdated]) {
        /**
           The listener might not have registered themselves at the time the pushRegistry:didUpdatePushCredentials:forType: callback is called.
           1-second wait does the job and the React Native binding can receive the event properly.
         */
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self sendEventWithName:kTwilioVoiceReactNativeEventVoice body:eventBody];
        });
    } else {
        [self sendEventWithName:kTwilioVoiceReactNativeEventVoice body:eventBody];
    }
}

RCT_EXPORT_MODULE();

#pragma mark - React Native

- (NSArray<NSString *> *)supportedEvents
{
  return @[kTwilioVoiceReactNativeEventVoice, kTwilioVoiceReactNativeEventCall];
}

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

#pragma mark - Bingings (Voice methods)

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(voice_getVersion)
{
    return TwilioVoiceSDK.sdkVersion;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(voice_connect:(NSString *)uuid
                                       accessToken:(NSString *)accessToken
                                       params:(NSDictionary *)params)
{
    TVOConnectOptions *connectOptions = [TVOConnectOptions optionsWithAccessToken:accessToken
                                                                            block:^(TVOConnectOptionsBuilder *builder) {
        builder.params = params;
        builder.uuid = [[NSUUID alloc] initWithUUIDString:uuid] ;
    }];
    self.activeCall = [TwilioVoiceSDK connectWithOptions:connectOptions delegate:self];
    self.callMap[uuid] = self.activeCall;

    return nil;
}

#pragma mark - Bingings (Call)

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_disconnect:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call disconnect];
    }

    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_getState:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    NSString *state = @"";
    if (call) {
        state = [self stringOfState:call.state];
    }
    
    return state;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_getSid:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    return (call && call.state != TVOCallStateConnecting)? call.sid : @"";
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_getFrom:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    return (call && [call.from length] > 0)? call.from : @"";
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_getTo:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    return (call && [call.to length] > 0)? call.to : @"";
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_hold:(NSString *)uuid
                                       onHold:(BOOL)onHold)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call setOnHold:onHold];
    }
    
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_isOnHold:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        return @(call.isOnHold);
    } else {
        return @(false);
    }
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_mute:(NSString *)uuid
                                       muted:(BOOL)muted)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call setMuted:muted];
    }
    
    return nil;
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_isMuted:(NSString *)uuid)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        return @(call.isMuted);
    } else {
        return @(false);
    }
}

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(call_sendDigits:(NSString *)uuid
                                       digits:(NSString *)digits)
{
    TVOCall *call = self.callMap[uuid];
    if (call) {
        [call sendDigits:digits];
    }
    
    return nil;
}

#pragma mark - utility

RCT_EXPORT_BLOCKING_SYNCHRONOUS_METHOD(util_generateId)
{
    return [[NSUUID UUID] UUIDString];
}

- (NSString *)stringOfState:(TVOCallState)state {
    switch (state) {
        case TVOCallStateConnecting:
            return @"connecting";
        case TVOCallStateRinging:
            return @"ringing";
        case TVOCallStateConnected:
            return @"conencted";
        case TVOCallStateReconnecting:
            return @"reconnecting";
        case TVOCallStateDisconnected:
            return @"disconnected";
        default:
            return @"connecting";
    }
}

#pragma mark - TVOCallDelegate

- (void)callDidStartRinging:(TVOCall *)call {
    NSLog(@"Call ringing.");
    self.audioDevice.enabled = YES;
    [self sendEventWithName:@"Call" body:@{@"type": @"ringing", @"uuid": [call.uuid UUIDString]}];
}

- (void)call:(TVOCall *)call didFailToConnectWithError:(NSError *)error {
    NSLog(@"Call failed to connect: %@.", error);
    [self sendEventWithName:@"Call" body:@{@"type": @"connectFailure", @"uuid": [call.uuid UUIDString], @"error": [error localizedDescription]}];

    // TODO: disconnect call with CallKit if needed
    // TODO: CallKit completion handler
}

- (void)call:(TVOCall *)call didDisconnectWithError:(NSError *)error {
    NSLog(@"Call disconnected with error: %@.", error);
    NSDictionary *messageBody = [NSDictionary dictionary];
    if (error) {
        messageBody = @{@"type": @"disconnected", @"uuid": [call.uuid UUIDString], @"error": [error localizedDescription]};
    } else {
        messageBody = @{@"type": @"disconnected", @"uuid": [call.uuid UUIDString]};
    }
    
    [self sendEventWithName:@"Call" body:messageBody];

    // TODO: end call with CallKit (if not user initiated-disconnect)
    // TODO: CallKit completion handler
}

- (void)callDidConnect:(TVOCall *)call {
    NSLog(@"Call connected.");
    [self sendEventWithName:@"Call" body:@{@"type": @"connected", @"uuid": [call.uuid UUIDString]}];

    // TODO: CallKit completion handler
    // TODO: report connected to CallKit
}

- (void)call:(TVOCall *)call isReconnectingWithError:(NSError *)error {
    NSLog(@"Call reconnecting: %@.", error);
    [self sendEventWithName:@"Call" body:@{@"type": @"connected", @"uuid": [call.uuid UUIDString], @"error": [error localizedDescription]}];
}

- (void)callDidReconnect:(TVOCall *)call {
    NSLog(@"Call reconnected.");
    [self sendEventWithName:@"Call" body:@{@"type": @"reconnected", @"uuid": [call.uuid UUIDString]}];
}

- (void)call:(TVOCall *)call
didReceiveQualityWarnings:(NSSet<NSNumber *> *)currentWarnings
previousWarnings:(NSSet<NSNumber *> *)previousWarnings {
    // TODO: process and emit warnings event
}

@end
