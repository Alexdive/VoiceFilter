//
//  MainViewPresenter.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 23.11.2022.
//

import UIKit

enum VoiceFilter: CaseIterable {
    case highPitch, lowPitch, alien, reverb, none
}

protocol PresenterOutput: AnyObject {
    func playVideo(with url: URL)
    func pause()
    func resume()
    func shareVideo(with url: URL)
    func updateViews(hasSelectedVideo: Bool)
}

protocol MainPresenterInput {
    var delegate: PresenterOutput? { get set }
    var currentVideo: URL? { get }
    var selectedFilter: VoiceFilter? { get set }
    var isLooped: Bool { get }
    
    func tappedLoopBtn()
    func replay()
    func restart()
    func didRecordVideo(_ url: URL)
    func didSelectVideo(_ url: URL)
    func didTapShareVideo()
}

final class MainViewPresenter: MainPresenterInput {
    
    weak var delegate: PresenterOutput?
    private var avService: AVServiceProtocol
    
    init(avService: AVService) {
        self.avService = avService
        self.avService.playVideo = { [weak self] url in
            self?.delegate?.playVideo(with: url)
            self?.selectedFilter = VoiceFilter.none
            self?.delegate?.updateViews(hasSelectedVideo: true)
        }
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToBackground),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appMovedToForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private(set) var currentVideo: URL? {
        didSet {
            delegate?.updateViews(hasSelectedVideo: currentVideo != nil)
        }
    }
    
    var selectedFilter: VoiceFilter? {
        didSet {
            guard let filter = selectedFilter,
                  filter != oldValue else { return }
            avService.resetEffects()
            switch filter {
            case .lowPitch:
                avService.applyLowPitchFilter()
            case .alien:
                avService.applyAlienFilter()
            case .highPitch:
                avService.applyHighPitchFilter()
            case .reverb:
                avService.applyReverbFilter()
            case .none:
                selectedFilter = nil
                return
            }
        }
    }
    
    private(set) var isLooped: Bool = true {
        didSet {
            let player = avService.audioPlayer
            if isLooped == true,
               player?.isPlaying == false {
                replay()
            }
        }
    }
    
    func tappedLoopBtn() {
        isLooped.toggle()
    }
    
    func replay() {
        avService.audioPlayer?.stop()
        if let url = currentVideo, isLooped {
            avService.startPlayback(videoUrl: url)
        }
    }
    
    func restart() {
        selectedFilter = nil
        currentVideo = nil
        avService.restart()
    }
    
    func didRecordVideo(_ url: URL) {
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, self, nil, nil)
        didSelectVideo(url)
    }
    
    func didSelectVideo(_ url: URL) {
        avService.startPlayback(videoUrl: url)
        currentVideo = url
    }
    
    func didTapShareVideo() {
        guard let currentVideo = currentVideo else { return }
        delegate?.pause()
        avService.prepareVideoForShare(videoUrl: currentVideo) { [weak self] outputURL in
            self?.delegate?.shareVideo(with: outputURL)
        }
    }
    
    @objc private func appMovedToBackground() {
        delegate?.pause()
        avService.engine?.pause()
        avService.audioPlayer?.pause()
    }
    
    @objc private func appMovedToForeground() {
        delegate?.resume()
        try? avService.engine?.start()
        avService.audioPlayer?.play()
    }
}
