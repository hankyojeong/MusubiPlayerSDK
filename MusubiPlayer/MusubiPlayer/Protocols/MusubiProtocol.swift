//
//  MusubiProtocol.swift
//  MusubiPlayer
//
//  Created by HanGyo Jeong on 2020/10/09.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

import UIKit

// STUDY: why inherit 'class' protocol
protocol MusubiDelegate: class {
    func renderObject(drawable: CAMetalDrawable, pixelBuffer: CVPixelBuffer)
    func currentTime(time: Float64)
    func totalTime(time: Float64)
}

protocol MusubiPlayerAction: class {
    func open(_ mediaPath: String, mediaType: mediaType)
    func start()
    func pause()
    func getPlayerState() -> playerState
    func seek(_ time: Float)
}
