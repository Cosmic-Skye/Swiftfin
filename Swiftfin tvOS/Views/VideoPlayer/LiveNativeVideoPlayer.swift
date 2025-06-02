//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVKit
import Combine
import Defaults
import JellyfinAPI
import SwiftUI

struct LiveNativeVideoPlayer: View {

    @EnvironmentObject
    private var router: LiveVideoPlayerCoordinator.Router

    @ObservedObject
    private var videoPlayerManager: LiveVideoPlayerManager

    @State
    private var isPresentingOverlay: Bool = false

    init(manager: LiveVideoPlayerManager) {
        self.videoPlayerManager = manager
    }

    @ViewBuilder
    private var playerView: some View {
        NativeVideoPlayerView(videoPlayerManager: videoPlayerManager)
    }

    var body: some View {
        Group {
            ZStack {
                if videoPlayerManager.currentViewModel != nil {
                    playerView
                        .onTapGesture { // Allow tapping on the player to toggle overlay
                            isPresentingOverlay.toggle()
                        }
                } else {
                    VideoPlayer.LoadingView()
                }

                if isPresentingOverlay && videoPlayerManager.currentViewModel != nil {
                    LiveVideoPlayer.LiveMainOverlay()
                        // Environment objects needed by LiveMainOverlay and its children:
                        // - videoPlayerManager (already an @ObservedObject here, can be passed as @EnvironmentObject)
                        // - currentProgressHandler (from videoPlayerManager)
                        // - overlayTimer (needs to be provided by parent or initialized here if local to player)
                        // - viewModel (currentViewModel from videoPlayerManager)
                        // Assuming overlayTimer is managed by a coordinator or higher-level view.
                        // For now, we ensure the essential ones are passed.
                            .environmentObject(videoPlayerManager)
                            .environmentObject(videoPlayerManager.currentProgressHandler)
                            .environmentObject(videoPlayerManager
                                .currentViewModel!
                            ) // currentViewModel is not nil here due to the if condition
                            // .environmentObject(overlayTimer) // This needs to be provided from where LiveNativeVideoPlayer is used
                            // For the overlay to dismiss on its own, an overlayTimer is typically used.
                            // This timer would be managed by the LiveVideoPlayerCoordinator or similar.
                            // We also need to pass the bindings for overlay control.
                            .environment(\.isPresentingOverlay, $isPresentingOverlay)
                    // .environment(\.currentOverlayType, $someStateForOverlayType) // If LiveMainOverlay uses this
                    // .environment(\.isScrubbing, $someScrubbingState) // If LiveMainOverlay uses this
                }
            }
        }
        .navigationBarHidden(true)
        .ignoresSafeArea()
        .onAppear {
            // Optionally, present the overlay by default when the view appears
            // isPresentingOverlay = true
            // Or, more commonly, the overlay appears on user interaction (tap)
        }
    }
}

struct LiveNativeVideoPlayerView: UIViewControllerRepresentable {

    let videoPlayerManager: VideoPlayerManager

    func makeUIViewController(context: Context) -> UILiveNativeVideoPlayerViewController {
        UILiveNativeVideoPlayerViewController(manager: videoPlayerManager)
    }

    func updateUIViewController(_ uiViewController: UILiveNativeVideoPlayerViewController, context: Context) {}
}

class UILiveNativeVideoPlayerViewController: AVPlayerViewController {

    let videoPlayerManager: VideoPlayerManager

    private var rateObserver: NSKeyValueObservation!
    private var timeObserverToken: Any!
    private var itemStatusObserver: NSKeyValueObservation?
    private var audioSelectionGroup: AVMediaSelectionGroup?
    private var cancellables = Set<AnyCancellable>() // For Combine subscriptions

    init(manager: VideoPlayerManager) {

        self.videoPlayerManager = manager

        super.init(nibName: nil, bundle: nil)

        // Hide default AVPlayerViewController controls
        self.showsPlaybackControls = false

        let newPlayer: AVPlayer = .init(url: manager.currentViewModel.hlsPlaybackURL)

        newPlayer.allowsExternalPlayback = true
        newPlayer.appliesMediaSelectionCriteriaAutomatically = false
        newPlayer.currentItem?.externalMetadata = createMetadata()

        if #available(tvOS 15.0, *) {
            // Allow Dolby Atmos spatialization format
            newPlayer.currentItem?.allowedAudioSpatializationFormats = .dolbyAtmos
        }

        rateObserver = newPlayer.observe(\.rate, options: .new) { _, change in
            guard let newValue = change.newValue else { return }

            if newValue == 0 {
                self.videoPlayerManager.onStateUpdated(newState: .paused)
            } else {
                self.videoPlayerManager.onStateUpdated(newState: .playing)
            }
        }

        let time = CMTime(seconds: 0.1, preferredTimescale: 1000)

        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: time, queue: .main) { [weak self] time in

            guard let self else { return }

            if time.seconds >= 0 {
                let newSeconds = Int(time.seconds)
                let progress = CGFloat(newSeconds) / CGFloat(self.videoPlayerManager.currentViewModel.item.runTimeSeconds)

                self.videoPlayerManager.currentProgressHandler.progress = progress
                self.videoPlayerManager.currentProgressHandler.scrubbedProgress = progress
                self.videoPlayerManager.currentProgressHandler.seconds = newSeconds
                self.videoPlayerManager.currentProgressHandler.scrubbedSeconds = newSeconds
            }
        }

        itemStatusObserver = newPlayer.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                self.loadAndReportAudioOptions()
            }
        }

        player = newPlayer

        // Subscribe to audio selection actions from the manager
        if let liveManager = manager as? LiveVideoPlayerManager {
            liveManager.selectAudioOptionAction
                .sink { [weak self] optionToSelect in
                    self?.selectAudioOption(optionToSelect)
                }
                .store(in: &cancellables)

            liveManager.selectQualityLevelAction
                .sink { [weak self] qualityLevelToSelect in
                    self?.applyQualityLevelPreferences(qualityLevelToSelect)
                }
                .store(in: &cancellables)
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        itemStatusObserver?.invalidate()
        // rateObserver is implicitly invalidated when newPlayer is deallocated if not done manually.
        // timeObserverToken needs to be removed, which is done in viewWillDisappear.
    }

    // MARK: - Media Selection

    private func loadAndReportAudioOptions() {
        guard let item = player?.currentItem, let asset = item.asset as? AVURLAsset else {
            print("Player item or asset not available for audio options.")
            return
        }

        let audibleGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        self.audioSelectionGroup = audibleGroup

        guard let liveManager = self.videoPlayerManager as? LiveVideoPlayerManager else {
            // print("LiveVideoPlayerManager not available for updating audio options.")
            // It's possible this manager is not the Live one in some contexts, though unlikely for this VC.
            return
        }

        if let group = audibleGroup {
            let options = group.options
            let currentSelection = item.selectedMediaOption(in: group)
            liveManager.updateAudioOptions(options: options, group: group, selectedOption: currentSelection)

            // For debugging:
            // print("Available audio tracks reported to manager: \(options.map { $0.displayName })")
            // if let currentSelection = currentSelection {
            //     print("Currently selected audio track reported to manager: \(currentSelection.displayName)")
            // }
        } else {
            // print("No audible media selection group found.")
            liveManager.updateAudioOptions(options: [], group: nil, selectedOption: nil)
        }
    }

    public func selectAudioOption(_ option: AVMediaSelectionOption) {
        guard let item = player?.currentItem, let group = self.audioSelectionGroup else {
            // print("Cannot select audio option: Player item or audio group not available.")
            return
        }

        // Prevent re-selecting the same track if it's already selected,
        // as select() might still trigger notifications or work.
        if item.selectedMediaOption(in: group) == option {
            // print("Audio option \(option.displayName) is already selected.")
            // Still, we should ensure the manager is up-to-date.
            if let liveManager = self.videoPlayerManager as? LiveVideoPlayerManager {
                liveManager.updateAudioOptions(options: group.options, group: group, selectedOption: option)
            }
            return
        }

        item.select(option, in: group)
        // print("Selected audio track via AVPlayer: \(option.displayName)")

        // After selection, update the manager with the new state
        if let liveManager = self.videoPlayerManager as? LiveVideoPlayerManager {
            // Re-fetch current selection to be absolutely sure
            let currentSelection = item.selectedMediaOption(in: group)
            liveManager.updateAudioOptions(options: group.options, group: group, selectedOption: currentSelection)
            // print("Manager updated with new audio selection: \(currentSelection?.displayName ?? "None")")
        }
    }

    // MARK: - Video Quality Preference

    private func applyQualityLevelPreferences(_ level: QualityLevel) {
        guard let item = player?.currentItem else {
            // print("Cannot apply quality preferences: Player item not available.")
            return
        }

        item.preferredPeakBitRate = level.peakBitrate ?? 0 // 0 means no limit / auto

        if let maxHeight = level.maxResolutionHeight {
            item.preferredMaximumResolution = CGSize(width: -1, height: maxHeight) // -1 for width means unspecified
        } else {
            item.preferredMaximumResolution = .zero // .zero means no preference
        }

        // print("Applied quality preferences: Bitrate \(item.preferredPeakBitRate), Max Height \(item.preferredMaximumResolution.height)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        stop()
        if let timeObserverToken = self.timeObserverToken {
            player?.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        itemStatusObserver?.invalidate() // Invalidate observer when view disappears
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
            completionHandler: { _ in
                self.play()
            }
        )
    }

    private func createMetadata() -> [AVMetadataItem] {
        let allMetadata: [AVMetadataIdentifier: Any?] = [
            .commonIdentifierTitle: videoPlayerManager.currentViewModel.item.displayTitle,
            .iTunesMetadataTrackSubTitle: videoPlayerManager.currentViewModel.item.subtitle,
        ]

        return allMetadata.compactMap { createMetadataItem(for: $0, value: $1) }
    }

    private func createMetadataItem(
        for identifier: AVMetadataIdentifier,
        value: Any?
    ) -> AVMetadataItem? {
        guard let value else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as? NSCopying & NSObjectProtocol
        // Specify "und" to indicate an undefined language.
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
