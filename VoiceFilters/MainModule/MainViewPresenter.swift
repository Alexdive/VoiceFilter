//
//  MainViewPresenter.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 23.11.2022.
//

import UIKit

protocol PresenterOutput: AnyObject {
    func playVideo(with url: URL)
    func pause()
    func resume()
    func shareVideo(with url: URL)
    func updateViews(hasSelectedVideo: Bool)
}

protocol MainPresenterInput {
    var filt: [FilterName: VoiceFilter] { get }
    var filters: [VoiceFilter] { get }
    var delegate: PresenterOutput? { get set }
    var currentVideo: URL? { get }
    var selectedFilter: FilterName? { get set }
    var isLooped: Bool { get }
    
    func tappedLoopBtn()
    func replay()
    func restart()
    func didRecordVideo(_ url: URL)
    func didSelectVideo(_ url: URL)
    func didTapShareVideo()
    func updateFilter(_ filter: VoiceFilter)
}

final class MainViewPresenter: MainPresenterInput {
    
    private(set) var filters: [VoiceFilter] = [.highPitch, .lowPitch, .alien, .reverb, .none]
    
    private(set) lazy var filt: [FilterName: VoiceFilter] = Dictionary(uniqueKeysWithValues: filters.map { ($0.name, $0) })
    
    weak var delegate: PresenterOutput?
    private var avService: AVServiceProtocol
    
    init(avService: AVService) {
        self.avService = avService
        self.avService.playVideo = { [weak self] url in
            guard let self else { return }
            self.delegate?.playVideo(with: url)
            self.selectedFilter = FilterName.none
            if self.isLooped == true {
                self.selectedFilter = self.replayFilter
            }
            self.delegate?.updateViews(hasSelectedVideo: true)
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
    
    var selectedFilter: FilterName? {
        didSet {
            guard let filterName = selectedFilter,
                  let filter = filt[filterName]
            else { return }
            avService.resetEffects()
            
            switch filter.name {
            case .highPitch:
                avService.applyHighPitchFilter(multiplier: filter.currentLevel)
            case .lowPitch:
                avService.applyLowPitchFilter(multiplier: filter.currentLevel)
            case .alien:
                avService.applyAlienFilter(multiplier: filter.currentLevel)
            case .reverb:
                avService.applyReverbFilter(multiplier: filter.currentLevel)
            case .none:
                selectedFilter = nil
                return
            default:
                return
            }
        }
    }
    
    func updateFilter(_ filter: VoiceFilter) {
        filt[filter.name] = filter
        selectedFilter = filter.name
    }
    
    var replayFilter: FilterName?
    
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
        replayFilter = selectedFilter
        avService.audioPlayer?.stop()
        if let url = currentVideo, isLooped {
            avService.startPlayback(videoUrl: url)
        }
    }
    
    func restart() {
        selectedFilter = FilterName.none
        currentVideo = nil
        avService.restart()
        delegate?.updateViews(hasSelectedVideo: false)
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
