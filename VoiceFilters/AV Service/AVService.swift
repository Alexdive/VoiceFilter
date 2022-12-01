//
//  AVService.swift
//  VoiceFilters
//
//  Created by Aleksei Permiakov on 23.11.2022.
//

import AVFoundation

protocol AVServiceProtocol {
    var playVideo: ((URL) -> Void)? { get set }
    var engine: AVAudioEngine? { get }
    var audioPlayer: AVAudioPlayerNode? { get }
    
    func startPlayback(videoUrl: URL)
    func prepareVideoForShare(videoUrl: URL, completion: @escaping (URL) -> Void)
    func restart()
    func resetEffects()
    func applyLowPitchFilter(level: Float)
    func applyAlienFilter(level: Float)
    func applyHighPitchFilter(level: Float)
    func applyReverbFilter(level: Float)
}

final class AVService: AVServiceProtocol {
    
    var playVideo: ((URL) -> Void)?
    
    // Assets
    private var editedVideoURL: URL?
    private var audioFile: AVAudioFile?
    private var extractedAudioUrl: URL?
    
    // Effects
    private let reverb = AVAudioUnitReverb()
    private let pitchControl = AVAudioUnitTimePitch()
    private lazy var distortion = AVAudioUnitDistortion()
    
    private(set) var engine: AVAudioEngine?
    private(set) var audioPlayer: AVAudioPlayerNode?
    
    // Public methods
    func prepareVideoForShare(videoUrl: URL, completion: @escaping (URL) -> Void) {
        if let editedVideoURL {
            completion(editedVideoURL)
        } else {
            prepareEditedVideo(videoUrl: videoUrl) { [unowned self] outputURL in
                self.editedVideoURL = outputURL
                completion(outputURL)
            }
        }
    }
    
    func restart() {
        editedVideoURL = nil
        audioFile = nil
        extractedAudioUrl = nil
        engine?.stop()
        audioPlayer?.stop()
    }
    
    func resetEffects() {
        distortion.wetDryMix = 0
        reverb.wetDryMix = 0
        pitchControl.pitch = 0
    }
    
    func applyLowPitchFilter(level: Float = 50) {
        let maxMultiplier: Float = 100
        let changePerMultiplier = -2400 / maxMultiplier
        
        pitchControl.pitch = level * changePerMultiplier
    }
    
    func applyAlienFilter(level: Float = 10) {
        distortion.loadFactoryPreset(.speechCosmicInterference)
        distortion.wetDryMix = level
    }
    
    func applyHighPitchFilter(level: Float = 50) {
        let maxMultiplier: Float = 100
        let changePerMultiplier = 2400 / maxMultiplier
        
        pitchControl.pitch = level * changePerMultiplier
    }
    
    func applyReverbFilter(level: Float = 50) {
        reverb.wetDryMix = level
        reverb.loadFactoryPreset(.cathedral)
    }
    
    private func prepareEditedVideo(videoUrl: URL, completion: @escaping (URL) -> Void) {
        engine?.stop()
        audioPlayer?.stop()
        
        guard let renderedAudioURL = renderAudio() else { return }
        
        mergeVideoAndAudio(videoUrl: videoUrl, audioUrl: renderedAudioURL) { outputURL in
            completion(outputURL)
        }
    }
    
    func startPlayback(videoUrl: URL) {
        if engine?.isRunning == false || engine == nil {
            prepareEngine()
        }
        if let audioUrl = extractedAudioUrl {
            playSeparateStreams(audioUrl: audioUrl, videoUrl: videoUrl)
        } else {
            getAudioURL(from: videoUrl) { [unowned self] audioUrl in
                guard let audioUrl else { return }
                self.playSeparateStreams(audioUrl: audioUrl, videoUrl: videoUrl)
            }
        }
    }
    
    private func playSeparateStreams(audioUrl: URL, videoUrl: URL) {
        try? prepareAudioPlayer(url: audioUrl)
        
        audioPlayer?.play()
        playVideo?(videoUrl)
    }
    
    private func getAudioURL(from videoURL: URL, completion: @escaping (URL?) -> Void)  {
        let composition = AVMutableComposition()
        do {
            let asset = AVURLAsset(url: videoURL)
            guard let audioAssetTrack = asset.tracks(withMediaType: AVMediaType.audio).first,
                  let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                          preferredTrackID: kCMPersistentTrackID_Invalid) else {
                completion(nil)
                return
            }
            try audioCompositionTrack.insertTimeRange(audioAssetTrack.timeRange, of: audioAssetTrack, at: CMTime.zero)
        } catch {
            print(error.localizedDescription)
            return
        }
        
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "extracted_audio.m4a")
        removeFileIfExists(atUrl: outputURL)
        
        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetPassthrough) else { return }
        exporter.outputFileType = AVFileType.m4a
        exporter.outputURL = outputURL
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                completion(outputURL)
                self.extractedAudioUrl = outputURL
            }
        }
    }
    
    private func resetAudioEngine() {
        engine?.stop()
        engine?.reset()
        
        engine = AVAudioEngine()
        audioPlayer = AVAudioPlayerNode()
    }
    
    private func prepareEngine() {
        resetEffects()
        resetAudioEngine()
        setupEngineNodes()
        try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: .defaultToSpeaker)
        try? engine?.start()
    }
    
    private func prepareAudioPlayer(url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        self.audioFile = audioFile
        audioPlayer?.scheduleFile(audioFile, at: nil)
    }
    
    private func renderAudio() -> URL? {
        resetAudioEngine()
        
        guard let audioFile = audioFile,
              let engine = engine,
              let audioPlayer = audioPlayer else { return nil }
        
        setupEngineNodes()
        
        audioPlayer.scheduleFile(audioFile, at: nil)
        
        do {
            let bufferSize: AVAudioFrameCount = 4096
            try engine.enableManualRenderingMode(.offline, format: audioFile.processingFormat, maximumFrameCount: bufferSize)
            try engine.start()
        }
        catch {
            return nil
        }
        
        audioPlayer.play()
        
        var outputFile: AVAudioFile?
        do {
            guard let url = createDocumentUrlFor(path: "filtered_audio.m4a") else { return nil }
           removeFileIfExists(atUrl: url)
            
            let recordSettings = audioFile.fileFormat.settings
            
            outputFile = try AVAudioFile(forWriting: url, settings: recordSettings)
        } catch {
            return nil
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                                  frameCapacity: engine.manualRenderingMaximumFrameCount) else { return nil }
        
        while engine.manualRenderingSampleTime < audioFile.length {
            let remainingSamples = audioFile.length - engine.manualRenderingSampleTime
            let framesToRender = min(outputBuffer.frameCapacity, AVAudioFrameCount(remainingSamples))
            
            do {
                let renderingStatus = try engine.renderOffline(framesToRender, to: outputBuffer)
                switch renderingStatus {
                case .success:
                    try outputFile?.write(from: outputBuffer)
                default:
                    return nil
                }
            }
            catch {
                return nil
            }
        }
        
        defer {
            outputFile = nil
            audioPlayer.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }
        
        return outputFile?.url
    }
    
    func mergeVideoAndAudio(videoUrl: URL, audioUrl: URL, completion: @escaping (URL) -> Void) {
        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()
        
        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)
        
        guard let compositionAddVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.video,
                                                                       preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAddAudio = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                       preferredTrackID: kCMPersistentTrackID_Invalid),
              let compositionAddAudioOfVideo = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio,
                                                                              preferredTrackID: kCMPersistentTrackID_Invalid),
              let aVideoAssetTrack: AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video).first,
              let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio).first
        else { return }
        
        compositionAddVideo.preferredTransform = aVideoAssetTrack.preferredTransform
        
        mutableCompositionVideoTrack.append(compositionAddVideo)
        mutableCompositionAudioTrack.append(compositionAddAudio)
        mutableCompositionAudioOfVideoTrack.append(compositionAddAudioOfVideo)
        
        let duration = min(aVideoAssetTrack.timeRange.duration, aAudioAssetTrack.timeRange.duration)
        
        try? mutableCompositionVideoTrack
            .first?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration),
                                    of: aVideoAssetTrack,
                                    at: CMTime.zero)
        
        try? mutableCompositionAudioTrack
            .first?.insertTimeRange(CMTimeRangeMake(start: CMTime.zero, duration: duration),
                                    of: aAudioAssetTrack,
                                    at: CMTime.zero)
        
        guard let outputURL = createDocumentUrlFor(path: "merged_video.mov") else { return }
        removeFileIfExists(atUrl: outputURL)
        
        guard let exporter = AVAssetExportSession(asset: mixComposition,
                                                  presetName: AVAssetExportPresetHighestQuality)
        else { return }
        exporter.outputURL = outputURL
        exporter.outputFileType = AVFileType.mov
        exporter.shouldOptimizeForNetworkUse = true
        
        exporter.exportAsynchronously {
            guard case exporter.status = AVAssetExportSession.Status.completed else { return }
            DispatchQueue.main.async {
                completion(outputURL)
            }
        }
    }
    
    func createDocumentUrlFor(path: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory,
                                 in: .userDomainMask).first?.appendingPathComponent(path)
    }
    
    func removeFileIfExists(atUrl url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(atPath: url.path)
        }
    }
    
    private func setupEngineNodes() {
        guard let engine = engine,
              let audioPlayer = audioPlayer else { return }
        
        let nodes = [audioPlayer, pitchControl, distortion, reverb]
        nodes.forEach { engine.attach($0) }
        
        for i in 0..<nodes.count {
            let isLast = i == nodes.count - 1
            engine.connect(nodes[i],
                           to: isLast ? engine.mainMixerNode : nodes[i + 1],
                           format: nil)
        }
    }
}
