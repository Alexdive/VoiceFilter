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
    func updateViews(with state: PresentationState)
}

protocol MainPresenterInput {
    var filtersDict: [FilterName: VoiceFilter] { get }
    var delegate: PresenterOutput? { get set }
    var selectedFilter: FilterName? { get set }
    
    func viewDidLoad()
    func getFiltersNames() -> [FilterName]
    func tappedLoopBtn()
    func replay()
    func reset()
    func didRecordVideo(_ url: URL)
    func didSelectVideo(_ url: URL)
    func didTapShareVideo()
    func updateFilter(_ filter: VoiceFilter)
}

struct PresentationState {
    var filterBtnsStackIsUserInteractionEnabled = false
    var bottomControlsStackIsHidden = true
    var pickerBtnsStackIsHidden = false
    var loopBtnIsSelected = true
    
    mutating func update(hasVideo: Bool) {
        filterBtnsStackIsUserInteractionEnabled = hasVideo
        bottomControlsStackIsHidden = !hasVideo
        pickerBtnsStackIsHidden = hasVideo
    }
}

final class MainViewPresenter: MainPresenterInput {
    
    private let filters: [VoiceFilter] = [.highPitch, .lowPitch, .alien, .reverb, .none]
    
    private(set) lazy var filtersDict: [FilterName: VoiceFilter] = Dictionary(uniqueKeysWithValues: filters.map { ($0.name, $0) })
    
    weak var delegate: PresenterOutput?
    private var avService: AVServiceProtocol
    
    var replayFilter: FilterName?
    
    private var presentationState = PresentationState() {
        didSet {
            delegate?.updateViews(with: presentationState)
        }
    }
    
    private(set) var isLooped: Bool = true {
        didSet {
            let player = avService.audioPlayer
            if isLooped == true,
               player?.isPlaying == false {
                replay()
            }
            presentationState.loopBtnIsSelected = isLooped
        }
    }
    
    private(set) var currentVideo: URL? {
        didSet {
            presentationState.update(hasVideo: currentVideo != nil)
        }
    }
    
    init(avService: AVService) {
        self.avService = avService
        self.avService.playVideo = { [weak self] url in
            guard let self else { return }
            self.delegate?.playVideo(with: url)
            self.selectedFilter = FilterName.none
            if self.isLooped == true {
                self.selectedFilter = self.replayFilter
            }
        }
        
        setupNotificationObservers()
    }
    
    var selectedFilter: FilterName? {
        didSet {
            guard let filterName = selectedFilter,
                  let filter = filtersDict[filterName]
            else { return }
            avService.resetEffects()
            
            switch filter.name {
            case .highPitch:
                avService.applyHighPitchFilter(level: filter.level)
            case .lowPitch:
                avService.applyLowPitchFilter(level: filter.level)
            case .alien:
                avService.applyAlienFilter(level: filter.level)
            case .reverb:
                avService.applyReverbFilter(level: filter.level)
            case .none:
                selectedFilter = nil
                return
            default:
                return
            }
        }
    }
    
    func viewDidLoad() {
        delegate?.updateViews(with: presentationState)
    }
    
    func getFiltersNames() -> [FilterName] {
        filters.map(\.name)
    }
    
    func updateFilter(_ filter: VoiceFilter) {
        filtersDict[filter.name] = filter
        selectedFilter = filter.name
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
    
    func reset() {
        selectedFilter = FilterName.none
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
        guard let currentVideo else { return }
        delegate?.pause()
        avService.prepareVideoForShare(videoUrl: currentVideo) { [weak self] outputURL in
            self?.delegate?.shareVideo(with: outputURL)
        }
    }
    
    private func setupNotificationObservers() {
        _ = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
                                                   object: nil,
                                                   queue: .main) { [unowned self] _ in
            self.delegate?.pause()
            self.avService.engine?.pause()
            self.avService.audioPlayer?.pause()
        }
        _ = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                                   object: nil,
                                                   queue: .main) { [unowned self] _ in
            self.delegate?.resume()
            try? self.avService.engine?.start()
            self.avService.audioPlayer?.play()
        }
    }
}
