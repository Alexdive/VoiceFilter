//
//  ViewController.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 23.11.2022.
//

import AVKit
import MobileCoreServices
import UIKit

final class MainViewController: AVPlayerViewController {
    
    enum UIConstants {
        static let layoutInset: CGFloat = 16
        static let verticalSpacing: CGFloat = 24
        static let horizontalSpacing: CGFloat = 32
        static let bottomStackInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        static let cornerRadius: CGFloat = 32
    }
    
    private var presenter: MainPresenterInput
    
    private lazy var recordVideoBtn: UIButton = {
        var button = makeButton(withImageName: "record.circle", tintColor: .systemRed)
        button.addAction {
            self.presentPicker(for: .camera)
        }
        return button
    }()
    
    private lazy var pickVideoBtn: UIButton = {
        var button = makeButton(withImageName: "folder", tintColor: .systemPurple)
        button.addAction {
            self.presentPicker(for: .photoLibrary)
        }
        return button
    }()
    
    private lazy var shareVideoBtn: UIButton = {
        var button = makeButton(withImageName: "square.and.arrow.up.circle", tintColor: .systemPurple)
        button.addAction {
            self.presenter.didTapShareVideo()
            self.activityIndicator.startAnimating()
        }
        return button
    }()
    
    private lazy var resetVideoBtn: UIButton = {
        var button = makeButton(withImageName: "arrow.uturn.backward.circle", tintColor: .systemRed)
        button.addAction {
            self.reset()
        }
        return button
    }()
    
    private lazy var loopBtn: UIButton = {
        var button = makeButton(withImageName: "infinity.circle", tintColor: .systemRed, selectedImage: "infinity.circle.fill")
        button.addAction {
            self.presenter.tappedLoopBtn()
            button.isSelected = self.presenter.isLooped
        }
        return button
    }()
    
    private lazy var filterBtnsStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = UIConstants.verticalSpacing
        return stackView
    }()
    
    private lazy var pickerBtnsStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = UIConstants.horizontalSpacing
        return stackView
    }()
    
    private lazy var bottomControlsStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = UIConstants.horizontalSpacing
        stackView.backgroundColor = .white.withAlphaComponent(0.5)
        stackView.layoutMargins = UIConstants.bottomStackInsets
        stackView.layer.cornerRadius = UIConstants.cornerRadius
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }()
    
    private var filterButtons: [VoiceFilter: UIButton] = [:]
    
    private lazy var picker: UIImagePickerController = {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.videoQuality = .typeHigh
        picker.videoExportPreset = AVAssetExportPresetHEVC1920x1080
        picker.mediaTypes = [UTType.movie.identifier]
        picker.allowsEditing = true
        return picker
    }()
    
    private lazy var activityIndicator = UIActivityIndicatorView(style: .large)
    
    init(presenter: MainViewPresenter) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
        setInitialState()
        presenter.delegate = self
        
        _ = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                   object: self.player?.currentItem,
                                                   queue: nil,
                                                   using: { _ in
            DispatchQueue.main.async {
                self.presenter.replay()
            }
        })
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        [filterBtnsStack, pickerBtnsStack, bottomControlsStack, activityIndicator]
            .forEach { view.bringSubviewToFront($0) }
    }
    
    private func setInitialState() {
        let hasVideo = presenter.currentVideo != nil
        filterBtnsStack.isUserInteractionEnabled = hasVideo
        bottomControlsStack.isHidden = !hasVideo
        loopBtn.isSelected = self.presenter.isLooped
    }
    
    private func shareWithActivityVC(url: URL) {
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = self.view
        self.present(share, animated: true) {
            self.activityIndicator.stopAnimating()
        }
    }
    
    private func presentPicker(for sourceType: UIImagePickerController.SourceType) {
        picker.sourceType = sourceType
        present(self.picker, animated: true, completion: nil)
    }
    
    private func reset() {
        self.presenter.restart()
        self.player = nil
        updateFilterBtns()
    }
}

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        dismiss(animated: true, completion: nil)
        guard let videoURL = info[.mediaURL] as? URL else { return }
        
        DispatchQueue.main.async {
            if picker.sourceType == .camera {
                self.presenter.didRecordVideo(videoURL)
            } else {
                self.presenter.didSelectVideo(videoURL)
            }
        }
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true) { [weak self] in
            self?.presenter.restart()
        }
    }
}

extension MainViewController: PresenterOutput {
    func pause() {
        player?.pause()
    }
    
    func resume() {
        player?.play()
    }
    
    func updateViews(hasSelectedVideo: Bool) {
        pickerBtnsStack.isHidden = hasSelectedVideo
        bottomControlsStack.isHidden = !hasSelectedVideo
        filterBtnsStack.isUserInteractionEnabled = hasSelectedVideo
        updateFilterBtns()
    }
    
    func playVideo(with url: URL) {
        player = AVPlayer(url: url)
        player?.isMuted = true
        player?.play()
    }
    
    func shareVideo(with url: URL) {
        activityIndicator.stopAnimating()
        shareWithActivityVC(url: url)
    }
}

// layout
extension MainViewController {
    private func setupViews() {
        showsPlaybackControls = false
        activityIndicator.color = .white
        
        [filterBtnsStack, pickerBtnsStack, bottomControlsStack, activityIndicator]
            .forEach {
                view.addSubview($0)
                $0.translatesAutoresizingMaskIntoConstraints = false
            }
        
        let filters = VoiceFilter.allCases
        filters.forEach { filter in
            let button = makeVoiceFilterButton(for: filter)
            filterButtons[filter] = button
            filterBtnsStack.addArrangedSubview(button)
        }
        
        pickerBtnsStack.addArrangedSubview(recordVideoBtn)
        pickerBtnsStack.addArrangedSubview(pickVideoBtn)
        
        bottomControlsStack.addArrangedSubview(resetVideoBtn)
        bottomControlsStack.addArrangedSubview(shareVideoBtn)
        bottomControlsStack.addArrangedSubview(loopBtn)
        
        NSLayoutConstraint.activate([
            filterBtnsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: UIConstants.layoutInset),
            filterBtnsStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            pickerBtnsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -UIConstants.layoutInset),
            pickerBtnsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            bottomControlsStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -UIConstants.layoutInset),
            bottomControlsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func makeVoiceFilterButton(for voiceFilter: VoiceFilter) -> UIButton {
        let button = UIButton()
        button.setImage(voiceFilter.image, for: .normal)
        button.setImage(voiceFilter.selectedImage, for: .selected)
        button.tintColor = .systemMint
        button.addAction { [weak self] in
            self?.didSelect(voiceFilter: voiceFilter)
        }
        return button
    }
    
    private func didSelect(voiceFilter: VoiceFilter) {
        presenter.selectedFilter = voiceFilter
        updateFilterBtns()
    }
    
    private func updateFilterBtns() {
        filterButtons.forEach { $1.isSelected = $0 == presenter.selectedFilter }
    }
    
    private func makeButton(withImageName image: String, tintColor: UIColor, selectedImage: String? = nil) -> UIButton {
        let button = UIButton()
        let mediumConfig = UIImage.SymbolConfiguration.medium
        let mediumImage = UIImage(systemName: image, withConfiguration: mediumConfig)
        button.setImage(mediumImage, for: .normal)
        if let selectedImage = selectedImage {
            let mediumSelectedImage = UIImage(systemName: selectedImage, withConfiguration: mediumConfig)
            button.setImage(mediumSelectedImage, for: .selected)
        }
        button.tintColor = tintColor
        return button
    }
}

extension VoiceFilter {
    var config: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration.medium
    }
    
    var image: UIImage? {
        switch self {
        case .highPitch:
            return UIImage(systemName: "arrow.up.circle", withConfiguration: config)
        case .lowPitch:
            return UIImage(systemName: "arrow.down.circle", withConfiguration: config)
        case .alien:
            return UIImage(systemName: "bubbles.and.sparkles", withConfiguration: config)
        case .reverb:
            return UIImage(systemName: "building.columns.circle", withConfiguration: config)
        case .none:
            return UIImage(systemName: "clear", withConfiguration: config)
        }
    }
    
    var selectedImage: UIImage? {
        switch self {
        case .highPitch:
            return UIImage(systemName: "arrow.up.circle.fill", withConfiguration: config)
        case .lowPitch:
            return UIImage(systemName: "arrow.down.circle.fill", withConfiguration: config)
        case .alien:
            return UIImage(systemName: "bubbles.and.sparkles.fill", withConfiguration: config)
        case .reverb:
            return UIImage(systemName: "building.columns.circle.fill", withConfiguration: config)
        case .none:
            return UIImage(systemName: "clear", withConfiguration: config)
        }
    }
}
