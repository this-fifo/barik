import SwiftUI

struct AudioOutputWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject private var audioManager = AudioOutputManager.shared

    @State private var rect: CGRect = CGRect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: currentIcon)
                .font(.system(size: 14))
                .foregroundStyle(.foregroundOutside)
        }
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        rect = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { oldState, newState in
                        rect = newState
                    }
            }
        )
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "audiooutput") {
                AudioOutputPopup()
            }
        }
    }

    private var currentIcon: String {
        if audioManager.isMuted {
            return "speaker.slash.fill"
        }

        guard let device = audioManager.currentDevice else {
            return "speaker.wave.2"
        }

        return device.icon
    }
}

struct AudioOutputWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            AudioOutputWidget()
        }
        .frame(width: 200, height: 100)
        .background(.yellow)
        .environmentObject(ConfigProvider(config: [:]))
    }
}
