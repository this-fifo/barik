import EventKit
import SwiftUI

// MARK: - Button Style

/// A button style that scales down when pressed for tactile feedback
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct NowPlayingPopup: View {
    @ObservedObject var configProvider: ConfigProvider
    @State private var selectedVariant: MenuBarPopupVariant = .horizontal

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.nowplaying.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            vertical: { NowPlayingVerticalPopup() },
            horizontal: { NowPlayingHorizontalPopup() }
        )
        .onAppear(perform: loadVariant)
        .onReceive(configProvider.$config, perform: updateVariant)
    }
    
    /// Loads the initial view variant from configuration.
    private func loadVariant() {
        if let variantString = configProvider.config["popup"]?
            .dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        } else {
            selectedVariant = .box
        }
    }
    
    /// Updates the view variant when configuration changes.
    private func updateVariant(newConfig: ConfigData) {
        if let variantString = newConfig["popup"]?.dictionaryValue?["view-variant"]?.stringValue,
           let variant = MenuBarPopupVariant(rawValue: variantString) {
            selectedVariant = variant
        }
    }
}

/// A vertical layout for the now playing popup.
private struct NowPlayingVerticalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying,
           let duration = song.duration,
           let position = song.position {
            VStack(spacing: 15) {
                Group {
                    if let artworkData = song.albumArtData,
                       let nsImage = NSImage(data: artworkData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 200, height: 200)
                .id(song.title + song.artist)
                .scaleEffect(song.state == .paused ? 0.9 : 1)
                .overlay(
                    song.state == .paused ?
                    Color.black.opacity(0.3)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    : nil
                )
                .animation(.smooth(duration: 0.5, extraBounce: 0.4), value: song.state == .paused)

                VStack(alignment: .center) {
                    Text(song.title)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 15))
                        .fontWeight(.medium)
                    Text(song.artist)
                        .opacity(0.6)
                        .font(.system(size: 15))
                        .fontWeight(.light)
                }

                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)

                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geometry.size.width * (position / duration), height: 4)
                        }
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let clickedPosition = max(0, min(value.location.x / geometry.size.width, 1))
                                    let newPosition = clickedPosition * duration
                                    playingManager.seek(to: newPosition)
                                }
                        )
                    }
                    .frame(height: 4)

                    HStack {
                        Text(timeString(from: position))
                            .font(.caption)
                        Spacer()
                        Text("-" + timeString(from: duration - position))
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                    .monospacedDigit()
                }

                HStack(spacing: 40) {
                    Button(action: { playingManager.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)

                    Button(action: { playingManager.togglePlayPause() }) {
                        Image(systemName: song.state == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)

                    Button(action: { playingManager.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 30)
            .frame(width: 300)
            .animation(.easeInOut, value: song.id)
        }
    }
}

/// A horizontal layout for the now playing popup.
struct NowPlayingHorizontalPopup: View {
    @ObservedObject private var playingManager = NowPlayingManager.shared

    var body: some View {
        if let song = playingManager.nowPlaying,
           let duration = song.duration,
           let position = song.position {
            VStack(spacing: 15) {
                HStack(spacing: 15) {
                    Group {
                        if let artworkData = song.albumArtData,
                           let nsImage = NSImage(data: artworkData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .id(song.title + song.artist)
                    .scaleEffect(song.state == .paused ? 0.9 : 1)
                    .overlay(
                        song.state == .paused ?
                        Color.black.opacity(0.3)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        : nil
                    )
                    .animation(.smooth(duration: 0.5, extraBounce: 0.4), value: song.state == .paused)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(song.title)
                            .font(.headline)
                            .fontWeight(.medium)
                        Text(song.artist)
                            .opacity(0.6)
                            .font(.headline)
                            .fontWeight(.light)
                    }
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 4)

                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geometry.size.width * (position / duration), height: 4)
                        }
                        .clipShape(Capsule())
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let clickedPosition = max(0, min(value.location.x / geometry.size.width, 1))
                                    let newPosition = clickedPosition * duration
                                    playingManager.seek(to: newPosition)
                                }
                        )
                    }
                    .frame(height: 4)

                    HStack {
                        Text(timeString(from: position))
                            .font(.caption)
                        Spacer()
                        Text("-" + timeString(from: duration - position))
                            .font(.caption)
                    }
                    .foregroundColor(.gray)
                    .monospacedDigit()
                }

                HStack(spacing: 40) {
                    Button(action: { playingManager.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)

                    Button(action: { playingManager.togglePlayPause() }) {
                        Image(systemName: song.state == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)

                    Button(action: { playingManager.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .focusable(false)
                }
            }
            .padding(.horizontal, 25)
            .padding(.vertical, 20)
            .frame(width: 300, height: 180)
            .animation(.easeInOut, value: song.id)
        }
    }
}

/// Converts a time interval in seconds to a formatted string (minutes:seconds).
private func timeString(from seconds: Double) -> String {
    let intSeconds = Int(seconds)
    let minutes = intSeconds / 60
    let remainingSeconds = intSeconds % 60
    return String(format: "%d:%02d", minutes, remainingSeconds)
}

// MARK: - Previews

struct NowPlayingPopup_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NowPlayingVerticalPopup()
                .background(Color.black)
                .frame(height: 600)
                .previewDisplayName("Vertical")
            
            NowPlayingHorizontalPopup()
                .background(Color.black)
                .previewLayout(.sizeThatFits)
                .previewDisplayName("Horizontal")
        }
    }
}
