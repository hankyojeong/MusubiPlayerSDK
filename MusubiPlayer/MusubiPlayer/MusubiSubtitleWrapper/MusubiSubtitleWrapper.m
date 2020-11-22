//
//  MusubiSubtitleWrapper.m
//  MusubiPlayer
//
//  Created by HanGyo Jeong on 2020/11/19.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

#import "MusubiSubtitleWrapper.h"
#include "MusubiSubtitles.h"

@implementation MusubiSubtitleWrapper {
    MusubiSubtitles* musubiSubtitle;
}

- (void)initMusubiSubtitle:(NSString*)subtitlePath Type:(SubtitleType)type {
    musubiSubtitle = [[MusubiSubtitles alloc] init];
    
    [musubiSubtitle setSubtitleFile:subtitlePath];
}

- (NSMutableArray*) getSubtitleSet {
    return [musubiSubtitle getSubtitleSet];
}

@end
