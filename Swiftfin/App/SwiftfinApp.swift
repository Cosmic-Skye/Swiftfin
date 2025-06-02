//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation // Reverted: AVFAudio did not resolve setPrefersSpatialAudio build issue
import CoreStore
import Defaults
import Factory
import Logging
import Nuke
import PreferencesView
import Pulse
import PulseLogHandler
import SwiftUI

@main
struct SwiftfinApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    @StateObject
    private var valueObservation = ValueObservation()

    init() {

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

        UIScrollView.appearance().keyboardDismissMode = .onDrag

        // Sometimes the tab bar won't appear properly on push, always have material background
        UITabBar.appearance().scrollEdgeAppearance = UITabBarAppearance(idiom: .unspecified)

        // Swiftfin

        // don't keep last user id
        if Defaults[.signOutOnClose] {
            Defaults[.lastSignedInUserID] = .signedOut
        }

        // AVAudioSession Configuration for iOS
        do {
            let audioSession = AVAudioSession.sharedInstance()
            print("[AudioSession] Attempting configuration...")

            do {
                print("[AudioSession] Setting category: .playback, mode: .moviePlayback (NO options first)")
                try audioSession.setCategory(.playback, mode: .moviePlayback)
                print("[AudioSession] Successfully set category and mode.")
                // .allowAirPlay option remains removed for now to avoid -50 error
            } catch {
                print("[AudioSession] FAILED during category/mode setting: \(error.localizedDescription)")
                throw error // Re-throw to be caught by the outer catch
            }

            if #available(iOS 15.0, tvOS 15.0, *) {
                do {
                    print("[AudioSession] Setting supportsMultichannelContent = true")
                    try audioSession.setSupportsMultichannelContent(true)
                    print("[AudioSession] Successfully set supportsMultichannelContent.")
                } catch {
                    print("[AudioSession] FAILED to set supportsMultichannelContent: \(error.localizedDescription)")
                    throw error // Re-throw
                }

                // do {
                //     print("[AudioSession] Setting prefersSpatialAudio = true")
                //     try audioSession.setPrefersSpatialAudio(true) // Re-commented due to persistent build error
                //     print("[AudioSession] Successfully set prefersSpatialAudio.")
                // } catch {
                //     print("[AudioSession] FAILED to set prefersSpatialAudio: \(error.localizedDescription)")
                //     throw error
                // }
            }

            do {
                print("[AudioSession] Activating session...")
                try audioSession.setActive(true)
                print("[AudioSession] Successfully activated session.")
            } catch {
                print("[AudioSession] FAILED to activate session: \(error.localizedDescription)")
                throw error // Re-throw
            }
            print("[AudioSession] Configuration complete and session active.")
        } catch {
            print("[AudioSession] OVERALL FAILURE in configuration: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("[AudioSession] Error Code: \(nsError.code), Domain: \(nsError.domain), UserInfo: \(nsError.userInfo)")
            }
        }
    }

    // TODO: removed after iOS 15 support removed

    @ViewBuilder
    private var versionedView: some View {
        if #available(iOS 16, *) {
            PreferencesView {
                MainCoordinator()
                    .view()
                    .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : .portrait)
            }
        } else {
            PreferencesView {
                PreferencesView {
                    MainCoordinator()
                        .view()
                        .supportedOrientations(UIDevice.isPad ? .allButUpsideDown : .portrait)
                }
                .ignoresSafeArea()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            versionedView
                .ignoresSafeArea()
                .onNotification(.applicationDidEnterBackground) {
                    Defaults[.backgroundTimeStamp] = Date.now
                }
                .onNotification(.applicationWillEnterForeground) {

                    // TODO: needs to check if any background playback is happening
                    //       - atow, background video playback isn't officially supported
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

extension UINavigationController {

    // Remove back button text
    override open func viewWillLayoutSubviews() {
        navigationBar.topItem?.backButtonDisplayMode = .minimal
    }
}
