//
//  ViewController.swift
//  MusubiPlayerDemo
//
//  Created by HanGyo Jeong on 2020/10/09.
//  Copyright © 2020 HanGyoJeong. All rights reserved.
//

import UIKit
import MusubiPlayer

class PlayListViewController: UIViewController {
    
    @IBOutlet weak var playlistTableView: UITableView!
    
    var mediaArray = [mediaPlayList]()
    var mediaURL: String?
    
    var musubiOfflineStore: MusubiOfflineStore?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        playlistTableView.rowHeight = 80
        
        playlistTableView.delegate = self
        playlistTableView.dataSource = self
        
        // Parsing Media PlayList(format: JSON)
        let mediaJsonFilePath = Bundle.main.path(forResource: "hlsMediaList", ofType: "json")
        if let data = try? String(contentsOfFile: mediaJsonFilePath!).data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as! [String: Any] {
                if let mediaInfoDic = json["hlsSamples"] as? [[String: String]] {
                    for mediaInfo in mediaInfoDic {
                        let name = mediaInfo["name"]!
                        let uri = mediaInfo["uri"]!
                        let mediaList: mediaPlayList = mediaPlayList(title: name, url: uri)
                        
                        mediaArray.append(mediaList)
                    }
                }
            }
        }
        musubiOfflineStore = MusubiOfflineStore()
    }
}

extension PlayListViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return mediaArray.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = playlistTableView.dequeueReusableCell(withIdentifier: "mediaPlayListCell", for: indexPath) as! mediaPlaylistCell
        
        let row = indexPath.row
        cell.mediaPlaylistTitle.text = mediaArray[row].title
        cell.mediaPlaylistURL.text = mediaArray[row].url
        
        return cell
    }
    
    // MARK: Cell Click Event
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let storyBoard = UIStoryboard.init(name: "Main", bundle: nil)
        let row = indexPath.row
        mediaURL = mediaArray[row].url
        
        if VideoSettings.playMode == .viewController {
            let popupMusubiAction = storyBoard.instantiateViewController(identifier: "PlayStorePopupViewController") as PlayStorePopupViewController
            popupMusubiAction.modalPresentationStyle = .overCurrentContext
            popupMusubiAction.actionDelegate = self
            present(popupMusubiAction, animated: true, completion: nil)
            
            NSLog("Action: \(popupMusubiAction.action)")
        }
        else if VideoSettings.playMode == .rawPlayer {
            NSLog("Video should be played by raw MusubiPlayer")
            let rawVideoViewController = storyBoard.instantiateViewController(identifier: "RawPlayerViewController") as RawPlayerViewController
            rawVideoViewController.videoURL = mediaURL
            rawVideoViewController.modalPresentationStyle = .overCurrentContext
            present(rawVideoViewController, animated: true, completion: nil)
        }
        
        playlistTableView.deselectRow(at: indexPath, animated: true)
    }
    
    // MARK: Swipe To Delete Data
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let row = indexPath.row
            
            musubiOfflineStore?.remove(mediaArray[row].url)
            mediaArray.remove(at: row)
        }
    }
}

extension PlayListViewController: actionPopupDelegate {
    func didAction(action: musubiAction) {
        if action == .play {
            if let mediaPath = mediaURL {
                let musubiPlayerController:MusubiPlayerViewController = MusubiPlayerViewController()
                musubiPlayerController.mediaURL = mediaPath
                musubiPlayerController.externalSubURI = "/Function_b.smi"
                musubiPlayerController.externalSubLabelColor = UIColor.red
                
                self.present(musubiPlayerController, animated: true, completion: nil)
            }
        }
        else if action == .store {
            if let mediaPath = mediaURL {
                musubiOfflineStore?.startStore(mediaPath)
            }
        }
    }
}
