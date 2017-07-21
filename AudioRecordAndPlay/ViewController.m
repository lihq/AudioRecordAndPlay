//
//  ViewController.m
//  AudioRecordAndPlay
//
//  Created by lihuaqing on 2017/7/7.
//  Copyright © 2017年 lihuaqing. All rights reserved.
//

#import "ViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AudioUnit/AudioUnit.h>
#import <AVFoundation/AVFoundation.h>
#include "math.h"
#define handleError(error)  if(error){ NSLog(@"%@",error); exit(1);}

#define kSmaple     8000 //44100

#define kOutoutBus 0
#define kInputBus  1

extern char  FILE_NAME[256];
static FILE *fp=0;
static FILE *wfp =0;

static void CheckError(OSStatus error,const char *operaton){
    if (error==noErr) {
        return;
    }
    char errorString[20]={};
    *(UInt32 *)(errorString+1)=CFSwapInt32HostToBig(error);
    if (isprint(errorString[1])&&isprint(errorString[2])&&isprint(errorString[3])&&isprint(errorString[4])) {
        errorString[0]=errorString[5]='\'';
        errorString[6]='\0';
    }else{
        sprintf(errorString, "%d",(int)error);
    }
    fprintf(stderr, "Error:%s (%s)\n",operaton,errorString);
    exit(1);
}

@interface ViewController ()
{
    AURenderCallbackStruct      _inputProc;
    AURenderCallbackStruct      _outputProc;
    AudioStreamBasicDescription _audioFormat;
    AudioStreamBasicDescription mAudioFormat;
}
@property (nonatomic,weak)   AVAudioSession *session;
@property (nonatomic,assign) AudioUnit toneUnit;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    [self configAudio];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


OSStatus inputRenderTone(
                         void *inRefCon,
                         AudioUnitRenderActionFlags 	*ioActionFlags,
                         const AudioTimeStamp 		*inTimeStamp,
                         UInt32 						inBusNumber,
                         UInt32 						inNumberFrames,
                         AudioBufferList 			*ioData)

{
    ViewController *THIS=(__bridge ViewController*)inRefCon;
    
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mData = NULL;
    bufferList.mBuffers[0].mDataByteSize = 0;
    OSStatus status = AudioUnitRender(THIS->_toneUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      kInputBus,
                                      inNumberFrames,
                                      &bufferList);
    
    if (status==noErr) {
        
        if (wfp==0) {
            wfp = fopen(FILE_NAME, "wb");
        }
        if (wfp) {
            fwrite(bufferList.mBuffers[0].mData, 1, bufferList.mBuffers[0].mDataByteSize, wfp);
        }
        
    }
    
    
    return status;
}

OSStatus outputRenderTone(
                          void *inRefCon,
                          AudioUnitRenderActionFlags 	*ioActionFlags,
                          const AudioTimeStamp 		*inTimeStamp,
                          UInt32 						inBusNumber,
                          UInt32 						inNumberFrames,
                          AudioBufferList 			*ioData)

{
    //    ViewController *THIS=(__bridge ViewController*)inRefCon;
    
    //先置为静音包
    memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);

    
    
    NSString* filePath = [[NSBundle mainBundle] pathForResource:@"my" ofType:@"pcm"];
    const char *ptr = filePath.UTF8String;
    if(fp==0) fp =  fopen(ptr, "rb");
    if (fp) {
        UInt32 datalen = inNumberFrames*2;
        int len = fread((char*)ioData->mBuffers[0].mData, 1, datalen, fp);
        if (len<=0) {
            fseek(fp,0,SEEK_SET);
        }
    }
    return 0;
}


- (void)configAudio
{
    _inputProc.inputProc = inputRenderTone;
    _inputProc.inputProcRefCon = (__bridge void *)(self);
    _outputProc.inputProc = outputRenderTone;
    _outputProc.inputProcRefCon = (__bridge void *)(self);
    
    //对AudioSession的一些设置
    NSError *error;
    self.session = [AVAudioSession sharedInstance];
    [self.session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:&error]; //lihq
    handleError(error);
    
    [self.session setPreferredIOBufferDuration:0.020 error:&error];
    handleError(error);
    [self.session setPreferredSampleRate:kSmaple error:&error];
    handleError(error);
    
    
    //lihq
    [self.session setMode:AVAudioSessionModeVoiceChat
                    error:&error];
    handleError(error);
    
    
    
    [self.session setActive:YES error:&error];
    handleError(error);
    
    
    //    Obtain a RemoteIO unit instance
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO ; //kAudioUnitSubType_RemoteIO;  //kAudioUnitSubType_VoiceProcessingIO可以处理回音
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    AudioComponentInstanceNew(inputComponent, &_toneUnit);
    
    
    UInt32 enable = 1;
    AudioUnitSetProperty(_toneUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Input,
                         kInputBus,
                         &enable,
                         sizeof(enable));
    AudioUnitSetProperty(_toneUnit,
                         kAudioOutputUnitProperty_EnableIO,
                         kAudioUnitScope_Output,
                         kOutoutBus, &enable, sizeof(enable));
    
    mAudioFormat.mSampleRate         = kSmaple;//采样率
    mAudioFormat.mFormatID           = kAudioFormatLinearPCM;//PCM采样
    mAudioFormat.mFormatFlags        = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    mAudioFormat.mFramesPerPacket    = 1;//每个数据包多少帧
    mAudioFormat.mChannelsPerFrame   = 1;//1单声道，2立体声
    mAudioFormat.mBitsPerChannel     = 16;//语音每采样点占用位数
    mAudioFormat.mBytesPerFrame      = mAudioFormat.mBitsPerChannel*mAudioFormat.mChannelsPerFrame/8;//每帧的bytes数
    mAudioFormat.mBytesPerPacket     = mAudioFormat.mBytesPerFrame*mAudioFormat.mFramesPerPacket;//每个数据包的bytes总数，每帧的bytes数＊每个数据包的帧数
    mAudioFormat.mReserved           = 0;
    
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input, kOutoutBus,
                                    &mAudioFormat, sizeof(mAudioFormat)),
               "couldn't set the remote I/O unit's output client format");
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output, kInputBus,
                                    &mAudioFormat, sizeof(mAudioFormat)),
               "couldn't set the remote I/O unit's input client format");
    
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Output,
                                    kInputBus,
                                    &_inputProc, sizeof(_inputProc)),
               "couldnt set remote i/o render callback for input");
    
    CheckError(AudioUnitSetProperty(_toneUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Input,
                                    kOutoutBus,
                                    &_outputProc, sizeof(_outputProc)),
               "couldnt set remote i/o render callback for output");
    
    CheckError(AudioUnitInitialize(_toneUnit),
               "couldn't initialize the remote I/O unit");
}


- (IBAction)OnPlayOrStop:(UIButton *)sender {
    if (sender.selected == NO) {
        CheckError(AudioOutputUnitStart(_toneUnit), "couldn't start remote i/o unit");
        sender.selected = YES;
        [sender setTitle:@"Stop" forState:UIControlStateSelected];
    }else{
        CheckError(AudioOutputUnitStop(_toneUnit), "couldn't stop remote i/o unit");
        sender.selected = NO;
        [sender setTitle:@"Play" forState:UIControlStateNormal];
    }
    
    NSError *error;
    [self.session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:&error]; //lihq
    handleError(error);

}
- (IBAction)OnSpeaker:(id)sender {
    NSError *error;
    [self.session setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker
                        error:&error]; //lihq
    handleError(error);
}

@end
