//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Combine
import Defaults
import Foundation
import JellyfinAPI
import MediaPlayer
import UIKit
import VLCUI

// TODO: better online/offline handling
// TODO: proper error catching
// TODO: better solution for previous/next/queuing
// TODO: should view models handle progress reports instead, with a protocol
//       for other types of media handling

// TODO: transition to `Stateful`
class VideoPlayerManager: ViewModel {

    class CurrentProgressHandler: ObservableObject {

        @Published
        var progress: CGFloat = 0 // Actual player progress
        @Published
        var scrubbedProgress: CGFloat = 0 // Progress value from slider interaction

        @Published
        var seconds: Int = 0 // Actual player time in seconds
        @Published
        var scrubbedSeconds: Int = 0 // Time in seconds based on slider interaction

        @Published
        var isScrubbing: Bool = false

        // Call this from the player's time observer
        func updatePlayerTime(newSeconds: Int, totalDuration: Int) {
            guard !isScrubbing else { return } // Don't update if user is actively scrubbing

            let newProgress = totalDuration > 0 ? CGFloat(newSeconds) / CGFloat(totalDuration) : 0

            // Update properties on the main thread as they are @Published
            DispatchQueue.main.async {
                self.seconds = newSeconds
                self.progress = newProgress

                // Also update scrubbed values if not scrubbing, so slider reflects current time
                self.scrubbedSeconds = newSeconds
                self.scrubbedProgress = newProgress
            }
        }

        // Call this when the slider value changes (onEditingChanged)
        func updateScrubbingState(editing: Bool, currentSliderValue: CGFloat, totalDuration: Int) {
            DispatchQueue.main.async {
                self.isScrubbing = editing
                self.scrubbedProgress = currentSliderValue
                self.scrubbedSeconds = Int(currentSliderValue * CGFloat(totalDuration))
            }
        }
    }

    @Published
    var audioTrackIndex: Int = -1
    @Published
    var state: VLCVideoPlayer.State = .opening
    @Published
    var subtitleTrackIndex: Int = -1
    @Published
    var playbackSpeed: PlaybackSpeed = PlaybackSpeed.one

    // MARK: - AVPlayer Audio Track Selection

    // Holds AVPlayer's view of available audio tracks
    @Published
    var availablePlayerAudioOptions: [AVMediaSelectionOption] = []
    @Published
    var selectedPlayerAudioOption: AVMediaSelectionOption? = nil

    // Holds server/media item's view of available audio streams (for UI)
    @Published
    var availableAudioStreams: [JellyfinAPI.MediaStream] = [] // Changed MediaStreamInfo to MediaStream
    @Published
    var selectedAudioStream: JellyfinAPI.MediaStream? = nil // Changed MediaStreamInfo to MediaStream

    // This group is needed by AVPlayerViewController to select an option.
    // It's not directly used by UI, so not @Published.
    var audioSelectionGroup: AVMediaSelectionGroup?

    // Action for UI to request selection of a MediaStream
    let selectAudioStreamAction = PassthroughSubject<JellyfinAPI.MediaStream, Never>() // Changed MediaStreamInfo to MediaStream
    // Action for VideoPlayerManager to command AVPlayerViewController to select a specific AVMediaSelectionOption
    let selectPlayerAudioOptionAction = PassthroughSubject<AVMediaSelectionOption, Never>()

    // MARK: - AVPlayer Video Quality Selection

    @Published
    var availableQualityLevels: [QualityLevel] = [] // Default to empty, populated by setupQualityLevels
    @Published
    var selectedQualityLevel: QualityLevel = .auto // Default to auto
    let selectQualityLevelAction = PassthroughSubject<QualityLevel, Never>()

    // MARK: - AVPlayer Playback Control Actions

    let playAction = PassthroughSubject<Void, Never>()
    let pauseAction = PassthroughSubject<Void, Never>()
    let skipForwardAction = PassthroughSubject<TimeInterval, Never>() // Value is seconds to skip
    let skipBackwardAction = PassthroughSubject<TimeInterval, Never>() // Value is seconds to skip
    let seekToAction = PassthroughSubject<TimeInterval, Never>() // Value is target time in seconds

    // MARK: ViewModel

    @Published
    var previousViewModel: VideoPlayerViewModel?
    @Published
    var currentViewModel: VideoPlayerViewModel! {
        willSet {
            guard let newValue else { return }
            hasSentStart = false
            getAdjacentEpisodes(for: newValue.item)

            // Populate availableAudioStreams from the new view model
            DispatchQueue.main.async {
                // Log container and video stream details
                self.logger.info("""
                [PlayerManager Init] Media Source Container: \(newValue.mediaSource.container ?? "N/A")
                """)
                if let videoStream = newValue.item.mediaStreams?.first(where: { $0.type == .video }) {
                    self.logger.info("""
                    [PlayerManager Init] Video Stream Details:
                      Codec: \(videoStream.codec ?? "N/A")
                      Profile: \(videoStream.profile ?? "N/A")
                      Bitrate: \(videoStream.bitRate ?? -1)
                      Width: \(videoStream.width ?? -1)
                      Height: \(videoStream.height ?? -1)
                    """)
                } else {
                    self.logger.info("[PlayerManager Init] No video stream found in item.")
                }

                // Log all available audio streams
                if let streams = newValue.item.mediaStreams { // Safely unwrap
                    self.availableAudioStreams = streams.filter { $0.type == .audio }
                    self.logger.info("[PlayerManager Init] All Available Audio MediaStreams from Server:")
                    for stream in self.availableAudioStreams {
                        self.logger.info("""
                        - Index: \(stream.index ?? -1), Title: \(stream.title ?? "N/A"), Display: \(stream
                            .displayTitle ?? "N/A"), Codec: \(stream.codec ?? "N/A"), Profile: \(stream.profile ?? "N/A"), Lang: \(stream
                            .language ?? "N/A"), Channels: \(stream.channels ?? -1), Bitrate: \(stream
                            .bitRate ?? -1), Default: \(String(describing: stream.isDefault))
                        """)
                    }
                } else {
                    self.availableAudioStreams = []
                    self.logger.info("[PlayerManager Init] No media streams found in item.")
                }

                // Set selected audio stream
                if let defaultAudioIndex = newValue.mediaSource.defaultAudioStreamIndex,
                   defaultAudioIndex < self.availableAudioStreams.count
                {
                    self.selectedAudioStream = self.availableAudioStreams[defaultAudioIndex]
                } else if let firstAudioStream = self.availableAudioStreams.first {
                    self.selectedAudioStream = firstAudioStream
                } else {
                    self.selectedAudioStream = nil
                }

                if let selected = self.selectedAudioStream {
                    self.logger
                        .info(
                            "[PlayerManager Init] Initially selected audio stream (by default/first): Index \(selected.index ?? -1), Display: \(selected.displayTitle ?? "N/A")"
                        )
                } else {
                    self.logger.info("[PlayerManager Init] No audio stream initially selected.")
                }

                // The OnlineVideoPlayerManager is now responsible for creating the initial
                // currentViewModel with the correct selectedAudioStreamIndex.
                // This mismatch detection logic is no longer needed here.
                // The primary role of this willSet's async block is to update UI-related properties
                // like availableAudioStreams and the manager's own selectedAudioStream (MediaStream object)
                // based on the already correctly configured newValue (VideoPlayerViewModel).

                // Reset player-specific options until AVPlayer loads them
                self.availablePlayerAudioOptions = []
                self.selectedPlayerAudioOption = nil
                self.audioSelectionGroup = nil
            }
        }
    }

    @Published
    var nextViewModel: VideoPlayerViewModel?

    var currentProgressHandler: CurrentProgressHandler = .init()
    let proxy: VLCVideoPlayer.Proxy = .init()

    private var currentProgressWorkItem: DispatchWorkItem?
    private var hasSentStart = false

    private let commandCenter = MPRemoteCommandCenter.shared()

    override init() {
        super.init()
        setupControlListeners()
        setupQualityLevels() // Initialize quality levels
    }

    // MARK: - Public Methods for AVPlayer Audio Track Management

    // Called by UINativeVideoPlayerViewController when AVPlayerItem loads its tracks
    func updatePlayerAudioOptions(
        options: [AVMediaSelectionOption],
        group: AVMediaSelectionGroup?,
        selectedOption: AVMediaSelectionOption?
    ) {
        DispatchQueue.main.async {
            self.logger.info("[PlayerManager] updatePlayerAudioOptions called.")
            self.logger.info("  Received \(options.count) AVMediaSelectionOptions.")
            if let group = group {
                self.logger.info("  AudioSelectionGroup allowsEmptySelection: \(group.allowsEmptySelection)")
            } else {
                self.logger.info("  AudioSelectionGroup: nil")
            }

            for (index, option) in options.enumerated() {
                var optionLog = "  Option \(index + 1):\n"
                optionLog += "    Display Name: \(option.displayName)\n"
                optionLog += "    Extended Language Tag: \(option.extendedLanguageTag ?? "N/A")\n"
                optionLog += "    Media Type: \(option.mediaType.rawValue)\n" // AVMediaType is not optional
                optionLog += "    Playable: \(option.isPlayable)\n"

                if #available(iOS 15.0, tvOS 15.0, *) {
                    optionLog += "    Common Metadata:\n"
                    if option.commonMetadata.isEmpty {
                        optionLog += "      (No common metadata)\n"
                    }
                    for metaItem in option.commonMetadata {
                        optionLog += "      - \(metaItem.commonKey?.rawValue ?? "Unknown key"): \(metaItem.value?.description ?? "N/A")\n"
                    }

                    // AVMediaSelectionOption does not have formatDescriptions directly.
                    // Format descriptions are on AVAssetTrack or AVPlayerItemTrack,
                    // which are logged in NativeVideoPlayer.swift.
                    // We will log common metadata here as it's available on AVMediaSelectionOption.
                }
                self.logger.info("\(optionLog)")
            }

            if let selOpt = selectedOption {
                self.logger.info("  Initially Selected AVMediaSelectionOption:")
                self.logger.info("    Display Name: \(selOpt.displayName)")
                self.logger.info("    Extended Language Tag: \(selOpt.extendedLanguageTag ?? "N/A")")
                self.logger.info("    Playable: \(String(describing: selOpt.isPlayable))")
            } else {
                self.logger.info("  Initially Selected AVMediaSelectionOption: nil")
            }

            self.availablePlayerAudioOptions = options
            self.audioSelectionGroup = group // Keep this for AVPlayer to use
            self.selectedPlayerAudioOption = selectedOption

            // Update the legacy audioTrackIndex if possible, for any part of UI still using it
            if let selOpt = selectedOption, let idx = options.firstIndex(of: selOpt) {
                self.audioTrackIndex = idx
            } else if options.isEmpty {
                self.audioTrackIndex = -1
            }

            // Attempt to map the AVPlayer's selected option back to a MediaStream
            if let avOption = selectedOption {
                // Simple index-based mapping for now. A more robust solution might involve language or title matching.
                if let streamIndex = options.firstIndex(of: avOption), streamIndex < self.availableAudioStreams.count {
                    // This assumes the order of AVMediaSelectionOption matches availableAudioStreams,
                    // which might not always be true. A more robust mapping is needed if issues arise.
                    // For now, let's try to find by display name or language if index is not directly usable.
                    let matchedStream = self.availableAudioStreams.first(where: { stream in // stream is now MediaStream
                        // Heuristic: Match by language if display name is generic, or by display name
                        let langMatch = stream.language?.lowercased() == avOption.extendedLanguageTag?.lowercased()
                        // MediaStream might use .title instead of .displayTitle, or .name
                        // Assuming .title for now, or check common properties.
                        let titleMatch = (stream.title ?? stream.displayTitle)?.lowercased() == avOption.displayName.lowercased()

                        if langMatch && titleMatch { return true }
                        if langMatch &&
                            (avOption.displayName.lowercased() == "unknown" || avOption.displayName.isEmpty || avOption.displayName
                                .lowercased() == "und"
                            ) { return true }
                        return titleMatch // Fallback to title match
                    })
                    self.selectedAudioStream = matchedStream ?? self.selectedAudioStream // Keep old if no match
                    if matchedStream != nil {
                        self.logger
                            .info(
                                "  Successfully mapped selected AVPlayerOption '\(avOption.displayName)' back to MediaStream '\(matchedStream?.displayTitle ?? "N/A")'"
                            )
                    } else {
                        self.logger.warning("  Could NOT map selected AVPlayerOption '\(avOption.displayName)' back to a MediaStream.")
                    }
                } else {
                    self.logger.warning("  Selected AVPlayerOption index out of bounds or not found for mapping to MediaStream.")
                }
            }
        }
    }

    // Called by UI (e.g., IOSAudioSelectionMenuView)
    func selectAudioStream(_ stream: JellyfinAPI.MediaStream) { // Changed MediaStreamInfo to MediaStream
        guard availableAudioStreams.contains(where: { $0.index == stream.index && $0.type == .audio }) else {
            logger.error("Attempted to select an unavailable audio stream: \((stream.title ?? stream.displayTitle) ?? "Unknown")")
            return
        }
        self.selectedAudioStream = stream // Update the MediaStream object for UI state (e.g., checkmark in menu)

        let newAudioStreamIndex = stream.index ?? 0 // Default to 0 if nil

        // Log MediaStream details of the user's selection
        logger.info("""
        [MediaStream Details] User selected audio stream from UI:
        Index: \(newAudioStreamIndex)
        Title: \(stream.title ?? "N/A")
        Display Title: \(stream.displayTitle ?? "N/A")
        Codec: \(stream.codec ?? "N/A")
        Profile: \(stream.profile ?? "N/A")
        Language: \(stream.language ?? "N/A")
        """)

        guard let currentVM = self.currentViewModel else {
            logger.error("Cannot change audio stream: currentViewModel is nil.")
            return
        }

        if newAudioStreamIndex != currentVM.selectedAudioStreamIndex {
            logger
                .info(
                    "Audio stream selection (index \(newAudioStreamIndex)) differs from current ViewModel's audio index (\(currentVM.selectedAudioStreamIndex)). Creating new ViewModel to re-initialize player."
                )

            // Note: VideoPlayerViewModel's hlsPlaybackURL is computed based on its properties,
            // including selectedAudioStreamIndex. We don't pass a new URL to init.
            // The playbackURL param for init is the general one (e.g. for VLC).
            // startTimeTicks is not part of VideoPlayerViewModel init, seeking is handled by the player.

            let newViewModel = VideoPlayerViewModel(
                playbackURL: currentVM.playbackURL, // Original base playback URL
                item: currentVM.item,
                mediaSource: currentVM.mediaSource,
                playSessionID: currentVM.playSessionID,
                // Pass the original full lists of streams from the mediaSource for internal processing by VideoPlayerViewModel init
                videoStreams: currentVM.mediaSource.mediaStreams?.filter { $0.type == .video } ?? [],
                audioStreams: currentVM.mediaSource.mediaStreams?.filter { $0.type == .audio } ?? [],
                subtitleStreams: currentVM.mediaSource.mediaStreams?.filter { $0.type == .subtitle } ?? [],
                selectedAudioStreamIndex: newAudioStreamIndex, // <<< KEY: Set the new audio index
                selectedSubtitleStreamIndex: currentVM.selectedSubtitleStreamIndex, // Keep current subtitle selection
                chapters: currentVM.chapters, // Pass existing chapters
                playMethod: currentVM.playMethod
            )

            // Setting currentViewModel will trigger its 'willSet' and also notify
            // UINativeVideoPlayerViewController to reload the player.
            self.currentViewModel = newViewModel

            // DO NOT send selectAudioStreamAction here, as the player will be re-initialized.
        } else {
            logger
                .info(
                    "Selected audio stream index \(newAudioStreamIndex) is the same as current ViewModel's audio index. Sending action to select within current player (if possible)."
                )
            selectAudioStreamAction.send(stream)
        }
    }

    // Renamed: Kept for internal use if AVPlayer needs direct AVMediaSelectionOption command
    // This might be deprecated if selectAudioStreamAction is sufficient
    func selectPlayerAudioOption(_ option: AVMediaSelectionOption) {
        guard availablePlayerAudioOptions.contains(option) else {
            logger.error("Attempted to select an unavailable player audio option: \(option.displayName)")
            return
        }
        selectPlayerAudioOptionAction.send(option)
    }

    // MARK: - Public Methods for AVPlayer Video Quality Management

    private func setupQualityLevels() {
        DispatchQueue.main.async {
            self.availableQualityLevels = QualityLevel.allPredefined
            if let autoLevel = QualityLevel.allPredefined.first(where: { $0.id == "auto" }) {
                self.selectedQualityLevel = autoLevel
            } else if let firstLevel = QualityLevel.allPredefined.first {
                self.selectedQualityLevel = firstLevel
            }
        }
    }

    func updateAvailableQualityLevels(levels: [QualityLevel]) {
        DispatchQueue.main.async {
            self.availableQualityLevels = levels
            if !levels.contains(self.selectedQualityLevel) {
                self.selectedQualityLevel = levels.first(where: { $0.id == "auto" }) ?? levels.first ?? .auto
            }
        }
    }

    func selectQualityLevel(_ level: QualityLevel) {
        guard availableQualityLevels.contains(level) else {
            logger.error("Attempted to select an unavailable quality level: \(level.name)")
            return
        }
        // Actual application of quality happens in AVPlayerViewController.
        // UI can optimistically update.
        self.selectedQualityLevel = level
        selectQualityLevelAction.send(level)
    }

    func selectNextViewModel() {
        guard let nextViewModel else { return }
        currentViewModel = nextViewModel
        previousViewModel = nil
        self.nextViewModel = nil
    }

    func selectPreviousViewModel() {
        guard let previousViewModel else { return }
        currentViewModel = previousViewModel
        self.previousViewModel = nil
        nextViewModel = nil
    }

    func onTicksUpdated(ticks: Int, playbackInformation: VLCVideoPlayer.PlaybackInformation) {

        if audioTrackIndex != playbackInformation.currentAudioTrack.index {
            audioTrackIndex = playbackInformation.currentAudioTrack.index
        }

        if subtitleTrackIndex != playbackInformation.currentSubtitleTrack.index {
            subtitleTrackIndex = playbackInformation.currentSubtitleTrack.index
        }
    }

    func onStateUpdated(newState: VLCVideoPlayer.State) {
        guard state != newState else { return }
        state = newState

        if !hasSentStart, newState == .playing {
            hasSentStart = true
            sendStartReport()
        }

        if hasSentStart, newState == .paused {
            hasSentStart = false
            sendPauseReport()
        }

        if newState == .stopped || newState == .ended {
            sendStopReport()
        }
    }

    func getAdjacentEpisodes(for item: BaseItemDto) {
        Task { @MainActor in
            guard let seriesID = item.seriesID, item.type == .episode else { return }

            let parameters = Paths.GetEpisodesParameters(
                userID: userSession.user.id,
                fields: .MinimumFields,
                adjacentTo: item.id!,
                limit: 3
            )
            let request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
            let response = try await userSession.client.send(request)

            // 4 possible states:
            //  1 - only current episode
            //  2 - two episodes with next episode
            //  3 - two episodes with previous episode
            //  4 - three episodes with current in middle

            // 1
            guard let items = response.value.items, items.count > 1 else { return }

            var previousItem: BaseItemDto?
            var nextItem: BaseItemDto?

            if items.count == 2 {
                if items[0].id == item.id {
                    // 2
                    nextItem = items[1]

                } else {
                    // 3
                    previousItem = items[0]
                }
            } else {
                nextItem = items[2]
                previousItem = items[0]
            }

            var nextViewModel: VideoPlayerViewModel?
            var previousViewModel: VideoPlayerViewModel?

            if let nextItem, let nextItemMediaSource = nextItem.mediaSources?.first {
                nextViewModel = try await nextItem.videoPlayerViewModel(with: nextItemMediaSource)
            }

            if let previousItem, let previousItemMediaSource = previousItem.mediaSources?.first {
                previousViewModel = try await previousItem.videoPlayerViewModel(with: previousItemMediaSource)
            }

            await MainActor.run {
                self.nextViewModel = nextViewModel
                self.previousViewModel = previousViewModel
            }
        }
    }

    func sendStartReport() {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        currentProgressWorkItem?.cancel()

        logger.debug("sent start report")

        Task {
            let startInfo = PlaybackStartInfo(
                audioStreamIndex: audioTrackIndex,
                itemID: currentViewModel.item.id,
                mediaSourceID: currentViewModel.mediaSource.id,
                playbackStartTimeTicks: Int(Date().timeIntervalSince1970) * 10_000_000,
                positionTicks: currentProgressHandler.seconds * 10_000_000,
                sessionID: currentViewModel.playSessionID,
                subtitleStreamIndex: subtitleTrackIndex
            )

            let request = Paths.reportPlaybackStart(startInfo)
            let _ = try await userSession.client.send(request)

            let progressTask = DispatchWorkItem {
                self.sendProgressReport()
            }

            currentProgressWorkItem = progressTask

            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: progressTask)
        }
    }

    func sendStopReport() {

        // TODO: This entire system is being redone in other PRs,
        //       can ignore the fact this is commented out for now.
        // let ids = ["itemID": currentViewModel.item.id, "seriesID": currentViewModel.item.parentID] // This was unused
//        Notifications[.itemMetadataDidChange].post(ids)

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        logger.debug("sent stop report")

        currentProgressWorkItem?.cancel()

        Task {
            let stopInfo = PlaybackStopInfo(
                itemID: currentViewModel.item.id,
                mediaSourceID: currentViewModel.mediaSource.id,
                positionTicks: currentProgressHandler.seconds * 10_000_000,
                sessionID: currentViewModel.playSessionID
            )

            let request = Paths.reportPlaybackStopped(stopInfo)
            let _ = try await userSession.client.send(request)
        }
    }

    func sendPauseReport() {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        logger.debug("sent pause report")

        currentProgressWorkItem?.cancel()

        Task {
            let startInfo = PlaybackStartInfo(
                audioStreamIndex: audioTrackIndex,
                isPaused: true,
                itemID: currentViewModel.item.id,
                mediaSourceID: currentViewModel.mediaSource.id,
                positionTicks: currentProgressHandler.seconds * 10_000_000,
                sessionID: currentViewModel.playSessionID,
                subtitleStreamIndex: subtitleTrackIndex
            )

            let request = Paths.reportPlaybackStart(startInfo)
            let _ = try await userSession.client.send(request)
        }
    }

    func sendProgressReport() {

        #if DEBUG
        guard Defaults[.sendProgressReports] else { return }
        #endif

        let progressTask = DispatchWorkItem {
            self.sendProgressReport()
        }

        currentProgressWorkItem = progressTask

        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: progressTask)

        Task {
            let progressInfo = PlaybackProgressInfo(
                audioStreamIndex: audioTrackIndex,
                isPaused: false,
                itemID: currentViewModel.item.id,
                mediaSourceID: currentViewModel.item.id, // Should this be currentViewModel.mediaSource.id?
                playSessionID: currentViewModel.playSessionID,
                positionTicks: currentProgressHandler.seconds * 10_000_000,
                sessionID: currentViewModel.playSessionID,
                subtitleStreamIndex: subtitleTrackIndex
            )

            let request = Paths.reportPlaybackProgress(progressInfo)
            let _ = try await userSession.client.send(request)

            logger.debug("sent progress task")
        }
    }

    func setupControlListeners() {
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.proxy.pause()

            return .success
        }

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.proxy.play()

            return .success
        }
    }
}
