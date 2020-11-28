//
//  MusubiPlayer.swift
//  MusubiPlayer
//
//  Created by HanGyo Jeong on 2020/10/09.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

import UIKit
import Foundation
import MetalKit
import AVFoundation
import MobileCoreServices

private var musubiPlayer_version = "0.0.5.beta"

var ONE_FRAME_DURATION: Double {
    get {
        0.03
    }
}

public enum mediaType {
    case local
    case hls
    case dash
}

public enum playerState {
    case none
    case open
    case play
    case pause
}

enum hlsPlayListType {
    case none
    case master
    case vod
    case live
}

// Key-Value observing context
private var playerItemContext = 0

open class MusubiPlayer:NSObject, AVPlayerItemOutputPullDelegate {
    var device_: MTLDevice?
    var metalLayer_: CAMetalLayer?
    var pipelineState_: MTLRenderPipelineState?
    var commandQueue_: MTLCommandQueue?
    
    var avPlayer_: AVPlayer?
    var videoOutput_: AVPlayerItemVideoOutput?
    var m_type_: mediaType?
    
    var videoOutputQueue_: DispatchQueue?
    var timer_: CADisplayLink?
    var lastFrameTimestamp_: CFTimeInterval?
    
    var mediaContentPath_: String?
    
    var currentPlayTime_: CMTime?
    var totalPlayTime_: CMTime?
    
    open weak var musubiDelegate: MusubiDelegate?
    
    var objectToDraw_: SquarePlain?
    
    var musubiPlayerState: playerState = .none
    var musubiDispatchQueue: DispatchQueue?
    
    let subtitleWrapper: MusubiSubtitleWrapper? = MusubiSubtitleWrapper()
    var subtitleIndex: NSInteger = 0
    
    public init(_ videoPlayerView: UIView) {
        super.init()
        
        NSLog("MusubiPlayer Version: \(musubiPlayer_version)")
        
        device_ = MTLCreateSystemDefaultDevice()
        metalLayer_ = CAMetalLayer()
        
        if let metalDevice = device_, let metalLayer = metalLayer_ {
            metalLayer.device = metalDevice
            metalLayer.pixelFormat = .bgra8Unorm
            metalLayer.framebufferOnly = true
//            metalLayer.frame = videoPlayerView.layer.frame
            metalLayer.frame = videoPlayerView.bounds
//            metalLayer.frame.size.width -= 40
            NSLog("metalLayer Frame: \(metalLayer.frame)")
//            metalLayer.bounds = videoPlayerView.layer.bounds
            //            videoPlayerView.layer.addSublayer(metalLayer)
            videoPlayerView.layer.insertSublayer(metalLayer, at: 0)
            
            let frameworkBundle = Bundle(for: MusubiPlayer.self)
            let defaultLibrary = try! metalDevice.makeDefaultLibrary(bundle: frameworkBundle)
            let vertexProgram = defaultLibrary.makeFunction(name: "basic_vertex")
            let fragmentProgram = defaultLibrary.makeFunction(name: "basic_fragment")
            
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            
            pipelineState_ = try! metalDevice.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
            commandQueue_ = metalDevice.makeCommandQueue()
            
        }
        
        timer_ = CADisplayLink.init(target: self, selector: #selector(newFrame))
        timer_?.add(to: .main, forMode: .default)

        // Setup AVPlayerItemVideoOutput with the required pixelbuffer attributes
        var pixelBufferAttributes: NSDictionary = [kCVPixelBufferMetalCompatibilityKey:true, kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput_ = AVPlayerItemVideoOutput.init(pixelBufferAttributes: pixelBufferAttributes as! [String: Any])
        videoOutputQueue_ = DispatchQueue(label: "VideoOutputQueue")
        videoOutput_?.setDelegate(self, queue: videoOutputQueue_)
        
        if let device = device_, let commandQueue = commandQueue_ {
            objectToDraw_ = SquarePlain.init(device, commandQ: commandQueue)
        }
        
        avPlayer_ = AVPlayer()
        
        addPeriodicTimeObserver()
    }
    
    @objc func newFrame(displayLink: CADisplayLink) {
        /*
         The Callback gets called once every vsync
         Using the display link's timestamp and duration we can compute the next time the screen will be refreshed, and copy the pixel buffer for that time.
         This pixelbuffer can then be processed and later rendered on screen
         */
        var outputItemTime: CMTime = .invalid
        
        // Calculate the nextVSync time which is when the screen will be refreshed next
        let nextVSync: CFTimeInterval = (displayLink.timestamp + displayLink.duration)
        
        if let videoOutput = videoOutput_ {
            outputItemTime = videoOutput.itemTime(forHostTime: nextVSync)
            
            var pixelBuffer: CVPixelBuffer?
            if videoOutput.hasNewPixelBuffer(forItemTime: outputItemTime) {
                pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: outputItemTime, itemTimeForDisplay: nil)
            }

            if 0.0 == lastFrameTimestamp_ {
                lastFrameTimestamp_ = displayLink.timestamp
            }

//            var elapsed: TimeInterval = displayLink.timestamp - lastFrameTimestamp
            lastFrameTimestamp_ = displayLink.timestamp

            // AutoRelease
            let drawable: CAMetalDrawable? = metalLayer_?.nextDrawable()
            if let pixelBufferData = pixelBuffer, let drawableData = drawable {
                musubiDelegate?.renderObject(drawable: drawableData, pixelBuffer: pixelBufferData)

                renderObject(drawable: drawableData, pixelBuffer: pixelBufferData)
            }
        }
    }
    
    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 1.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        
        // Add time observer. Invoke closure on the main queue
        if let avPlayer = avPlayer_ {
            avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
                
//                NSLog("Player Time: %f", CMTimeGetSeconds(time))
                self.musubiDelegate?.currentTime(time: CMTimeGetSeconds(time))
                
                if let subtitleData = self.subtitleWrapper?.getSubtitleSet() {
                    
                    if subtitleData.count > self.subtitleIndex {
                        let subData = subtitleData.object(at: self.subtitleIndex) as! ExternalSubtitle
                        
                        let subTimeSec = subData.subtitleStartTime / 1000
                        if ( ((Double(subTimeSec) - CMTimeGetSeconds(time) <= 1 && Double(subTimeSec) - CMTimeGetSeconds(time) >= 0)) ||
                            ((Double(subTimeSec) - CMTimeGetSeconds(time) <= 0 && Double(subTimeSec) - CMTimeGetSeconds(time) >= -1)) ) {
                            if let subDataText = subData.subtitleText {
//                                NSLog("text renderer: \(Double(subTimeSec)) , \(CMTimeGetSeconds(time))")
                                self.musubiDelegate?.onSubtitleData(startTime: subData.subtitleStartTime, endTime: subData.subtitleEndTime, text: subDataText)
                                self.subtitleIndex = self.subtitleIndex + 1
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func renderObject(drawable: CAMetalDrawable, pixelBuffer: CVPixelBuffer) {
        if let commandQueue = commandQueue_, let pipelineState = pipelineState_ {
            objectToDraw_?.render(commandQueue,
                                  renderPipelineState: pipelineState,
                                  drawable: drawable,
                                  pixelBuffer: pixelBuffer)
        }
    }
    
    // MARK: Initialize the Properties
    private func initProperties() {
        musubiDispatchQueue = DispatchQueue(label: "musubiStatus")
        
        lastFrameTimestamp_ = 0.0
    }
    
    func reSetVideoPlayerViewFrame(_ videoPlayerView: UIView) {
        if let metalLayer = metalLayer_ {

            let transformRect = CGRect(x: videoPlayerView.layer.frame.origin.y,
                                       y: videoPlayerView.layer.frame.origin.x,
                                       width: videoPlayerView.layer.frame.height,
                                       height: videoPlayerView.layer.frame.width)
            metalLayer.frame = transformRect
            videoPlayerView.layer.insertSublayer(metalLayer, at: 0)
        }
    }
    
    // MARK: Notification Center callback event
    @objc func playerDidFinishPlaying(note: NSNotification) {
        NSLog("Video Finished")
    }
    
    /*
     KVO
     */
    open override func observeValue(forKeyPath keyPath: String?,
                                     of object: Any?,
                                     change: [NSKeyValueChangeKey : Any]?,
                                     context: UnsafeMutableRawPointer?) {
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            
            return
        }
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status_: AVPlayerItem.Status?
            if let statusNumber = change?[.newKey] as? NSNumber {
                status_ = AVPlayerItem.Status(rawValue: statusNumber.intValue)
            } else {
                status_ = .unknown
            }
            
            if let status = status_ {
                switch status {
                case .readyToPlay:
                    // Player item is ready to play.
                    if let avPlayer = avPlayer_ {
                        self.totalPlayTime_ = avPlayer.currentItem?.asset.duration
                        if let totalPlayTime = self.totalPlayTime_ {
                            self.musubiDelegate?.totalTime(time: CMTimeGetSeconds(totalPlayTime))
                        }
                    }
                    break
                case .failed:
                    // Player ittem failed. See error.
                    break
                case .unknown:
                    // Player item is not yet ready
                    break
                }
            }
        }
    }
}

// MARK: Musubi Player Action API
extension MusubiPlayer: MusubiPlayerAction {
     public func open(_ mediaPath: String, mediaType: mediaType) {
        var mediaURL_: NSURL?
        if let player = avPlayer_, let videoOutput = videoOutput_ {
            NSLog("Media Content URI: %@", mediaPath)
            self.musubiPlayerState = .open
            
            switch mediaType {
            case .local:
                mediaURL_ = NSURL.fileURL(withPath: mediaPath) as NSURL
                break
            case .hls:
                mediaURL_ = NSURL(string: mediaPath)
                break
            case .dash:
                // TODO: playing dash content
                NSLog("[ERROR] Dash is not supported now")
                break
            default:
                
                break
            }
            
            player.currentItem?.remove(videoOutput)
            
            if let mediaURL = mediaURL_ {
                let item = AVPlayerItem.init(url: mediaURL as URL)
                let asset = item.asset
                
                asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
                    var error: NSError? = nil
                    let status = asset.statusOfValue(forKey: "tracks", error: &error)
                    switch status {
                    case .loaded:
                        DispatchQueue.main.async {
                            item.add(videoOutput)
                            player.replaceCurrentItem(with: item)
                            videoOutput.requestNotificationOfMediaDataChange(withAdvanceInterval: ONE_FRAME_DURATION)
//                            player.pause()
                            player.addObserver(self, forKeyPath: "status", options: .new, context: &playerItemContext)
                            NotificationCenter.default.addObserver(self, selector: #selector(self.playerDidFinishPlaying), name:.AVPlayerItemDidPlayToEndTime , object: player.currentItem)
                        }
                        break
                    default:
                        NSLog("Player Status is not loaded")
                        break
                    }
                }
            }
        }
    }
    
    public func start() {
           if let avPlayer = avPlayer_ {
               musubiPlayerState = .play
               avPlayer.play()
           }
       }
       
   public func pause() {
       if let avPlayer = avPlayer_ {
           musubiPlayerState = .pause
           avPlayer.pause()
       }
   }
   
   public func getPlayerState() -> playerState {
       return musubiPlayerState;
   }
   
   public func seek(_ time: Float) {
       if let avPlayer = avPlayer_ {
           let cmTime: CMTime = CMTimeMake(value: Int64(time), timescale: Int32(1.0))
        
            if let subtitleSet = subtitleWrapper?.getSubtitleSet() {
                var subPositionReloc: NSInteger = 0
                for subtitle in subtitleSet {
                    let subData = subtitle as! ExternalSubtitle
                    
                    let subTimeSec = subData.subtitleStartTime / 1000
                    if ( Double(subTimeSec) >= CMTimeGetSeconds(cmTime) ) {
                        subPositionReloc -= 1;
                        if subPositionReloc < 0 {
                            subPositionReloc = 0
                        }
                        break
                    }
                    if (subPositionReloc >= subtitleSet.count) {
                        subPositionReloc = 0;
                        break;
                    }
                    subPositionReloc += 1;
                }
                self.subtitleIndex = subPositionReloc
            }
        avPlayer.seek(to: cmTime)
       }
    }
    
   public func close() {
        if let avPlayer = avPlayer_, let videoOutput = videoOutput_{
            avPlayer.currentItem?.remove(videoOutput)
        }
        avPlayer_ = nil
    }
    
    public func setExternalSubtitle(_ subtitlePath: String, _ subtitleType: SubtitleType) {
        subtitleWrapper?.initMusubiSubtitle(subtitlePath, type: SubtitleType(rawValue: subtitleType.rawValue))
        
        // Check the Subtitle Data
//        if let subtitleSet = subtitleWrapper?.getSubtitleSet() {
//            for subtitle in subtitleSet {
//                let subData = subtitle as! ExternalSubtitle
//                NSLog("Time: \(subData.subtitleTime), Text: \(subData.subtitleText)")
//            }
//        }
    }
}
