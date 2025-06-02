//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation // Added for AVAudioSession
import CoreStore
import Defaults
import Factory
import Logging
import Nuke
import Pulse
import PulseLogHandler
import SwiftUI

@main
struct SwiftfinApp: App {

    init() {

        // AVAudioSession Configuration
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Configure for playback, allow AirPlay. .moviePlayback is a common mode.
            // .spatialAudio mode could be used if the content is consistently spatial.
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])

            if #available(tvOS 15.0, *) {
                try audioSession.setSupportsMultichannelContent(true)
                try audioSession.setPrefersSpatialAudio(true)
            }

            try audioSession.setActive(true)
            // Consider adding logging here if a logger is accessible
            // For example: logger.info("AVAudioSession configured for optimal playback.")
        } catch {
            // Handle errors appropriately, e.g., log them
            print("Failed to configure AVAudioSession: \(error.localizedDescription)")
        }

        // CoreStore

        CoreStoreDefaults.dataStack = SwiftfinStore.dataStack
        CoreStoreDefaults.logger = SwiftfinCorestoreLogger()

        // Logging
        LoggingSystem.bootstrap { label in

            var loggers: [LogHandler] = [PersistentLogHandler(label: label).withLogLevel(.trace)]

            #if DEBUG
            loggers.append(SwiftfinConsoleLogger())
            #endif

            return MultiplexLogHandler(loggers)
        }

        // Nuke

        ImageCache.shared.costLimit = 1024 * 1024 * 200 // 200 MB
        ImageCache.shared.ttl = 300 // 5 min

        ImageDecoderRegistry.shared.register { context in
            guard let mimeType = context.urlResponse?.mimeType else { return nil }
            return mimeType.contains("svg") ? ImageDecoders.Empty() : nil
        }

        ImagePipeline.shared = .Swiftfin.posters

        // UIKit

        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.label]

        // don't keep last user id
        if Defaults[.signOutOnClose] {
            Defaults[.lastSignedInUserID] = .signedOut
        }
    }

    var body: some Scene {
        WindowGroup {
            MainCoordinator()
                .view()
                .onNotification(.applicationDidEnterBackground) {
                    Defaults[.backgroundTimeStamp] = Date.now
                }
                .onNotification(.applicationWillEnterForeground) {
                    // TODO: needs to check if any background playback is happening
                    let backgroundedInterval = Date.now.timeIntervalSince(Defaults[.backgroundTimeStamp])

                    if Defaults[.signOutOnBackground], backgroundedInterval > Defaults[.backgroundSignOutInterval] {
                        Defaults[.lastSignedInUserID] = .signedOut
                        Container.shared.currentUserSession.reset()
                        Notifications[.didSignOut].post()
                    }
                }
        }
    }
}
