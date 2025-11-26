import SwiftUI

/// Widget for the menu, displaying Wi‑Fi and Ethernet icons.
struct NetworkWidget: View {
    @StateObject private var viewModel = NetworkStatusViewModel()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 10) {
            if viewModel.wifiState != .notSupported {
                wifiIcon
            }
            if viewModel.ethernetState != .notSupported {
                ethernetIcon
            }
        }
        .font(.system(size: 14))
        .contentShape(Rectangle())
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newValue in
                        rect = newValue
                    }
            }
        )
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "network") { NetworkPopup() }
        }
    }

    private var wifiIcon: some View {
        if viewModel.ssid == "Not connected" {
            return Image(systemName: "wifi.slash")
                .foregroundColor(.red)
                .offset(y: -1)
        }
        switch viewModel.wifiState {
        case .connected:
            return Image(systemName: "wifi")
                .foregroundColor(.foregroundOutside)
                .offset(y: -1)
        case .connecting:
            return Image(systemName: "wifi")
                .foregroundColor(.yellow)
                .offset(y: -1)
        case .connectedWithoutInternet:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.yellow)
                .offset(y: -1)
        case .disconnected:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
                .offset(y: -1)
        case .disabled:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.red)
                .offset(y: -1)
        case .notSupported:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.gray)
                .offset(y: -1)
        }
    }

    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            return Image(systemName: "network")
                .font(.system(size: 15))
                .foregroundColor(.primary)
        case .connectedWithoutInternet:
            return Image(systemName: "network")
                .font(.system(size: 15))
                .foregroundColor(.yellow)
        case .connecting:
            return Image(systemName: "network.slash")
                .font(.system(size: 15))
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "network.slash")
                .font(.system(size: 15))
                .foregroundColor(.red)
        case .disabled, .notSupported:
            return Image(systemName: "questionmark.circle")
                .font(.system(size: 15))
                .foregroundColor(.gray)
        }
    }
}

struct NetworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        NetworkWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
