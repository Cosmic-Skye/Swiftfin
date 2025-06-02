//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVKit
import Combine
import CoreMedia // Add CoreMedia for CMTIME_IS_NEGATIVE
import Defaults
import JellyfinAPI
import SwiftUI

struct NativeVideoPlayer: View {

    @Environment(\.scenePhase)
    var scenePhase

    @EnvironmentObject
    private var router: VideoPlayerCoordinator.Router

    @ObservedObject
    private var videoPlayerManager: VideoPlayerManager

    @State
    private var isPresentingOverlay: Bool = false // State for iOS overlay

    init(manager: VideoPlayerManager) {
        self.videoPlayerManager = manager
    }

    @ViewBuilder
    private var playerView: some View {
        NativeVideoPlayerView(videoPlayerManager: videoPlayerManager)
    }

    var body: some View {
        ZStack { // Wrap in ZStack to allow overlay
            if videoPlayerManager.currentViewModel != nil {
                playerView
                    .onTapGesture {
                        isPresentingOverlay.toggle()
                    }
            } else {
                VideoPlayer.LoadingView()
            }

            if isPresentingOverlay && videoPlayerManager.currentViewModel != nil {
                VStack { // Main VStack for the overlay
                    Spacer() // Pushes the bottom bar to the bottom
                    IOSBottomBarView(
                        isPresentingAudioMenu: $isPresentingAudioMenu,
                        isPresentingQualityMenu: $isPresentingQualityMenu
                    )
                    .environmentObject(videoPlayerManager)
                    .environmentObject(videoPlayerManager.currentViewModel!)
                    .environmentObject(videoPlayerManager.currentProgressHandler)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .sheet(isPresented: $isPresentingAudioMenu) {
            IOSAudioSelectionMenuView(videoPlayerManager: videoPlayerManager, isPresented: $isPresentingAudioMenu)
        }
        .sheet(isPresented: $isPresentingQualityMenu) {
            IOSQualitySelectionMenuView(videoPlayerManager: videoPlayerManager, isPresented: $isPresentingQualityMenu)
        }
        .navigationBarHidden()
        .statusBarHidden()
        .ignoresSafeArea()
        .animation(.easeInOut, value: isPresentingOverlay)
        .onAppear {
            // isPresentingOverlay = true
        }
    }

    @State
    private var isPresentingAudioMenu: Bool = false
    @State
    private var isPresentingQualityMenu: Bool = false
}

struct NativeVideoPlayerView: UIViewControllerRepresentable {

    let videoPlayerManager: VideoPlayerManager

    func makeUIViewController(context: Context) -> UINativeVideoPlayerViewController {
        UINativeVideoPlayerViewController(manager: videoPlayerManager)
    }

    func updateUIViewController(_ uiViewController: UINativeVideoPlayerViewController, context: Context) {}
}

class UINativeVideoPlayerViewController: AVPlayerViewController {

    let videoPlayerManager: VideoPlayerManager

    private var rateObserver: NSKeyValueObservation!
    private var timeObserverToken: Any!
    private var itemStatusObserver: NSKeyValueObservation?
    private var avPlayerAudioSelectionGroup: AVMediaSelectionGroup?
    private var cancellables = Set<AnyCancellable>()

    init(manager: VideoPlayerManager) {

        self.videoPlayerManager = manager

        super.init(nibName: nil, bundle: nil)

        self.showsPlaybackControls = false

        let newPlayer: AVPlayer = .init(url: manager.currentViewModel.playbackURL)

        newPlayer.allowsExternalPlayback = true
        newPlayer.appliesMediaSelectionCriteriaAutomatically = false
        newPlayer.currentItem?.externalMetadata = createMetadata()
        allowsPictureInPicturePlayback = true

        rateObserver = newPlayer.observe(\.rate, options: .new) { _, change in
            guard let newValue = change.newValue else { return }
            self.videoPlayerManager.onStateUpdated(newState: newValue == 0 ? .paused : .playing)
        }

        let time = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in
            guard let self else { return }
            if time.seconds >= 0 {
                let newSeconds = Int(time.seconds)
                self.videoPlayerManager.currentProgressHandler.updatePlayerTime(
                    newSeconds: newSeconds,
                    totalDuration: self.videoPlayerManager.currentViewModel.item.runTimeSeconds
                )
            }
        }

        itemStatusObserver = newPlayer.currentItem?
            .observe(\.status, options: [.new, .initial]) { [weak self] playerItem, _ in
                guard let self = self else { return }
                if playerItem.status == .readyToPlay {
                    self.loadAndReportPlayerAudioOptions()
                    self.applyQualityLevelPreferences(self.videoPlayerManager.selectedQualityLevel)
                    if let initiallySelectedStream = self.videoPlayerManager.selectedAudioStream {
                        self.selectAudioStream(initiallySelectedStream)
                    }
                }
            }

        player = newPlayer

        videoPlayerManager.selectAudioStreamAction
            .sink { [weak self] streamToSelect in
                self?.selectAudioStream(streamToSelect)
            }
            .store(in: &cancellables)

        videoPlayerManager.selectPlayerAudioOptionAction
            .sink { [weak self] optionToSelect in
                self?.selectPlayerAudioOption(optionToSelect)
            }
            .store(in: &cancellables)

        videoPlayerManager.selectQualityLevelAction
            .sink { [weak self] qualityLevelToSelect in
                self?.applyQualityLevelPreferences(qualityLevelToSelect)
            }
            .store(in: &cancellables)

        videoPlayerManager.playAction
            .sink { [weak self] in self?.player?.play() }
            .store(in: &cancellables)

        videoPlayerManager.pauseAction
            .sink { [weak self] in self?.player?.pause() }
            .store(in: &cancellables)

        videoPlayerManager.skipForwardAction
            .sink { [weak self] interval in
                guard let self = self, let player = self.player else { return }
                let currentTime = player.currentTime()
                let targetTime = CMTimeAdd(currentTime, CMTime(seconds: interval, preferredTimescale: currentTime.timescale))
                player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            .store(in: &cancellables)

        videoPlayerManager.skipBackwardAction
            .sink { [weak self] interval in
                guard let self = self, let player = self.player else { return }
                let currentTime = player.currentTime()
                var targetTime = CMTimeSubtract(currentTime, CMTime(seconds: interval, preferredTimescale: currentTime.timescale))
                if targetTime.seconds < 0 { targetTime = .zero }
                player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            .store(in: &cancellables)

        videoPlayerManager.seekToAction
            .sink { [weak self] targetSeconds in
                guard let self = self, let player = self.player else { return }
                let targetTime = CMTime(seconds: targetSeconds, preferredTimescale: player.currentTime().timescale)
                player.seek(to: targetTime, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            .store(in: &cancellables)
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        itemStatusObserver?.invalidate()
    }

    private func loadAndReportPlayerAudioOptions() {
        guard let item = player?.currentItem, let asset = item.asset as? AVURLAsset else {
            videoPlayerManager.updatePlayerAudioOptions(options: [], group: nil, selectedOption: nil)
            return
        }
        let audibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        self.avPlayerAudioSelectionGroup = audibleGroup
        if let group = audibleGroup {
            videoPlayerManager.updatePlayerAudioOptions(
                options: group.options,
                group: group,
                selectedOption: item.selectedMediaOption(in: group)
            )
        } else {
            videoPlayerManager.updatePlayerAudioOptions(options: [], group: nil, selectedOption: nil)
        }
    }

    private func selectAudioStream(_ stream: JellyfinAPI.MediaStream) {
        guard let currentItemStatus = self.player?.currentItem?.status, currentItemStatus == .readyToPlay else {
            // logger.info("Player item not ready, deferring audio stream selection for stream: \(stream.index ?? -1)")
            return
        }
        guard let group = self.avPlayerAudioSelectionGroup else {
            // logger.warning("Audio selection group not available. Trying to load.")
            loadAndReportPlayerAudioOptions() // Try to load it
            guard let reloadedGroup = self.avPlayerAudioSelectionGroup else {
                // logger.error("Failed to load audio group on demand for stream selection.")
                return
            }
            // Check item status again after attempting to load group, before using reloadedGroup
            guard let currentItemStatusAfterReload = self.player?.currentItem?.status, currentItemStatusAfterReload == .readyToPlay else {
                // logger.info("Player item not ready after attempting to load audio group, deferring audio stream selection for stream:
                // \(stream.index ?? -1)")
                return
            }
            // Use the reloaded group for matching
            matchAndSelectAudioOption(for: stream, in: reloadedGroup)
            return
        }
        matchAndSelectAudioOption(for: stream, in: group)
    }

    private func matchAndSelectAudioOption(for stream: JellyfinAPI.MediaStream, in group: AVMediaSelectionGroup) {
        var matchedOption: AVMediaSelectionOption? = nil
        if let streamIndex32 = stream.index {
            let streamIndex = Int(streamIndex32)
            if streamIndex >= 0 && streamIndex < group.options.count {
                let potentialMatchByIndex = group.options[streamIndex]
                let optionLang = potentialMatchByIndex.extendedLanguageTag?.lowercased()
                let streamLang = stream.language?.lowercased()
                let streamItemTitle = (stream.title ?? stream.displayTitle)?.lowercased()
                let optionTitle = potentialMatchByIndex.displayName.lowercased()
                var isPlausibleMatch = false
                if let sLang = streamLang, let oLang = optionLang, sLang == oLang { isPlausibleMatch = true }
                if !isPlausibleMatch, let sTitle = streamItemTitle, !sTitle.isEmpty, sTitle != "unknown", sTitle != "und",
                   sTitle == optionTitle { isPlausibleMatch = true }
                if isPlausibleMatch { matchedOption = potentialMatchByIndex }
            }
        }

        if matchedOption == nil {
            for option in group.options {
                let optionLang = option.extendedLanguageTag?.lowercased()
                let streamLang = stream.language?.lowercased()
                let optionTitle = option.displayName.lowercased()
                let streamItemTitle = (stream.title ?? stream.displayTitle)?.lowercased()
                if let sLang = streamLang, let oLang = optionLang, sLang == oLang,
                   let sTitle = streamItemTitle, !sTitle.isEmpty, sTitle != "unknown", sTitle != "und", sTitle == optionTitle
                {
                    matchedOption = option
                    break
                }
                if matchedOption == nil, let sLang = streamLang, let oLang = optionLang, sLang == oLang,
                   streamItemTitle == nil || streamItemTitle!.isEmpty || streamItemTitle == "unknown" || streamItemTitle == "und"
                {
                    matchedOption = option
                }
                if matchedOption == nil, let sTitle = streamItemTitle, !sTitle.isEmpty, sTitle != "unknown", sTitle != "und",
                   sTitle == optionTitle,
                   streamLang == nil || optionLang == nil || streamLang != optionLang
                {
                    matchedOption = option
                }
            }
        }

        if let optionToSelect = matchedOption {
            selectPlayerAudioOption(optionToSelect)
        } else {
            // logger.error("Could not find a matching AVMediaSelectionOption for selected MediaStream: \((stream.title ??
            // stream.displayTitle) ?? "Index \(String(describing: stream.index)))")")
            loadAndReportPlayerAudioOptions() // Refresh options if no match, to ensure consistency
        }
    }

    public func selectPlayerAudioOption(_ option: AVMediaSelectionOption) {
        guard let item = player?.currentItem, let group = self.avPlayerAudioSelectionGroup else { return }
        if item.selectedMediaOption(in: group) == option {
            videoPlayerManager.updatePlayerAudioOptions(options: group.options, group: group, selectedOption: option)
            return
        }
        item.select(option, in: group)
        let currentAVPlayerSelection = item.selectedMediaOption(in: group)
        videoPlayerManager.updatePlayerAudioOptions(options: group.options, group: group, selectedOption: currentAVPlayerSelection)
    }

    private func applyQualityLevelPreferences(_ level: QualityLevel) {
        guard let item = player?.currentItem else { return }
        item.preferredPeakBitRate = level.peakBitrate ?? 0
        if let maxHeight = level.maxResolutionHeight {
            item.preferredMaximumResolution = CGSize(width: -1, height: maxHeight)
        } else {
            item.preferredMaximumResolution = .zero
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        player?.usesExternalPlaybackWhileExternalScreenIsActive = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop()
        if let timeObserverToken = self.timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        player?.seek(
            to: CMTimeMake(
                value: Int64(videoPlayerManager.currentViewModel.item.startTimeSeconds - Defaults[.VideoPlayer.resumeOffset]),
                timescale: 1
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: { _ in self.play() }
        )
    }

    private func createMetadata() -> [AVMetadataItem] { [] }

    private func createMetadataItem(for identifier: AVMetadataIdentifier, value: Any?) -> AVMetadataItem? {
        guard let value else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        item.extendedLanguageTag = "und"
        return item.copy() as? AVMetadataItem
    }

    private func play() {
        player?.play()
        videoPlayerManager.sendStartReport()
    }

    private func stop() {
        player?.pause()
        videoPlayerManager.sendStopReport()
    }
}
