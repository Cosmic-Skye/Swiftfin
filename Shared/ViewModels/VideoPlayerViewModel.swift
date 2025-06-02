//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults
import Factory
import Files
import Foundation
import JellyfinAPI
import UIKit
import VLCUI

final class VideoPlayerViewModel: ViewModel {

    let playbackURL: URL
    let item: BaseItemDto
    let mediaSource: MediaSourceInfo
    let playSessionID: String
    let videoStreams: [MediaStream]
    let audioStreams: [MediaStream]
    let subtitleStreams: [MediaStream]
    let selectedAudioStreamIndex: Int
    let selectedSubtitleStreamIndex: Int
    let chapters: [ChapterInfo.FullInfo]
    let playMethod: PlayMethod

    var hlsPlaybackURL: URL {
        // Determine the desired audio codec to request based on the selected stream
        let targetAudioCodec: String?
        if let selectedStream = self.audioStreams.first(where: { $0.index == self.selectedAudioStreamIndex }) {
            if selectedStream.codec?.lowercased() == "eac3" {
                targetAudioCodec = "eac3"
                print("[VideoPlayerViewModel] Selected audio stream is E-AC3. Requesting 'eac3' codec.")
            } else {
                // For other codecs, let server decide or specify a general list if needed.
                // For now, nil to let server pick based on profile for non-EAC3.
                targetAudioCodec = nil
                print(
                    "[VideoPlayerViewModel] Selected audio stream is NOT E-AC3 (it's \(selectedStream.codec ?? "unknown")). Setting requested audioCodec to nil."
                )
            }
        } else {
            targetAudioCodec = nil // Should not happen if selectedAudioStreamIndex is valid
            print(
                "[VideoPlayerViewModel] Could not find selected audio stream by index \(self.selectedAudioStreamIndex). Setting requested audioCodec to nil."
            )
        }

        let parameters = Paths.GetMasterHlsVideoPlaylistParameters(
            isStatic: true, // As per original
            params: nil, // Not previously used, assuming nil is acceptable for optional String
            tag: mediaSource.eTag,
            deviceProfileID: nil, // Not previously used, let server infer or use `deviceID`
            playSessionID: playSessionID,
            segmentContainer: MediaContainer.mp4.rawValue, // As per original
            segmentLength: nil, // Let server decide
            minSegments: 2, // As per original
            mediaSourceID: mediaSource.id!,
            deviceID: UIDevice.vendorUUIDString, // As per original
            audioCodec: targetAudioCodec, // Use the determined target codec
            enableAutoStreamCopy: true, // Prefer copying if possible
            allowVideoStreamCopy: true, // Video codec (HEVC) should be fine to copy
            allowAudioStreamCopy: true, // E-AC3 should be fine to copy for HLS fMP4
            isBreakOnNonKeyFrames: true, // As per original
            audioSampleRate: nil, // Let server decide
            maxAudioBitDepth: nil, // Let server decide
            audioBitRate: nil, // Let server decide
            audioChannels: nil, // Let server decide
            maxAudioChannels: nil, // Let server/profile decide (was transcodingMaxAudioChannels before, mapping to maxAudioChannels)
            profile: nil, // Let server decide
            level: nil, // Let server decide
            framerate: nil, // Let server decide
            maxFramerate: nil, // Let server decide
            isCopyTimestamps: true, // As per original (mapped from copyTimestamps)
            // startTimeTicks expects Int?. If item.startTimeSeconds is 0, pass nil, otherwise convert ticks to Int.
            // The original complex condition for DVD/BluRay defaultSubtitleStreamIndex seems out of place for startTimeTicks.
            // Let's use item.startTimeSeconds directly.
            startTimeTicks: item.startTimeSeconds > 0 ? Int(item.startTimeSeconds * 10_000_000) : nil,
            width: nil, // Let server decide
            height: nil, // Let server decide
            maxWidth: nil, // Let server decide
            maxHeight: nil, // Let server decide
            videoBitRate: Defaults[.VideoPlayer.Playback.appMaximumBitrate].rawValue, // As per original
            subtitleStreamIndex: self.selectedSubtitleStreamIndex,
            subtitleMethod: .embed, // As per original
            maxRefFrames: nil, // Let server decide
            maxVideoBitDepth: nil, // Let server decide
            requireAvc: false, // As per original (assuming false is okay)
            isDeInterlace: false, // Default to false
            requireNonAnamorphic: false, // Default to false
            transcodingMaxAudioChannels: nil, // Let server/profile decide (use maxAudioChannels instead if that's the new param name)
            cpuCoreLimit: nil, // Let server decide
            liveStreamID: nil, // Not a live stream
            enableMpegtsM2TsMode: false, // Default to false for HLS fmp4
            videoCodec: nil, // Let server choose
            subtitleCodec: nil, // Let server choose or handle via sidecar
            transcodeReasons: nil, // Let server determine
            audioStreamIndex: self.selectedAudioStreamIndex, // <<< KEY PARAMETER
            videoStreamIndex: videoStreams.first?.index, // As per original
            context: .streaming, // Explicitly set context if available, else nil
            streamOptions: nil, // No specific stream options for now
            enableAdaptiveBitrateStreaming: true, // As per original
            enableTrickplay: false, // Default to false
            enableAudioVbrEncoding: false, // Default to false
            isAlwaysBurnInSubtitleWhenTranscoding: false // Default to false
        )
        let request = Paths.getMasterHlsVideoPlaylist(
            itemID: item.id!,
            parameters: parameters
        )

        // TODO: don't force unwrap
        let hlsStreamURL = userSession.client.fullURL(with: request)!

        // The api_key should ideally be added by the API client library via an interceptor or similar.
        // If it's not, adding it manually is a common workaround.
        var components = URLComponents(url: hlsStreamURL, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "api_key", value: userSession.user.accessToken)]

        let finalUrl = components.url!
        print("[VideoPlayerViewModel] Final hlsPlaybackURL (should include AudioStreamIndex via parameters): \(finalUrl.absoluteString)")
        return finalUrl
    }

    // TODO: should start time be from the media source instead?
    var vlcVideoPlayerConfiguration: VLCVideoPlayer.Configuration {
        let configuration = VLCVideoPlayer.Configuration(url: playbackURL)
        configuration.autoPlay = true
        configuration.startTime = .seconds(max(0, item.startTimeSeconds - Defaults[.VideoPlayer.resumeOffset]))
        if self.audioStreams[0].path != nil {
            configuration.audioIndex = .absolute(selectedAudioStreamIndex)
        }
        configuration.subtitleIndex = .absolute(selectedSubtitleStreamIndex)
        configuration.subtitleSize = .absolute(Defaults[.VideoPlayer.Subtitle.subtitleSize])
        configuration.subtitleColor = .absolute(Defaults[.VideoPlayer.Subtitle.subtitleColor].uiColor)

        if let font = UIFont(name: Defaults[.VideoPlayer.Subtitle.subtitleFontName], size: 0) {
            configuration.subtitleFont = .absolute(font)
        }

        configuration.playbackChildren = subtitleStreams
            .filter { $0.deliveryMethod == .external }
            .compactMap(\.asPlaybackChild)

        return configuration
    }

    init(
        playbackURL: URL,
        item: BaseItemDto,
        mediaSource: MediaSourceInfo,
        playSessionID: String,
        // TODO: Remove?
        videoStreams: [MediaStream],
        audioStreams: [MediaStream],
        subtitleStreams: [MediaStream],
        // <- End of Potential Remove?
        selectedAudioStreamIndex: Int,
        selectedSubtitleStreamIndex: Int,
        chapters: [ChapterInfo.FullInfo],
        playMethod: PlayMethod
    ) {
        self.item = item
        self.mediaSource = mediaSource
        self.playSessionID = playSessionID
        self.playbackURL = playbackURL

        guard let mediaStreams = mediaSource.mediaStreams else {
            fatalError("Media source does not have any streams")
        }

        let adjustedStreams = mediaStreams.adjustedTrackIndexes(for: playMethod, selectedAudioStreamIndex: selectedAudioStreamIndex)

        self.videoStreams = adjustedStreams.filter { $0.type == MediaStreamType.video }
        self.audioStreams = adjustedStreams.filter { $0.type == MediaStreamType.audio }
        self.subtitleStreams = adjustedStreams.filter { $0.type == MediaStreamType.subtitle }

        self.selectedAudioStreamIndex = selectedAudioStreamIndex
        self.selectedSubtitleStreamIndex = selectedSubtitleStreamIndex
        self.chapters = chapters
        self.playMethod = playMethod
        super.init()
    }

    func chapter(from seconds: Int) -> ChapterInfo.FullInfo? {
        chapters.first(where: { $0.secondsRange.contains(seconds) })
    }
}

extension VideoPlayerViewModel: Equatable {

    static func == (lhs: VideoPlayerViewModel, rhs: VideoPlayerViewModel) -> Bool {
        lhs.item == rhs.item &&
            lhs.playbackURL == rhs.playbackURL
    }
}
