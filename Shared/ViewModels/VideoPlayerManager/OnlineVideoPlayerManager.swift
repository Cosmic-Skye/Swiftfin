//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import Defaults // Added
import Factory // Added
import Foundation
import JellyfinAPI

final class OnlineVideoPlayerManager: VideoPlayerManager {

    init(item: BaseItemDto, mediaSource: MediaSourceInfo) {
        super.init()

        Task {
            do {
                // Step 1: Determine the desired initial audio stream index
                let allAudioStreams = item.mediaStreams?.filter { $0.type == .audio } ?? []
                var desiredInitialSelectedAudioStreamIndex: Int = -1

                if let eac3JocStream = allAudioStreams
                    .first(where: {
                        $0.codec?.lowercased() == "eac3" && ($0.profile?.lowercased().contains("dolby digital plus + dolby atmos") ?? false)
                    }),
                    let eac3Index = eac3JocStream.index
                {
                    desiredInitialSelectedAudioStreamIndex = eac3Index
                    logger.info("[OnlineVPM] Initial audio: Found E-AC3 JOC stream with index \(eac3Index).")
                } else if let defaultIdx = mediaSource.defaultAudioStreamIndex,
                          allAudioStreams.contains(where: { $0.index == defaultIdx })
                {
                    desiredInitialSelectedAudioStreamIndex = defaultIdx
                    logger.info("[OnlineVPM] Initial audio: Using mediaSource.defaultAudioStreamIndex \(defaultIdx).")
                } else if let firstAudio = allAudioStreams.first, let firstIndex = firstAudio.index {
                    desiredInitialSelectedAudioStreamIndex = firstIndex
                    logger.info("[OnlineVPM] Initial audio: Defaulting to first available audio stream with index \(firstIndex).")
                } else {
                    logger.warning("[OnlineVPM] Initial audio: No suitable audio stream found, defaulting to index -1.")
                }

                // Step 2: Replicate logic from BaseItemDto.videoPlayerViewModel to get PlaybackInfo
                let userSession = Container.shared
                    .currentUserSession()! // Corrected - Assuming Container is globally available via Factory import
                let currentVideoPlayerType = Defaults[.VideoPlayer.videoPlayerType] // Corrected
                let currentVideoBitrate = Defaults[.VideoPlayer.Playback.appMaximumBitrate] // Corrected
                let compatibilityMode = Defaults[.VideoPlayer.Playback.compatibilityMode] // Corrected

                // Replicate BaseItemDto.getMaxBitrate
                let maxBitrateSetting = Defaults[.VideoPlayer.Playback.appMaximumBitrateTest] // Corrected
                let maxBitrate = (currentVideoBitrate == .auto) ?
                    try await Self.testBitrate(with: maxBitrateSetting.rawValue, userSession: userSession) :
                    currentVideoBitrate.rawValue
                let cappedMaxBitrate = min(maxBitrate, PlaybackBitrate.max.rawValue)

                let profile = DeviceProfile.build(
                    for: currentVideoPlayerType,
                    compatibilityMode: compatibilityMode,
                    maxBitrate: cappedMaxBitrate
                )

                let playbackInfoDto = PlaybackInfoDto(deviceProfile: profile)
                let playbackInfoParameters = Paths.GetPostedPlaybackInfoParameters(
                    userID: userSession.user.id,
                    maxStreamingBitrate: cappedMaxBitrate,
                    mediaSourceID: mediaSource.id // Use the initial mediaSource's ID here
                )
                let playbackInfoRequest = Paths.getPostedPlaybackInfo(
                    itemID: item.id!,
                    parameters: playbackInfoParameters,
                    playbackInfoDto
                )
                let playbackInfoResponse = try await userSession.client.send(playbackInfoRequest)

                guard let playSessionID = playbackInfoResponse.value.playSessionID else {
                    throw JellyfinAPIError("PlaySessionID missing from playback info response")
                }

                // Use the mediaSource from the playbackInfoResponse, as it might have updated transcoding URLs etc.
                // The original BaseItemDto extension used a guard like this:
                guard let finalMediaSource = playbackInfoResponse.value.mediaSources?.first(where: { $0.id == mediaSource.id }) else {
                    // Attempt to find by eTag as a fallback, or just use the first if only one.
                    // This logic can be refined, but for now, ensure we get *a* mediaSource.
                    if let firstSource = playbackInfoResponse.value.mediaSources?.first {
                        logger
                            .warning(
                                "[OnlineVPM] Could not find media source by ID (\(mediaSource.id ?? "N/A")). Using first available from playback info."
                            )
                        // finalMediaSource = firstSource // This line would cause a compile error due to guard scope.
                        // We need to declare finalMediaSource outside or handle this differently.
                        // For now, let's stick to the stricter matching or throw.
                        throw JellyfinAPIError(
                            "Matching media source (ID: \(mediaSource.id ?? "N/A")) not found in playback info response. Response had: \(playbackInfoResponse.value.mediaSources?.map { $0.id ?? "nil" }.joined(separator: ", ") ?? "no sources")"
                        )
                    } else {
                        throw JellyfinAPIError("No media sources found in playback info response.")
                    }
                }
                // logger.info("[OnlineVPM] Using media source from playback info: ID \(finalMediaSource.id ?? "N/A"), ETag:
                // \(finalMediaSource.eTag ?? "N/A")")

                // Step 3: Determine playbackURL and playMethod (from MediaSourceInfo.videoPlayerViewModel)
                let determinedPlaybackURL: URL
                let determinedPlayMethod: PlayMethod

                if let transcodingURL = finalMediaSource.transcodingURL {
                    guard let fullTranscodeURL = userSession.client.fullURL(with: transcodingURL) else {
                        throw JellyfinAPIError("Unable to make transcode URL")
                    }
                    determinedPlaybackURL = fullTranscodeURL
                    determinedPlayMethod = .transcode
                } else {
                    let videoStreamParameters = Paths.GetVideoStreamParameters(
                        isStatic: true,
                        tag: item.etag,
                        playSessionID: playSessionID,
                        mediaSourceID: finalMediaSource.id
                    )
                    let videoStreamRequest = Paths.getVideoStream(
                        itemID: item.id!,
                        parameters: videoStreamParameters
                    )
                    guard let streamURL = userSession.client.fullURL(with: videoStreamRequest) else {
                        throw JellyfinAPIError("Unable to make stream URL")
                    }
                    determinedPlaybackURL = streamURL
                    determinedPlayMethod = .directPlay
                }

                // Step 4: Create VideoPlayerViewModel directly
                let viewModel = VideoPlayerViewModel(
                    playbackURL: determinedPlaybackURL,
                    item: item,
                    mediaSource: finalMediaSource,
                    playSessionID: playSessionID,
                    videoStreams: finalMediaSource.mediaStreams?.filter { $0.type == .video } ?? [],
                    audioStreams: finalMediaSource.mediaStreams?.filter { $0.type == .audio } ?? [],
                    subtitleStreams: finalMediaSource.mediaStreams?.filter { $0.type == .subtitle } ?? [],
                    selectedAudioStreamIndex: desiredInitialSelectedAudioStreamIndex,
                    selectedSubtitleStreamIndex: finalMediaSource.defaultSubtitleStreamIndex ?? -1,
                    chapters: item.fullChapterInfo,
                    playMethod: determinedPlayMethod
                )

                await MainActor.run {
                    self.currentViewModel = viewModel
                }

            } catch {
                // Handle error appropriately, e.g., update UI to show an error state
                logger.error("[OnlineVPM] Error creating VideoPlayerViewModel: \(error.localizedDescription)")
                // Optionally, set currentViewModel to nil or an error-state VM
                await MainActor.run {
                    self.currentViewModel = nil // Or some error state
                }
            }
        }
    }

    // Replicated from BaseItemDto extension for getMaxBitrate -> testBitrate
    private static func testBitrate(with testSize: Int, userSession: UserSession) async throws -> Int {
        precondition(testSize > 0, "testSize must be greater than zero")
        let testStartTime = Date()
        _ = try await userSession.client.send(Paths.getBitrateTestBytes(size: testSize))
        let testDuration = Date().timeIntervalSince(testStartTime)
        let testSizeBits = Double(testSize * 8)
        let testBitrate = testSizeBits / testDuration
        return min(Int(testBitrate), PlaybackBitrate.max.rawValue)
    }
}
