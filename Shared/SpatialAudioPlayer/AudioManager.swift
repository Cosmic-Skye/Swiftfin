//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Factory
import Logging
import MediaPlayer

class AudioManager {

    @Injected(\.logService)
    private var logger

    private let audioSession = AVAudioSession.sharedInstance()

    init() {
        setupAudioSession()
        setupRemoteCommandCenter()
    }

    private func setupAudioSession() {
        do {
            var options: AVAudioSession.CategoryOptions = [
                .allowAirPlay,
                .allowBluetooth,
                .allowBluetoothA2DP,
            ]

            #if os(iOS)
            options.insert(.defaultToSpeaker)
            #endif

            try audioSession.setCategory(
                .playback,
                mode: .moviePlayback,
                options: options
            )

            try audioSession.setActive(true)

        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    func configureSpatialAudio() {
        guard #available(iOS 14.0, tvOS 14.0, *) else {
            logger.debug("Spatial audio not available on this OS version")
            return
        }

        do {
            if audioSession.availableCategories.contains(.playback) {
                var options: AVAudioSession.CategoryOptions = [
                    .allowAirPlay,
                    .allowBluetooth,
                    .allowBluetoothA2DP,
                ]

                #if os(iOS)
                options.insert(.defaultToSpeaker)
                #endif

                #if os(tvOS)
                // tvOS-specific audio optimizations
                if #available(tvOS 15.0, *) {
                    options.insert(.interruptSpokenAudioAndMixWithOthers)
                }
                #endif

                try audioSession.setCategory(
                    .playback,
                    mode: .moviePlayback,
                    options: options
                )

                // Enhanced multichannel support for newer OS versions
                if #available(iOS 15.0, tvOS 15.0, *) {
                    if audioSession.supportsMultichannelContent {
                        try audioSession.setSupportsMultichannelContent(true)
                        logger.info("Multichannel audio support enabled")

                        #if os(tvOS)
                        // tvOS-specific: Prioritize spatial audio for home theater setups
                        configureTVOSSpatialAudio()
                        #endif
                    }
                } else if #available(iOS 14.5, tvOS 14.5, *) {
                    // Fallback for older versions that still support multichannel
                    if audioSession.supportsMultichannelContent {
                        try audioSession.setSupportsMultichannelContent(true)
                        logger.info("Multichannel audio support enabled (legacy)")
                    }
                }

                try audioSession.setActive(true)

                logAudioCapabilities()
            }
        } catch {
            logger.error("Spatial audio configuration failed: \(error.localizedDescription)")
        }
    }

    #if os(tvOS)
    @available(tvOS 15.0, *)
    private func configureTVOSSpatialAudio() {
        // tvOS-specific spatial audio optimizations
        logger.debug("Configuring tvOS spatial audio optimizations")

        // Check for HomePod or Apple TV audio output
        for output in audioSession.currentRoute.outputs {
            if output.portType == .airPlay {
                logger.info("AirPlay output detected - optimizing for spatial audio")
                break
            } else if output.portType == .HDMI {
                logger.info("HDMI output detected - configuring for surround sound")
                break
            }
        }
    }
    #endif

    private func logAudioCapabilities() {
        logger.debug("=== Audio Capabilities ===")
        logger.debug("Current route: \(audioSession.currentRoute)")
        logger.debug("Output volume: \(audioSession.outputVolume)")
        logger.debug("Output data sources: \(audioSession.outputDataSources?.count ?? 0)")

        if #available(iOS 14.5, tvOS 14.5, *) {
            logger.debug("Supports multichannel content: \(audioSession.supportsMultichannelContent)")
        }

        for output in audioSession.currentRoute.outputs {
            logger.debug("Output: \(output.portName) - Type: \(output.portType.rawValue)")
            logger.debug("  Channels: \(output.channels?.count ?? 0)")

            if let channels = output.channels {
                for (index, channel) in channels.enumerated() {
                    logger.trace("    Channel \(index): \(channel.channelName) - \(channel.channelLabel)")
                }
            }

            if let dataSources = output.dataSources {
                for dataSource in dataSources {
                    logger.debug("  Data source: \(dataSource.dataSourceName)")
                    if #available(iOS 14.0, tvOS 14.0, *) {
                        logger.debug("    Supports spatial audio: \(dataSource.supportedPolarPatterns?.contains(.stereo) ?? false)")
                    }
                }
            }
        }

        if #available(iOS 15.0, tvOS 15.0, *) {
            logger.info("Spatial audio enabled: \(isSpatialAudioEnabled())")
        }
    }

    @available(iOS 15.0, tvOS 15.0, *)
    private func isSpatialAudioEnabled() -> Bool {
        for output in audioSession.currentRoute.outputs {
            switch output.portType {
            case .bluetoothA2DP, .airPlay:
                if let dataSources = output.dataSources,
                   let selectedDataSource = output.selectedDataSource
                {
                    return dataSources.contains(selectedDataSource)
                }
            #if os(tvOS)
            case .HDMI:
                // For tvOS, check if HDMI supports multichannel (5.1 or higher)
                let channelCount = output.channels?.count ?? 0
                // 6 channels = 5.1, 8 channels = 7.1, etc.
                return channelCount >= 6
            #endif
            default:
                break
            }
        }
        return false
    }

    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlePlayCommand()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlePauseCommand()
            return .success
        }

        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                self?.handleSkipForward(interval: skipEvent.interval)
            }
            return .success
        }

        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            if let skipEvent = event as? MPSkipIntervalCommandEvent {
                self?.handleSkipBackward(interval: skipEvent.interval)
            }
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 10)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 10)]
    }

    private func handlePlayCommand() {
        NotificationCenter.default.post(name: .audioManagerPlayCommand, object: nil)
    }

    private func handlePauseCommand() {
        NotificationCenter.default.post(name: .audioManagerPauseCommand, object: nil)
    }

    private func handleSkipForward(interval: TimeInterval) {
        NotificationCenter.default.post(name: .audioManagerSkipForward, object: nil, userInfo: ["interval": interval])
    }

    private func handleSkipBackward(interval: TimeInterval) {
        NotificationCenter.default.post(name: .audioManagerSkipBackward, object: nil, userInfo: ["interval": interval])
    }

    func updateNowPlayingInfo(title: String, duration: TimeInterval, currentTime: TimeInterval) {
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func handleRouteChange() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.audioRouteChanged(notification: notification)
        }
        #elseif os(tvOS)
        // tvOS handles route changes differently - monitor for HDMI/AirPlay changes
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.tvOSAudioRouteChanged(notification: notification)
        }
        #endif
    }

    #if os(tvOS)
    private func tvOSAudioRouteChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        logger.debug("tvOS audio route changed: \(reason)")

        switch reason {
        case .newDeviceAvailable:
            logger.info("New audio device available on tvOS")
            // Check if it's a spatial audio capable device
            configureSpatialAudio()
        case .oldDeviceUnavailable:
            logger.info("Audio device disconnected on tvOS")
        case .categoryChange:
            logger.info("Audio category changed on tvOS")
            configureSpatialAudio()
        default:
            break
        }
    }
    #endif

    private func audioRouteChanged(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else {
            return
        }

        logger.debug("Audio route changed: \(reason)")

        switch reason {
        case .newDeviceAvailable:
            logger.info("New audio device available")
            configureSpatialAudio()
        case .oldDeviceUnavailable:
            logger.info("Audio device disconnected")
        case .categoryChange:
            logger.info("Audio category changed")
            configureSpatialAudio()
        default:
            break
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension Notification.Name {
    static let audioManagerPlayCommand = Notification.Name("audioManagerPlayCommand")
    static let audioManagerPauseCommand = Notification.Name("audioManagerPauseCommand")
    static let audioManagerSkipForward = Notification.Name("audioManagerSkipForward")
    static let audioManagerSkipBackward = Notification.Name("audioManagerSkipBackward")
}
