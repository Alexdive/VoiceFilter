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
        static let filtersStackInsets = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        static let cornerRadius: CGFloat = 32
    }
    
    private var presenter: MainPresenterInput
    
    private lazy var recordVideoBtn: UIButton = {
        var button = makeButton(withImageName: "record.circle", tintColor: .systemRed)
        button.addAction { [unowned self] in
            self.presentPicker(for: .camera)
        }
        return button
    }()
    
    private lazy var pickVideoBtn: UIButton = {
        var button = makeButton(withImageName: "folder", tintColor: .systemPurple)
        button.addAction { [unowned self] in
            self.presentPicker(for: .photoLibrary)
        }
        return button
    }()
    
    private lazy var shareVideoBtn: UIButton = {
        var button = makeButton(withImageName: "square.and.arrow.up.circle", tintColor: .systemPurple)
        button.addAction { [unowned self] in
            self.presenter.didTapShareVideo()
            self.activityIndicator.startAnimating()
        }
        return button
    }()
    
    private lazy var resetVideoBtn: UIButton = {
        var button = makeButton(withImageName: "arrow.uturn.backward.circle", tintColor: .systemRed)
        button.addAction { [unowned self] in
            self.reset()
        }
        return button
    }()
    
    private lazy var loopBtn: UIButton = {
        var button = makeButton(withImageName: "infinity.circle", tintColor: .systemPurple, selectedImage: "infinity.circle.fill")
        button.addAction { [unowned self] in
            self.presenter.tappedLoopBtn()
        }
        return button
    }()
    
    private lazy var filterBtnsStack: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = UIConstants.verticalSpacing
        stackView.backgroundColor = .white.withAlphaComponent(0.5)
        stackView.layoutMargins = UIConstants.filtersStackInsets
        stackView.layer.cornerRadius = UIConstants.cornerRadius
        stackView.isLayoutMarginsRelativeArrangement = true
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
    
    private var filterButtons: [FilterName: UIButton] = [:]
    
    private lazy var picker: UIImagePickerController = {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.videoQuality = .typeHigh
        picker.videoExportPreset = AVAssetExportPresetHEVC1920x1080
        picker.mediaTypes = [UTType.movie.identifier]
        picker.allowsEditing = true
        return picker
    }()
    
    private lazy var sliderContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .white.withAlphaComponent(0.5)
        view.layer.cornerRadius = 20
        return view
    }()
    
    private var slider: UISlider?
    
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
        setupGestureRecognizers()
        setupNotifications()
        presenter.delegate = self
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        [filterBtnsStack, pickerBtnsStack, bottomControlsStack, activityIndicator]
            .forEach { view.bringSubviewToFront($0) }
        presenter.viewDidLoad()
    }
    
    private func presentPicker(for sourceType: UIImagePickerController.SourceType) {
        picker.sourceType = sourceType
        present(self.picker, animated: true, completion: nil)
    }
    
    private func reset() {
        presenter.reset()
        player = nil
        removeSliderContainerIfNeeded()
    }
    
    private func shareWithActivityVC(url: URL) {
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = self.view
        self.present(share, animated: true) {
            self.activityIndicator.stopAnimating()
        }
    }
    
    private func updateState(with state: PresentationState) {
        filterBtnsStack.isUserInteractionEnabled = state.filterBtnsStackIsUserInteractionEnabled
        bottomControlsStack.isHidden = state.bottomControlsStackIsHidden
        pickerBtnsStack.isHidden = state.pickerBtnsStackIsHidden
        loopBtn.isSelected = state.loopBtnIsSelected
    }
    
    private func setupGestureRecognizers() {
        let tap = UITapGestureRecognizer()
        tap.addAction { [unowned self] in
            self.removeSliderContainerIfNeeded()
        }
        view.addGestureRecognizer(tap)
        
        filterButtons
            .filter { $0.key != .none }
            .forEach { filterName, button in
                let longTap = UILongPressGestureRecognizer()
                button.addGestureRecognizer(longTap)
                longTap.addAction { [unowned self] in
                    if longTap.state == .began {
                        self.showSlider(filterName: filterName)
                        self.didSelect(filterName: filterName)
                    }
                }
            }
    }
    
    private func setupNotifications() {
        _ = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                   object: self.player?.currentItem,
                                                   queue: nil) { _ in
            DispatchQueue.main.async {
                self.presenter.replay()
            }
        }
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
            self?.presenter.reset()
        }
    }
}

extension MainViewController: PresenterOutput {
    func updateViews(with state: PresentationState) {
        updateState(with: state)
        updateFilterBtns()
    }
    
    func pause() {
        player?.pause()
    }
    
    func resume() {
        player?.play()
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
        view.backgroundColor = .darkGray
        
        [filterBtnsStack, pickerBtnsStack, bottomControlsStack, activityIndicator]
            .forEach {
                view.addSubview($0)
                $0.translatesAutoresizingMaskIntoConstraints = false
            }
        
        let filters = presenter.getFiltersNames()
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
    
    private func removeSliderContainerIfNeeded() {
        if sliderContainer.isDescendant(of: view) {
            sliderContainer.subviews.forEach { $0.removeFromSuperview() }
            slider = nil
            sliderContainer.removeFromSuperview()
            sliderContainer.removeAllConstraints()
        }
    }
    
    private func layoutSliderContainer(with button: UIButton) {
        view.addSubview(sliderContainer)
        sliderContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sliderContainer.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 20),
            sliderContainer.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            sliderContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            sliderContainer.heightAnchor.constraint(equalTo: button.heightAnchor, multiplier: 0.8)
        ])
        view.layoutIfNeeded()
    }
    
    private func showSlider(filterName: FilterName) {
        guard let button = filterButtons[filterName],
              var filter = presenter.filtersDict[filterName] else { return }
        
        removeSliderContainerIfNeeded()
        layoutSliderContainer(with: button)
        
        slider = makeSlider()
        guard let slider else { return }
        slider.value = filter.level
        
        slider.addAction(for: .valueChanged) { [unowned self] in
            filter.level = slider.value
            presenter.updateFilter(filter)
        }
        
        sliderContainer.addSubview(slider)
        slider.frame = .init(origin: .init(x: sliderContainer.bounds.minX + 10,
                                           y: sliderContainer.bounds.minY),
                             size: .init(width: sliderContainer.bounds.width - 20,
                                         height: sliderContainer.bounds.height))
    }
    
    private func didSelect(filterName: FilterName) {
        presenter.selectedFilter = filterName
        updateFilterBtns()
        if sliderContainer.isDescendant(of: view) {
            if filterName != .none {
                showSlider(filterName: filterName)
            } else {
                removeSliderContainerIfNeeded()
            }
        }
    }
    
    private func updateFilterBtns() {
        filterButtons.forEach { $1.isSelected = $0 == presenter.selectedFilter }
    }
    
    private func makeVoiceFilterButton(for filterName: FilterName) -> UIButton {
        let button = UIButton()
        let voiceFilter = presenter.filtersDict[filterName] ?? .none
        button.setImage(voiceFilter.image, for: .normal)
        button.setImage(voiceFilter.selectedImage, for: .selected)
        button.tintColor = .systemMint
        button.addAction { [unowned self] in
            self.didSelect(filterName: filterName)
        }
        return button
    }
    
    private func makeButton(withImageName image: String, tintColor: UIColor, selectedImage: String? = nil) -> UIButton {
        let button = UIButton()
        let mediumConfig = UIImage.SymbolConfiguration.medium
        let mediumImage = UIImage(systemName: image, withConfiguration: mediumConfig)
        button.setImage(mediumImage, for: .normal)
        if let selectedImage {
            let mediumSelectedImage = UIImage(systemName: selectedImage, withConfiguration: mediumConfig)
            button.setImage(mediumSelectedImage, for: .selected)
        }
        button.tintColor = tintColor
        return button
    }
    
    private func makeSlider() -> UISlider {
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.isContinuous = true
        slider.tintColor = .systemMint
        slider.thumbTintColor = .systemPurple
        return slider
    }
}
