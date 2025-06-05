//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2025 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI // For MediaStreamInfo
import SwiftUI

struct IOSAudioSelectionMenuView: View {
    @ObservedObject
    var videoPlayerManager: VideoPlayerManager
    @Binding
    var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { // Reduced spacing for popover
            Text("Audio Tracks") // Changed title slightly for popover context
                .font(.headline)
                .padding(.bottom, 5) // Add some padding below the title

            if videoPlayerManager.availableAudioStreams.isEmpty {
                Text("No audio tracks available.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { // Use LazyVStack for performance with many items
                        ForEach(videoPlayerManager.availableAudioStreams, id: \.index) { stream in
                            Button(action: {
                                videoPlayerManager.selectAudioStream(stream)
                                isPresented = false // This will dismiss the popover
                            }) {
                                HStack {
                                    Text(getDescriptiveStreamName(for: stream))
                                        .foregroundColor(videoPlayerManager.selectedAudioStream?.index == stream
                                            .index ? .accentColor : .primary
                                        )
                                    Spacer()
                                    if videoPlayerManager.selectedAudioStream?.index == stream.index {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(.vertical, 8) // Add some padding to each button row
                            }
                            Divider() // Add a divider between items
                        }
                    }
                }
                // maxHeight constraint removed, will be applied by the caller in popover
            }

            // "Done" button can be part of the VStack if needed, or rely on tap-outside-to-dismiss
            // For simplicity, relying on tap-outside or selection to dismiss.
            // If a Done button is essential:
            // Button("Done") { isPresented = false }
            //    .padding(.top)
        }
        .padding() // Add padding around the VStack content
        // .background(Color(.systemGray6)) // Optional: give popover a distinct background
        // .cornerRadius(10) // Optional: if background is added
    }

    private func getDescriptiveStreamName(for stream: JellyfinAPI.MediaStream) -> String { // Changed MediaStreamInfo to MediaStream
        var nameParts: [String] = []

        // MediaStream uses .title, not .displayTitle typically for the main descriptive name.
        // It might also have a .codec or .language.
        if let title = stream.title, !title.isEmpty, title.lowercased() != "unknown", title.lowercased() != "und" {
            nameParts.append(title)
        } else if let displayTitle = stream.displayTitle, !displayTitle.isEmpty, displayTitle.lowercased() != "unknown",
                  displayTitle.lowercased() != "und"
        {
            // Fallback to displayTitle if .title is not useful
            nameParts.append(displayTitle)
        }

        if let language = stream.language {
            let locale = Locale(identifier: Locale.current.identifier)
            if let localizedLanguage = locale.localizedString(forLanguageCode: language) {
                if nameParts.isEmpty || !nameParts.contains(where: { $0.caseInsensitiveCompare(localizedLanguage) == .orderedSame }) {
                    nameParts.append(localizedLanguage)
                }
            } else if !nameParts.contains(where: { $0.caseInsensitiveCompare(language) == .orderedSame }) {
                nameParts.append(language) // Fallback to language code if localization fails
            }
        }

        if let codec = stream.codec, !codec.isEmpty {
            if nameParts.isEmpty || !nameParts.contains(where: { $0.caseInsensitiveCompare(codec) == .orderedSame }) {
                // nameParts.append(codec.uppercased()) // Optionally add codec, might be too verbose
            }
        }

        if nameParts.isEmpty {
            // stream.index is Int32?, so handle optionality
            return "Track \((stream.index ?? -1) + 1)" // Use 1-based indexing for display
        }

        return nameParts.joined(separator: " - ")
    }
}
