//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation // For AVMediaSelectionOption, AVMediaSelectionGroup
import Combine // For PassthroughSubject
import Foundation
import JellyfinAPI

// TODO: the video player needs to be slightly refactored anyways, so I'm fine
//       with the channel retrieving method below and is mainly just for reference
//       for how I should probably handle getting the channels of programs elsewhere.

final class LiveVideoPlayerManager: VideoPlayerManager {

    @Published
    var program: ChannelProgram?

    // Note: AVPlayer audio/quality selection properties and methods are now in the base VideoPlayerManager.
    // LiveVideoPlayerManager can still override or extend them if tvOS-specific behavior is needed
    // beyond what the base class provides for AVPlayer.

    // Initializers remain to handle specific setup for live video if necessary,
    // but they no longer need to call setupQualityLevels() as the base init() does it.

    init(item: BaseItemDto, mediaSource: MediaSourceInfo, program: ChannelProgram? = nil) {
        self.program = program
        super.init() // Calls base init which now includes setupQualityLevels()

        Task {
            let viewModel = try await item.liveVideoPlayerViewModel(with: mediaSource, logger: logger)

            await MainActor.run {
                self.currentViewModel = viewModel
            }
        }
    }

    init(program: BaseItemDto) { // Changed from convenience to designated if no other designated init
        // If this class has no other designated initializers, this becomes one.
        // Or, ensure it calls a designated initializer of this class if one exists.
        // For now, assuming it can call super.init() directly after setting its own properties.
        super.init()
        Task {
            guard let channel = try? await self.getChannel(for: program), let mediaSource = channel.mediaSources?.first else {
                assertionFailure("No channel for program?")
                return
            }

            let viewModel = try await program.liveVideoPlayerViewModel(with: mediaSource, logger: logger)

            await MainActor.run {
                self.currentViewModel = viewModel
            }
        }
    }

    private func getChannel(for program: BaseItemDto) async throws -> BaseItemDto? {

        var parameters = Paths.GetItemsByUserIDParameters()
        parameters.fields = .MinimumFields
        parameters.ids = [program.channelID ?? ""]

        let request = Paths.getItemsByUserID(
            userID: userSession.user.id,
            parameters: parameters
        )
        let response = try await userSession.client.send(request)

        return response.value.items?.first
    }

    // MARK: - Public Methods for Audio Track Management are now in base class

    // MARK: - Public Methods for Video Quality Management are now in base class
}
