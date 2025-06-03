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
    private var currentPlaybackURL: URL? // Stores the URL of the currently loaded player item
    private let atmosResourceLoaderDelegate = AtmosManifestResourceLoaderDelegate() // Retain the delegate

    init(manager: VideoPlayerManager) {
        self.videoPlayerManager = manager
        super.init(nibName: nil, bundle: nil)

        // Initial player setup
        if let initialViewModel = manager.currentViewModel {
            setupPlayer(with: initialViewModel)
        } else {
            // This case should ideally not happen if the player is presented with a valid view model.
            // Handle gracefully, perhaps by showing a loading state or an error.
            print("[NativePlayer] Error: Initial currentViewModel is nil. Player cannot be set up.")
        }

        // Subscribe to changes in currentViewModel to re-initialize player if URL changes
        videoPlayerManager.$currentViewModel
            .compactMap { $0 } // Ensure we only proceed if viewModel is not nil
            .sink { [weak self] newViewModel in
                guard let self = self else { return }
                // Check if the HLS URL has actually changed, or if the player is not yet set up for the current URL
                if self.currentPlaybackURL != newViewModel.hlsPlaybackURL || self.player == nil {
                    print("[NativePlayer] currentViewModel changed or player needs setup. New URL: \(newViewModel.hlsPlaybackURL)")
                    self.setupPlayer(with: newViewModel)
                } else {
                    print(
                        "[NativePlayer] currentViewModel changed, but playback URL is the same (\(newViewModel.hlsPlaybackURL)). No player re-initialization needed from this sink."
                    )
                }
            }
            .store(in: &cancellables) // Store this subscription

        // Action Subscriptions (remain here as they are tied to the manager, not a specific player instance)
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
        cleanupPlayer() // Ensure all resources are released
        cancellables.forEach { $0.cancel() } // Cancel Combine subscriptions
    }

    private func cleanupPlayer() {
        print("[NativePlayer] cleanupPlayer called.")
        // Invalidate KVO observers
        rateObserver?.invalidate()
        rateObserver = nil
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil

        // Remove periodic time observer
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        // Nil out player and related properties
        player?.pause() // Pause before nilling out
        player = nil
        currentPlaybackURL = nil
        avPlayerAudioSelectionGroup = nil
        // availablePlayerAudioOptions and selectedPlayerAudioOption are managed by VideoPlayerManager,
        // but good to reset local state if any was directly tied to player item.
        // For now, they are updated via loadAndReportPlayerAudioOptions which is called on new item.
    }

    private func setupPlayer(with viewModel: VideoPlayerViewModel) {
        print("[NativePlayer] setupPlayer called with URL: \(viewModel.hlsPlaybackURL)")
        // Only proceed if the URL has changed OR if the player is currently nil (needs initial setup)
        guard currentPlaybackURL != viewModel.hlsPlaybackURL || self.player == nil else {
            print(
                "[NativePlayer] Playback URL is the same (\(viewModel.hlsPlaybackURL)) and player instance exists. Skipping redundant setup."
            )
            return
        }

        cleanupPlayer() // Clean up any existing player instance first

        self.showsPlaybackControls = false // This is an AVPlayerViewController property

        let originalPlaybackURL = viewModel.hlsPlaybackURL // Assuming hlsPlaybackURL is non-optional URL
        let playerItem: AVPlayerItem

        // Temporarily disabling interceptor for testing direct playback
        print("[NativePlayer] Atmos interceptor temporarily disabled. Using direct playback.")
        let asset = AVURLAsset(url: originalPlaybackURL)
        playerItem = AVPlayerItem(asset: asset)
        // // Determine if the selected audio stream is likely Atmos
        // let selectedStream = viewModel.audioStreams.first { $0.index == viewModel.selectedAudioStreamIndex }
        // let isLikelyAtmos = selectedStream?.profile?.localizedCaseInsensitiveContains("atmos") == true ||
        //     selectedStream?.codec?.localizedCaseInsensitiveContains("joc") == true || // JOC in codec
        //     selectedStream?.displayTitle?.localizedCaseInsensitiveContains("atmos") == true // Atmos in display title

        // if isLikelyAtmos, let customURL = AtmosManifestResourceLoaderDelegate.customURL(from: originalPlaybackURL) {
        //     print("[NativePlayer] Selected audio stream appears to be Atmos. Using custom URL for interceptor:
        //     \(customURL.absoluteString)")
        //     atmosResourceLoaderDelegate.masterPlaylistOriginalURL = originalPlaybackURL
        //     let asset = AVURLAsset(url: customURL)
        //     asset.resourceLoader.setDelegate(atmosResourceLoaderDelegate, queue: DispatchQueue.main)
        //     playerItem = AVPlayerItem(asset: asset)
        // } else {
        //     if isLikelyAtmos { // customURL creation must have failed if isLikelyAtmos is true but we are in else
        //         print(
        //             "[NativePlayer] Error: Could not create custom URL for Atmos stream (\(originalPlaybackURL.absoluteString)). Falling
        //             back to direct playback."
        //         )
        //     } else {
        //         print(
        //             "[NativePlayer] Selected audio stream (\(selectedStream?.displayTitle ?? "Unknown")) does not appear to be Atmos.
        //             Using direct playback."
        //         )
        //     }
        //     let asset = AVURLAsset(url: originalPlaybackURL)
        //     playerItem = AVPlayerItem(asset: asset)
        // }

        let newPlayer = AVPlayer(playerItem: playerItem)
        self.currentPlaybackURL = originalPlaybackURL // Store the original URL for comparison logic

        newPlayer.allowsExternalPlayback = true
        newPlayer.appliesMediaSelectionCriteriaAutomatically = false // We handle selection
        newPlayer.currentItem?.externalMetadata = createMetadata() // For Now Playing info
        allowsPictureInPicturePlayback = true // AVPlayerViewController property

        // Setup KVO for player rate (play/pause state)
        rateObserver = newPlayer.observe(\.rate, options: .new) { [weak self] _, change in
            guard let self = self, let newValue = change.newValue else { return }
            self.videoPlayerManager.onStateUpdated(newState: newValue == 0 ? .paused : .playing)
        }

        // Setup periodic time observer for progress updates
        let timeInterval = CMTime(seconds: 0.1, preferredTimescale: 1000)
        timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: timeInterval, queue: .main) { [weak self] time in
            guard let self = self, let currentVM = self.videoPlayerManager.currentViewModel else { return }
            if time.seconds >= 0 {
                let newSeconds = Int(time.seconds)
                self.videoPlayerManager.currentProgressHandler.updatePlayerTime(
                    newSeconds: newSeconds,
                    totalDuration: currentVM.item.runTimeSeconds
                )
            }
        }

        // Setup KVO for player item status (readyToPlay, failed, etc.)
        itemStatusObserver = newPlayer.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self] playerItem, _ in
            guard let self = self else { return }
            switch playerItem.status {
            case .readyToPlay:
                print("[NativePlayer] PlayerItem status: readyToPlay")
                self.loadAndReportPlayerAudioOptions() // Load audio options from the new item
                self.applyQualityLevelPreferences(self.videoPlayerManager.selectedQualityLevel)
                if #available(iOS 15.0, *) {
                    playerItem.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
                }
                // Log track details (as before)
                print("[AVPlayerItem Track Details]")
                for (trackIndex, track) in playerItem.tracks.enumerated() {
                    print("  Track \(trackIndex + 1):")
                    print("    AVPlayerItemTrack isEnabled: \(track.isEnabled)")
                    if let assetTrack = track.assetTrack {
                        print("    AssetTrack available: true")
                        print("    AssetTrack ID: \(assetTrack.trackID)")
                        print("    AssetTrack mediaType: \(assetTrack.mediaType.rawValue)")
                        print("    AssetTrack isPlayable: \(assetTrack.isPlayable)")
                        print("    AssetTrack isEnabled: \(assetTrack.isEnabled)")
                        print("    AssetTrack naturalSize: \(assetTrack.naturalSize)")
                        print("    AssetTrack preferredTransform: \(assetTrack.preferredTransform)")
                        print("    AssetTrack preferredVolume: \(assetTrack.preferredVolume)")
                        print("    AssetTrack estimatedDataRate: \(assetTrack.estimatedDataRate)")
                        print("    AssetTrack totalSampleDataLength: \(assetTrack.totalSampleDataLength)")

                        let formatDescriptions = assetTrack.formatDescriptions
                        print("    Format Descriptions Array Count: \(formatDescriptions.count)")
                        if formatDescriptions.isEmpty {
                            print("    Detailed Format Descriptions: EMPTY_ARRAY (assetTrack.formatDescriptions was empty)")
                            print("    AssetTrack Common Metadata (Fallback):")
                            for metadataItem in assetTrack.commonMetadata {
                                if let commonKey = metadataItem.commonKey?.rawValue {
                                    print("      \(commonKey): \(metadataItem.value?.description ?? "N/A")")
                                } else if let keyString = metadataItem.key as? String {
                                    print("      \(keyString): \(metadataItem.value?.description ?? "N/A")")
                                } else {
                                    print(
                                        "      Unknown Key (\(metadataItem.key?.description ?? "No Key")): \(metadataItem.value?.description ?? "N/A")"
                                    )
                                }
                            }
                        } else {
                            print("    Format Descriptions (\(formatDescriptions.count)):")
                            // ... (existing detailed format description logging) ...
                            for (i, desc) in formatDescriptions.enumerated() {
                                let formatDesc = desc as! CMFormatDescription
                                print("      Desc \(i):")
                                let mediaType = CMFormatDescriptionGetMediaType(formatDesc)
                                if mediaType == kCMMediaType_Audio {
                                    let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
                                    if let asbdPtr = asbd {
                                        let formatID = asbdPtr.pointee.mFormatID
                                        let formatIDHex = String(format: "0x%08x", formatID)
                                        print("        MediaType: Audio")
                                        print("        Format ID: \(formatIDHex) ('\(self.fourCharCodeToString(formatID))')")
                                        print("        Channels Per Frame: \(asbdPtr.pointee.mChannelsPerFrame)")
                                        if let layoutPtr = CMAudioFormatDescriptionGetChannelLayout(formatDesc, sizeOut: nil) {
                                            print(
                                                "        Channel Layout Tag: \(layoutPtr.pointee.mChannelLayoutTag) (\(String(format: "0x%08x", layoutPtr.pointee.mChannelLayoutTag)))"
                                            )
                                        } else {
                                            print("        Channel Layout Tag: N/A")
                                        }
                                    } else {
                                        print("        Could not get ASBD for audio format description.")
                                    }
                                } else if mediaType == kCMMediaType_Video {
                                    let dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc)
                                    print("        MediaType: Video")
                                    print("        Dimensions: \(dimensions.width)x\(dimensions.height)")
                                    print("        Codec: '\(self.fourCharCodeToString(CMFormatDescriptionGetMediaSubType(formatDesc)))'")
                                } else if mediaType == kCMMediaType_Subtitle {
                                    print("        MediaType: Subtitle")
                                    print("        Codec: '\(self.fourCharCodeToString(CMFormatDescriptionGetMediaSubType(formatDesc)))'")
                                } else if mediaType == kCMMediaType_Text {
                                    print("        MediaType: Text")
                                    print("        Codec: '\(self.fourCharCodeToString(CMFormatDescriptionGetMediaSubType(formatDesc)))'")
                                } else {
                                    print(
                                        "        Unknown MediaType: '\(self.fourCharCodeToString(mediaType))' (Subtype: '\(self.fourCharCodeToString(CMFormatDescriptionGetMediaSubType(formatDesc)))')"
                                    )
                                }
                            }
                        }
                    } else {
                        print("    AssetTrack available: false (track.assetTrack is nil)")
                    }
                }

                // Auto-select the audio stream designated by the ViewModel (which might be from user selection or default)
                if let initiallySelectedStream = self.videoPlayerManager.selectedAudioStream {
                    print(
                        "[NativePlayer] ReadyToPlay: Attempting to select initial/designated audio stream: \(initiallySelectedStream.displayTitle ?? "N/A") (Index: \(initiallySelectedStream.index ?? -1))"
                    )
                    self.selectAudioStream(initiallySelectedStream)
                }
            // Consider auto-play after seek from viewDidAppear or directly here if not resuming
            // For now, play() is called from viewDidAppear's seek completion.
            case .failed:
                print("[NativePlayer] PlayerItem status: failed. Error: \(playerItem.error?.localizedDescription ?? "Unknown error")")
            // Handle error appropriately (e.g., show alert, report to manager)
            case .unknown:
                print("[NativePlayer] PlayerItem status: unknown.")
            @unknown default:
                print("[NativePlayer] PlayerItem status: new unhandled case.")
            }
        }
        self.player = newPlayer // Assign the new player to the AVPlayerViewController's player property

        // If resuming, viewDidAppear will handle seek & play.
        // If starting fresh, we might need to call play() here or after item is ready.
        // For now, let's assume viewDidAppear handles the initial play after seek.
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
                selectedOption: item.currentMediaSelection.selectedMediaOption(in: group)
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
        print("[NativePlayer] matchAndSelectAudioOption called.")
        print("  Attempting to select JellyfinAPI.MediaStream:")
        print(
            "    Index: \(stream.index ?? -1), Display: \(stream.displayTitle ?? "N/A"), Codec: \(stream.codec ?? "N/A"), Lang: \(stream.language ?? "N/A")"
        )
        print("  AVMediaSelectionGroup has \(group.options.count) options available in current HLS stream:")
        for (idx, opt) in group.options.enumerated() {
            print(
                "    Option \(idx + 1): DisplayName: '\(opt.displayName)', Language: '\(opt.extendedLanguageTag ?? "N/A")', MediaType: '\(opt.mediaType.rawValue)'"
            )
        }

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
            print(
                "  Match found: Will attempt to select AVPlayerOption: DisplayName: '\(optionToSelect.displayName)', Language: '\(optionToSelect.extendedLanguageTag ?? "N/A")'"
            )
            selectPlayerAudioOption(optionToSelect)
        } else {
            print(
                "  No suitable AVMediaSelectionOption found in the current HLS stream for the requested MediaStream (Index: \(stream.index ?? -1), Display: \(stream.displayTitle ?? "N/A"))."
            )
            // logger.error("Could not find a matching AVMediaSelectionOption for selected MediaStream: \((stream.title ??
            // stream.displayTitle) ?? "Index \(String(describing: stream.index)))")")
            loadAndReportPlayerAudioOptions() // Refresh options if no match, to ensure consistency
        }
    }

    public func selectPlayerAudioOption(_ option: AVMediaSelectionOption) {
        guard let item = player?.currentItem, let group = self.avPlayerAudioSelectionGroup else { return }

        // Log AVMediaSelectionOption details (simplified)
        var optionDetails = "[AVMediaSelectionOption Details] Selecting option:\n"
        optionDetails += "  Display Name: \(option.displayName)\n"
        optionDetails += "  Extended Language Tag: \(option.extendedLanguageTag ?? "N/A")\n"
        optionDetails += "  Media Type: \(option.mediaType.rawValue)\n" // Removed optional chaining
        if #available(iOS 15.0, tvOS 15.0, *) {
            optionDetails += "  Common Metadata:\n"
            for metaItem in option.commonMetadata {
                optionDetails += "    - \(metaItem.commonKey?.rawValue ?? "Unknown key"): \(metaItem.value?.description ?? "N/A")\n"
            }
        }
        // Use your logger here if available, otherwise print
        print(optionDetails)

        if item.currentMediaSelection.selectedMediaOption(in: group) == option {
            videoPlayerManager.updatePlayerAudioOptions(options: group.options, group: group, selectedOption: option)
            return
        }
        item.select(option, in: group)
        let currentAVPlayerSelection = item.currentMediaSelection.selectedMediaOption(in: group)
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
            completionHandler: { [weak self] finished in
                if finished {
                    self?.play()
                }
            }
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

    private func fourCharCodeToString(_ fourCharCode: FourCharCode) -> String {
        let c1 = Character(UnicodeScalar((fourCharCode >> 24) & 0xFF) ?? " ")
        let c2 = Character(UnicodeScalar((fourCharCode >> 16) & 0xFF) ?? " ")
        let c3 = Character(UnicodeScalar((fourCharCode >> 8) & 0xFF) ?? " ")
        let c4 = Character(UnicodeScalar(fourCharCode & 0xFF) ?? " ")
        // Filter out non-printable ASCII characters and trim whitespace
        let chars = [c1, c2, c3, c4].filter { char in
            guard let scalar = char.unicodeScalars.first else { return false }
            return scalar.isASCII && (char.isLetter || char.isNumber || char.isPunctuation || char == " ") // Allow space
        }
        return String(chars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
