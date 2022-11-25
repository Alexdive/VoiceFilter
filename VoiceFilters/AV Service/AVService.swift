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
    func applyLowPitchFilter()
    func applyAlienFilter()
    func applyHighPitchFilter()
    func applyReverbFilter()
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
        guard let editedVideoURL = editedVideoURL else {
            prepareEditedVideo(videoUrl: videoUrl) { [weak self] outputURL in
                guard let self = self else { return }
                self.editedVideoURL = outputURL
                completion(outputURL)
            }
            return
        }
        completion(editedVideoURL)
    }
    
    func restart() {
        editedVideoURL = nil
        resetEffects()
        engine?.stop()
        audioPlayer?.stop()
    }
    
    func resetEffects() {
        distortion.wetDryMix = 0
        reverb.wetDryMix = 0
        pitchControl.pitch = 0
    }
    
    func applyLowPitchFilter() {
        pitchControl.pitch = -1000
    }
    
    func applyAlienFilter() {
        distortion.wetDryMix = 10
        distortion.loadFactoryPreset(.speechAlienChatter)
    }
    
    func applyHighPitchFilter() {
        pitchControl.pitch = 1000
    }
    
    func applyReverbFilter() {
        reverb.wetDryMix = 50
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
        if let audioUrl = extractedAudioUrl {
            playSeparateStreams(audioUrl: audioUrl, videoUrl: videoUrl)
        }
        getAudioURL(from: videoUrl) { [weak self] audioUrl in
            guard let self = self,
                  let audioUrl = audioUrl else { return }
            
            self.playSeparateStreams(audioUrl: audioUrl, videoUrl: videoUrl)
        }
    }
    
    private func playSeparateStreams(audioUrl: URL, videoUrl: URL) {
        try? self.prepareEngine(url: audioUrl)
        try? self.engine?.start()
        
        self.audioPlayer?.play()
        self.playVideo?(videoUrl)
    }
    
    private func getAudioURL(from videoURL: URL, completion: @escaping (URL?) -> Void)  {
        let composition = AVMutableComposition()
        do {
            let asset = AVURLAsset(url: videoURL)
            guard let audioAssetTrack = asset.tracks(withMediaType: AVMediaType.audio).first else {
                completion(nil)
                return
            }
            guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio,
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
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
        }
        
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
        
        let engine = AVAudioEngine()
        let audioPlayer = AVAudioPlayerNode()
        self.engine = engine
        self.audioPlayer = audioPlayer
    }
    
    private func prepareEngine(url: URL) throws {
        resetEffects()
        resetAudioEngine()
        setupEngineNodes()
        
        let audioFile = try AVAudioFile(forReading: url)
        try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: .defaultToSpeaker)
        
        self.audioFile = audioFile
        audioPlayer?.scheduleFile(audioFile, at: nil)
    }
    
    private func renderAudio() -> URL? {
        guard let audioFile = audioFile else { return nil }
        
        resetAudioEngine()
        guard let engine = engine,
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
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("filtered_audio.m4a")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            
            let recordSettings = audioFile.fileFormat.settings
            
            outputFile = try AVAudioFile(forWriting: url, settings: recordSettings)
        } catch {
            return nil
        }
        
        
        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )!
        
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
        
        let newURL = outputFile?.url
        outputFile = nil
        
        audioPlayer.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        
        return newURL
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
        
        guard let documentDirectory = FileManager.default.urls(for: .documentDirectory,
                                                               in: .userDomainMask).first else { return }
        
        let outputURL = documentDirectory.appendingPathComponent("merged_video.mov")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
        }
        
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
    
    private func setupEngineNodes() {
        guard let engine = engine,
              let audioPlayer = audioPlayer else { return }
        
        let nodes = [audioPlayer, pitchControl, distortion, reverb]
        nodes.forEach { engine.attach($0) }
        
        for i in 0..<nodes.count {
            guard i < nodes.count - 1 else {
                engine.connect(nodes[i], to: engine.mainMixerNode, format: nil)
                continue
            }
            engine.connect(nodes[i], to: nodes[i + 1], format: nil)
        }
    }
}
