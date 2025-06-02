//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import AVKit
import Combine
import Factory
import JellyfinAPI
import Logging
import SwiftUI

// This class provides a VLCVideoPlayer-compatible interface
// while using AVPlayer with spatial audio support underneath
public class SpatialVideoPlayer {

    // MARK: - State matching VLCVideoPlayer

    public enum State: Equatable {
        case opening
        case playing
        case paused
        case stopped
        case ended
        case error(Error)

        public static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.opening, .opening),
                 (.playing, .playing),
                 (.paused, .paused),
                 (.stopped, .stopped),
                 (.ended, .ended):
                return true
            case let (.error(lhsError), .error(rhsError)):
                return (lhsError as NSError).code == (rhsError as NSError).code &&
                    (lhsError as NSError).domain == (rhsError as NSError).domain
            default:
                return false
            }
        }
    }

    // MARK: - Proxy matching VLCVideoPlayer.Proxy

    public class Proxy: ObservableObject {

        weak var player: SpatialVideoPlayer?

        public func play() {
            player?.play()
        }

        public func pause() {
            player?.pause()
        }

        public func stop() {
            player?.stop()
        }

        public func seek(to seconds: Int) {
            player?.seek(to: seconds)
        }

        public func seek(by seconds: Int) {
            player?.seek(by: seconds)
        }

        public func setRate(_ rate: Float) {
            player?.setRate(rate)
        }

        public func setAudioTrack(index: Int) {
            player?.setAudioTrack(index: index)
        }

        public func setSubtitleTrack(index: Int) {
            player?.setSubtitleTrack(index: index)
        }

        public func setAudioDelay(_ delay: TimeInterval) {
            player?.setAudioDelay(delay)
        }

        public func setSubtitleDelay(_ delay: TimeInterval) {
            player?.setSubtitleDelay(delay)
        }

        public func setVideoAspectRatio(_ aspectRatio: String?) {
            player?.setVideoAspectRatio(aspectRatio)
        }

        // VLC-compatible methods that need different parameter types
        public func setAudioDelay(_ delay: VLCTime) {
            let seconds = TimeInterval(delay.value) / 1000.0
            player?.setAudioDelay(seconds)
        }

        public func setSubtitleDelay(_ delay: VLCTime) {
            let seconds = TimeInterval(delay.value) / 1000.0
            player?.setSubtitleDelay(seconds)
        }

        public func setTime(_ time: VLCTime) {
            let seconds = Int(time.value / 1000)
            player?.seek(to: seconds)
        }

        public func setRate(_ rate: VLCPlaybackRate) {
            player?.setRate(rate.value)
        }

        public func jumpBackward(_ seconds: Int) {
            player?.seek(by: -seconds)
        }

        public func jumpForward(_ seconds: Int) {
            player?.seek(by: seconds)
        }

        public func aspectFill(_ value: Float) {
            // Convert float value to aspect ratio string
            // value > 0 means fill mode, value <= 0 means fit mode
            let aspectRatio = value > 0 ? "fill" : "fit"
            player?.setVideoAspectRatio(aspectRatio)
        }

        public func setSubtitleColor(_ color: VLCTextRendererColor) {
            // AVPlayer handles subtitle styling differently
            // AVPlayer handles subtitle styling differently - no action needed
        }

        public func setSubtitleFont(_ font: UIFont?) {
            // AVPlayer handles subtitle styling differently
            // AVPlayer handles subtitle styling differently - no action needed
        }

        public func setSubtitleSize(_ size: VLCTextRendererSize) {
            // AVPlayer handles subtitle styling differently
            // AVPlayer handles subtitle styling differently - no action needed
        }

        public func playNewMedia(_ configuration: Configuration) {
            player?.load(configuration: configuration)
        }
    }

    // MARK: - External Subtitle Support

    public struct ExternalSubtitle {
        public let url: URL
        public let languageCode: String?
        public let displayName: String
        public let isForced: Bool
        public let isDefault: Bool

        public init(url: URL, languageCode: String?, displayName: String, isForced: Bool = false, isDefault: Bool = false) {
            self.url = url
            self.languageCode = languageCode
            self.displayName = displayName
            self.isForced = isForced
            self.isDefault = isDefault
        }
    }

    // MARK: - Configuration matching VLCVideoPlayer

    public struct Configuration {
        public let url: URL
        public var autoPlay: Bool = true
        public var playImmediately: Bool = true
        public var audioTrackIndex: Int = -1
        public var subtitleTrackIndex: Int = -1
        public var startTime: Int = 0 // in seconds
        public var externalSubtitles: [ExternalSubtitle] = []

        public init(url: URL) {
            self.url = url
        }

        public func validate() throws {
            guard url.scheme != nil else {
                throw ValidationError.invalidURL("URL must have a valid scheme")
            }

            // Validate URL is accessible (for local files)
            if url.isFileURL {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ValidationError.invalidURL("File does not exist at path: \(url.path)")
                }
            }

            guard startTime >= 0 else {
                throw ValidationError.invalidStartTime("Start time cannot be negative")
            }

            guard audioTrackIndex >= -1 else {
                throw ValidationError.invalidTrackIndex("Audio track index must be -1 or greater")
            }

            guard subtitleTrackIndex >= -1 else {
                throw ValidationError.invalidTrackIndex("Subtitle track index must be -1 or greater")
            }

            // Validate external subtitle URLs
            for (index, subtitle) in externalSubtitles.enumerated() {
                if subtitle.url.isFileURL {
                    guard FileManager.default.fileExists(atPath: subtitle.url.path) else {
                        throw ValidationError.invalidURL("External subtitle \(index) does not exist at path: \(subtitle.url.path)")
                    }
                }
            }
        }
    }

    // MARK: - Validation Errors

    public enum ValidationError: LocalizedError {
        case invalidURL(String)
        case invalidStartTime(String)
        case invalidTrackIndex(String)

        public var errorDescription: String? {
            switch self {
            case let .invalidURL(message),
                 let .invalidStartTime(message),
                 let .invalidTrackIndex(message):
                return message
            }
        }
    }

    // MARK: - PlaybackInformation matching VLCVideoPlayer

    public struct PlaybackInformation {
        public let currentAudioTrack: AudioTrack
        public let currentSubtitleTrack: SubtitleTrack
        public let audioTracks: [AudioTrack]
        public let subtitleTracks: [SubtitleTrack]

        public struct AudioTrack {
            public let index: Int
            public let name: String
            public let languageCode: String?
            public let isDefault: Bool
        }

        public struct SubtitleTrack {
            public let index: Int
            public let name: String
            public let languageCode: String?
            public let isDefault: Bool
            public let isForced: Bool
        }
    }

    // MARK: - Properties

    @Injected(\.logService)
    private var logger

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private let audioManager = AudioManager()
    private var configuration: Configuration?

    // Public accessor for the underlying AVPlayer (needed by SwiftUI Coordinator)
    public var avPlayer: AVPlayer? { player }

    @Published @MainActor
    public private(set) var state: State = .stopped
    @Published @MainActor
    public private(set) var currentTime: Int = 0 // in milliseconds
    @Published @MainActor
    public private(set) var duration: Int = 0 // in milliseconds
    @Published @MainActor
    public private(set) var playbackInformation: PlaybackInformation?

    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var itemEndObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // Audio/Subtitle track management
    private var currentAudioTrackIndex: Int = -1
    private var currentSubtitleTrackIndex: Int = -1
    private var subtitleDelay: TimeInterval = 0
    private var aspectRatio: String?

    // MARK: - Initialization

    public init() {
        setupNotifications()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    public func load(configuration: Configuration) {
        self.configuration = configuration
        cleanup()
        Task { @MainActor in
            state = .opening
        }

        // Validate configuration
        do {
            try configuration.validate()
        } catch {
            logger.error("Invalid configuration: \(error.localizedDescription)")
            Task { @MainActor in
                state = .error(error)
            }
            return
        }

        logger.debug("Loading media from URL: \(configuration.url)")

        // Create player item
        playerItem = AVPlayerItem(url: configuration.url)

        // Setup observers
        setupPlayerItemObservers()

        // Create player
        player = AVPlayer(playerItem: playerItem)
        Task { @MainActor in
            player?.automaticallyWaitsToMinimizeStalling = true
        }

        // Configure spatial audio
        audioManager.configureSpatialAudio()

        // Setup time observer
        setupTimeObserver()

        // Apply initial configuration
        if configuration.startTime > 0 {
            seek(to: configuration.startTime)
        }

        if configuration.audioTrackIndex >= 0 {
            setAudioTrack(index: configuration.audioTrackIndex)
        }

        if configuration.subtitleTrackIndex >= 0 {
            setSubtitleTrack(index: configuration.subtitleTrackIndex)
        }

        // Load external subtitles if available
        loadExternalSubtitles()

        // Auto play if configured
        if configuration.autoPlay {
            play()
        }
    }

    @available(iOS 15.0, tvOS 15.0, *)
    public func loadAsync(configuration: Configuration) async throws {
        self.configuration = configuration
        cleanup()
        await MainActor.run {
            state = .opening
        }

        // Validate configuration
        try configuration.validate()

        logger.debug("Loading media from URL: \(configuration.url)")

        // Create asset and load asynchronously
        let asset = AVURLAsset(url: configuration.url)
        let (isPlayable, tracks) = try await asset.load(.isPlayable, .tracks)

        guard isPlayable else {
            throw ValidationError.invalidURL("Media is not playable")
        }

        // Create player item
        playerItem = AVPlayerItem(asset: asset)

        // Setup observers
        setupPlayerItemObservers()

        // Create player
        player = AVPlayer(playerItem: playerItem)
        Task { @MainActor in
            player?.automaticallyWaitsToMinimizeStalling = true
        }

        // Configure spatial audio
        audioManager.configureSpatialAudio()

        // Setup time observer
        setupTimeObserver()

        // Apply initial configuration
        if configuration.startTime > 0 {
            await seek(to: configuration.startTime)
        }

        if configuration.audioTrackIndex >= 0 {
            setAudioTrack(index: configuration.audioTrackIndex)
        }

        if configuration.subtitleTrackIndex >= 0 {
            setSubtitleTrack(index: configuration.subtitleTrackIndex)
        }

        // Load external subtitles if available
        loadExternalSubtitles()

        // Auto play if configured
        if configuration.autoPlay {
            play()
        }

        logger.info("Media loaded successfully with \(tracks.count) tracks")
    }

    public func play() {
        guard let player = player else { return }

        if configuration?.playImmediately == true {
            player.playImmediately(atRate: 1.0)
        } else {
            player.play()
        }

        Task { @MainActor in
            state = .playing
        }
    }

    public func pause() {
        player?.pause()
        Task { @MainActor in
            state = .paused
        }
    }

    public func stop() {
        cleanup()
        Task { @MainActor in
            state = .stopped
        }
    }

    public func seek(to seconds: Int) {
        guard let player = player else { return }
        let time = CMTime(seconds: Double(seconds), preferredTimescale: 1000)
        player.seek(to: time) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    @available(iOS 15.0, tvOS 15.0, *)
    public func seek(to seconds: Int) async {
        guard let player = player else { return }
        let time = CMTime(seconds: Double(seconds), preferredTimescale: 1000)

        await player.seek(to: time)
        updateCurrentTime()
    }

    public func seek(by seconds: Int) {
        guard let currentTimeInSeconds = player?.currentTime().seconds else { return }
        let targetTime = Int(currentTimeInSeconds) + seconds
        seek(to: max(0, targetTime))
    }

    public func setRate(_ rate: Float) {
        player?.rate = rate
    }

    public func setAudioTrack(index: Int) {
        guard let playerItem = playerItem else { return }

        // Handle audio selection using AVMediaSelectionGroup
        if let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            if index == -1 {
                // Use default audio track
                playerItem.select(audioGroup.defaultOption, in: audioGroup)
                currentAudioTrackIndex = index
            } else {
                let options = audioGroup.options
                if index < options.count && index >= 0 {
                    playerItem.select(options[index], in: audioGroup)
                    currentAudioTrackIndex = index
                } else {
                    logger.warning("Audio track index \(index) out of bounds (0..\(options.count - 1))")
                    return
                }
            }
        }

        updatePlaybackInformation()
    }

    public func setSubtitleTrack(index: Int) {
        guard let playerItem = playerItem else { return }

        // Handle subtitle selection
        if let subtitleGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            if index == -1 {
                // Disable subtitles
                playerItem.select(nil, in: subtitleGroup)
                currentSubtitleTrackIndex = index
            } else {
                let options = subtitleGroup.options
                if index < options.count && index >= 0 {
                    playerItem.select(options[index], in: subtitleGroup)
                    currentSubtitleTrackIndex = index
                } else {
                    logger.warning("Subtitle track index \(index) out of bounds (0..\(options.count - 1))")
                    return
                }
            }
        }

        updatePlaybackInformation()
    }

    public func setAudioDelay(_ delay: TimeInterval) {
        // Apply audio delay using AVAudioMix
        guard let playerItem = playerItem else { return }

        let audioMix = AVMutableAudioMix()
        let audioMixInputParameters = AVMutableAudioMixInputParameters()

        if let audioTrack = playerItem.asset.tracks(withMediaType: .audio).first {
            audioMixInputParameters.trackID = audioTrack.trackID

            // Apply time offset for audio delay
            let timescale = CMTimeScale(1000)
            let delayTime = CMTime(seconds: delay, preferredTimescale: timescale)
            audioMixInputParameters.setVolumeRamp(
                fromStartVolume: 1.0,
                toEndVolume: 1.0,
                timeRange: CMTimeRange(start: delayTime, duration: CMTime.positiveInfinity)
            )

            audioMix.inputParameters = [audioMixInputParameters]
            playerItem.audioMix = audioMix

            logger.info("Applied audio delay of \(delay) seconds")
        }
    }

    public func setSubtitleDelay(_ delay: TimeInterval) {
        // Store subtitle delay for later application
        subtitleDelay = delay

        // Apply delay by adjusting subtitle track timing if possible
        guard let playerItem = playerItem,
              let subtitleGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              currentSubtitleTrackIndex >= 0 else { return }

        // Re-select current subtitle with delay applied
        let options = subtitleGroup.options
        if currentSubtitleTrackIndex < options.count {
            playerItem.select(options[currentSubtitleTrackIndex], in: subtitleGroup)
            logger.info("Applied subtitle delay of \(delay) seconds")
        }
    }

    public func setVideoAspectRatio(_ aspectRatio: String?) {
        // Store aspect ratio for the view layer to handle
        self.aspectRatio = aspectRatio

        // Notify observers about aspect ratio change
        NotificationCenter.default.post(
            name: .spatialVideoPlayerAspectRatioChanged,
            object: self,
            userInfo: ["aspectRatio": aspectRatio ?? ""]
        )
    }

    // MARK: - Private Methods

    private func loadExternalSubtitles() {
        guard let configuration = configuration,
              !configuration.externalSubtitles.isEmpty,
              let _ = playerItem else { return }

        logger.info("Loading \(configuration.externalSubtitles.count) external subtitle(s)")

        // AVPlayer doesn't directly support external subtitle files
        // This would require a custom subtitle renderer or converting to WebVTT
        // For now, log a warning about this limitation
        logger
            .warning("External subtitle loading is not yet implemented in SpatialVideoPlayer. Subtitles must be embedded in the media file."
            )

        // TODO: Implement external subtitle support using:
        // 1. Parse subtitle files (SRT, ASS, etc.)
        // 2. Convert to WebVTT format
        // 3. Create AVMediaSelectionOption programmatically
        // 4. Or overlay subtitles using CATextLayer
    }

    private func setupPlayerItemObservers() {
        guard let playerItem = playerItem else { return }

        // Observe player item status
        statusObserver = playerItem.observe(\.status) { [weak self] item, _ in
            switch item.status {
            case .readyToPlay:
                self?.handleReadyToPlay()
            case .failed:
                let error = item.error ?? NSError(domain: "SpatialVideoPlayer", code: -1)
                Task { @MainActor in
                    self?.state = .error(error)
                }
            case .unknown:
                break
            @unknown default:
                break
            }
        }

        // Observe when playback ends
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.state = .ended
            }
        }
    }

    private func setupTimeObserver() {
        guard let player = player else { return }

        // Update time every 250ms for better performance
        let interval = CMTime(seconds: 0.25, preferredTimescale: 1000)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            self?.updateCurrentTime()
        }
    }

    private func handleReadyToPlay() {
        guard let playerItem = playerItem else { return }

        // Update duration
        let durationTime = playerItem.duration
        if durationTime.isNumeric {
            Task { @MainActor in
                duration = Int(durationTime.seconds * 1000)
            }
        }

        // Update playback information
        updatePlaybackInformation()

        // Update state if we're supposed to be playing
        Task { @MainActor in
            if state == .opening && player?.rate ?? 0 > 0 {
                state = .playing
            }
        }
    }

    private func updateCurrentTime() {
        guard let player = player else { return }
        let time = player.currentTime()
        if time.isNumeric {
            Task { @MainActor in
                currentTime = Int(time.seconds * 1000)
            }
        }
    }

    private func updatePlaybackInformation() {
        guard let playerItem = playerItem else { return }

        var audioTracks: [PlaybackInformation.AudioTrack] = []
        var subtitleTracks: [PlaybackInformation.SubtitleTrack] = []

        // Get audio tracks
        if let audioGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) {
            for (index, option) in audioGroup.options.enumerated() {
                let track = PlaybackInformation.AudioTrack(
                    index: index,
                    name: option.displayName,
                    languageCode: option.locale?.languageCode,
                    isDefault: audioGroup.defaultOption == option
                )
                audioTracks.append(track)
            }
        }

        // Get subtitle tracks
        if let subtitleGroup = playerItem.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            // Add "None" option
            let noneTrack = PlaybackInformation.SubtitleTrack(
                index: -1,
                name: "None",
                languageCode: nil,
                isDefault: false,
                isForced: false
            )
            subtitleTracks.append(noneTrack)

            for (index, option) in subtitleGroup.options.enumerated() {
                let track = PlaybackInformation.SubtitleTrack(
                    index: index,
                    name: option.displayName,
                    languageCode: option.locale?.languageCode,
                    isDefault: subtitleGroup.defaultOption == option,
                    isForced: option.hasMediaCharacteristic(.containsOnlyForcedSubtitles)
                )
                subtitleTracks.append(track)
            }
        }

        // Create current track info
        let currentAudioTrack = audioTracks.first { $0.index == currentAudioTrackIndex } ?? PlaybackInformation.AudioTrack(
            index: -1,
            name: "Default",
            languageCode: nil,
            isDefault: true
        )
        let currentSubtitleTrack = subtitleTracks.first { $0.index == currentSubtitleTrackIndex } ?? PlaybackInformation.SubtitleTrack(
            index: -1,
            name: "None",
            languageCode: nil,
            isDefault: false,
            isForced: false
        )

        let info = PlaybackInformation(
            currentAudioTrack: currentAudioTrack,
            currentSubtitleTrack: currentSubtitleTrack,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks
        )

        Task { @MainActor in
            playbackInformation = info
        }
    }

    private func setupNotifications() {
        // Handle audio manager notifications
        NotificationCenter.default.publisher(for: .audioManagerPlayCommand)
            .sink { [weak self] _ in self?.play() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioManagerPauseCommand)
            .sink { [weak self] _ in self?.pause() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioManagerSkipForward)
            .sink { [weak self] notification in
                if let interval = notification.userInfo?["interval"] as? TimeInterval {
                    self?.seek(by: Int(interval))
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .audioManagerSkipBackward)
            .sink { [weak self] notification in
                if let interval = notification.userInfo?["interval"] as? TimeInterval {
                    self?.seek(by: -Int(interval))
                }
            }
            .store(in: &cancellables)
    }

    private func cleanup() {
        player?.pause()

        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
        }

        statusObserver?.invalidate()

        if let itemEndObserver = itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }

        player = nil
        playerItem = nil
        timeObserver = nil
        statusObserver = nil
        itemEndObserver = nil

        Task { @MainActor in
            currentTime = 0
            duration = 0
            playbackInformation = nil
        }
    }
}

// MARK: - SwiftUI View

public struct SpatialVideoPlayerView: UIViewControllerRepresentable {

    let configuration: SpatialVideoPlayer.Configuration
    let proxy: SpatialVideoPlayer.Proxy
    let onTicksUpdated: ((Int, SpatialVideoPlayer.PlaybackInformation) -> Void)?
    let onStateUpdated: ((SpatialVideoPlayer.State, SpatialVideoPlayer.PlaybackInformation?) -> Void)?

    public init(
        configuration: SpatialVideoPlayer.Configuration,
        proxy: SpatialVideoPlayer.Proxy,
        onTicksUpdated: ((Int, SpatialVideoPlayer.PlaybackInformation) -> Void)? = nil,
        onStateUpdated: ((SpatialVideoPlayer.State, SpatialVideoPlayer.PlaybackInformation?) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.proxy = proxy
        self.onTicksUpdated = onTicksUpdated
        self.onStateUpdated = onStateUpdated
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()

        let player = SpatialVideoPlayer()
        proxy.player = player
        context.coordinator.player = player

        // Setup player view
        let playerViewController = AVPlayerViewController()
        playerViewController.showsPlaybackControls = false
        playerViewController.view.backgroundColor = .black

        viewController.addChild(playerViewController)
        viewController.view.addSubview(playerViewController.view)
        playerViewController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            playerViewController.view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            playerViewController.view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            playerViewController.view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            playerViewController.view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
        ])
        playerViewController.didMove(toParent: viewController)

        context.coordinator.playerViewController = playerViewController

        // Load configuration
        player.load(configuration: configuration)

        // Setup observers
        context.coordinator.setupObservers()

        return viewController
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Updates handled through proxy
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            onTicksUpdated: onTicksUpdated,
            onStateUpdated: onStateUpdated
        )
    }

    public class Coordinator: NSObject {
        var player: SpatialVideoPlayer?
        var playerViewController: AVPlayerViewController?
        let onTicksUpdated: ((Int, SpatialVideoPlayer.PlaybackInformation) -> Void)?
        let onStateUpdated: ((SpatialVideoPlayer.State, SpatialVideoPlayer.PlaybackInformation?) -> Void)?
        private var cancellables = Set<AnyCancellable>()
        private var aspectRatioObserver: NSObjectProtocol?

        init(
            onTicksUpdated: ((Int, SpatialVideoPlayer.PlaybackInformation) -> Void)?,
            onStateUpdated: ((SpatialVideoPlayer.State, SpatialVideoPlayer.PlaybackInformation?) -> Void)?
        ) {
            self.onTicksUpdated = onTicksUpdated
            self.onStateUpdated = onStateUpdated
        }

        func setupObservers() {
            guard let player = player else { return }

            // Observe time updates
            player.$currentTime
                .sink { [weak self, weak player] ticks in
                    guard let player = player else { return }
                    Task { @MainActor in
                        if let playbackInfo = player.playbackInformation {
                            self?.onTicksUpdated?(ticks, playbackInfo)
                        }
                    }
                }
                .store(in: &cancellables)

            // Observe state updates
            player.$state
                .sink { [weak self, weak player] state in
                    guard let player = player else { return }
                    Task { @MainActor in
                        self?.onStateUpdated?(state, player.playbackInformation)
                    }
                }
                .store(in: &cancellables)

            // Update AVPlayerViewController when player changes
            player.$state
                .sink { [weak self] _ in
                    if let avPlayer = player.avPlayer {
                        self?.playerViewController?.player = avPlayer
                    }
                }
                .store(in: &cancellables)

            // Listen for aspect ratio changes
            aspectRatioObserver = NotificationCenter.default.addObserver(
                forName: .spatialVideoPlayerAspectRatioChanged,
                object: player,
                queue: .main
            ) { [weak self] notification in
                if let aspectRatio = notification.userInfo?["aspectRatio"] as? String {
                    self?.updateVideoAspectRatio(aspectRatio)
                }
            }
        }

        private func updateVideoAspectRatio(_ aspectRatio: String) {
            guard let playerViewController = playerViewController else { return }

            switch aspectRatio {
            case "fill":
                playerViewController.videoGravity = .resizeAspectFill
            case "fit":
                playerViewController.videoGravity = .resizeAspect
            default:
                playerViewController.videoGravity = .resizeAspect
            }
        }

        deinit {
            if let observer = aspectRatioObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

// MARK: - Notification Names

public extension Notification.Name {
    static let spatialVideoPlayerAspectRatioChanged = Notification.Name("spatialVideoPlayerAspectRatioChanged")
}

// Extension to provide VLCVideoPlayer compatibility
public extension SpatialVideoPlayerView {

    func proxy(_ proxy: SpatialVideoPlayer.Proxy) -> Self {
        // Proxy is already set in init
        self
    }

    func onTicksUpdated(_ handler: @escaping (Int, SpatialVideoPlayer.PlaybackInformation) -> Void) -> Self {
        SpatialVideoPlayerView(
            configuration: configuration,
            proxy: proxy,
            onTicksUpdated: handler,
            onStateUpdated: onStateUpdated
        )
    }

    func onStateUpdated(_ handler: @escaping (SpatialVideoPlayer.State, SpatialVideoPlayer.PlaybackInformation?) -> Void) -> Self {
        SpatialVideoPlayerView(
            configuration: configuration,
            proxy: proxy,
            onTicksUpdated: onTicksUpdated,
            onStateUpdated: handler
        )
    }
}
