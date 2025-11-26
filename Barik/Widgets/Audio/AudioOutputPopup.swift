import SwiftUI

struct AudioOutputPopup: View {
    @ObservedObject private var audioManager = AudioOutputManager.shared
    @State private var localVolume: Float = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Volume slider section
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: audioManager.isMuted ? "speaker.slash.fill" : volumeIcon)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20)
                        .onTapGesture {
                            audioManager.setMuted(!audioManager.isMuted)
                        }

                    Slider(value: $localVolume, in: 0...1) { editing in
                        if !editing {
                            audioManager.setVolume(localVolume)
                        }
                    }
                    .tint(.white)
                    .onChange(of: localVolume) { _, newValue in
                        audioManager.setVolume(newValue)
                    }

                    Text("\(Int(localVolume * 100))%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 4)

            Divider()
                .background(Color.white.opacity(0.2))

            // Output devices section
            VStack(alignment: .leading, spacing: 4) {
                Text("Output")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.horizontal, 4)

                ForEach(audioManager.outputDevices) { device in
                    DeviceRow(device: device, isSelected: device.isDefault) {
                        audioManager.setDefaultOutputDevice(device)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            localVolume = audioManager.volume
        }
        .onChange(of: audioManager.volume) { _, newValue in
            localVolume = newValue
        }
    }

    private var volumeIcon: String {
        if localVolume == 0 {
            return "speaker.fill"
        } else if localVolume < 0.33 {
            return "speaker.wave.1.fill"
        } else if localVolume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

private struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: device.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 20)

                Text(device.name)
                    .font(.system(size: 13))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.white.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AudioOutputPopup_Previews: PreviewProvider {
    static var previews: some View {
        AudioOutputPopup()
            .background(Color.black)
            .previewLayout(.sizeThatFits)
    }
}
