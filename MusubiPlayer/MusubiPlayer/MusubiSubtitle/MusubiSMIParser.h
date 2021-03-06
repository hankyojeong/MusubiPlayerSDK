//
//  MusubiSMIParser.h
//  MusubiSubtitles
//
//  Created by HanGyo Jeong on 2020/11/19.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MusubiSubtitleParser.h"

NS_ASSUME_NONNULL_BEGIN

@interface MusubiSMIParser : MusubiSubtitleParser

- (id)initExternalSubtitleOverHTTP:(NSString*)subtitleURL;

@end

NS_ASSUME_NONNULL_END
