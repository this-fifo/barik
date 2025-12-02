// ABOUTME: Widget that toggles system sleep prevention
// ABOUTME: Click to toggle - prevents idle sleep while allowing display sleep

import SwiftUI

struct CaffeinateWidget: View {
    @ObservedObject private var manager = CaffeinateManager.shared

    var body: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 14))
            .foregroundStyle(.foregroundOutside)
            .opacity(manager.isActive ? 1.0 : 0.5)
            .shadow(color: .foregroundShadowOutside, radius: 3)
            .experimentalConfiguration(cornerRadius: 15)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.001))
            .onTapGesture {
                manager.toggle()
            }
            .animation(.easeInOut(duration: 0.15), value: manager.isActive)
    }
}

struct CaffeinateWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            CaffeinateWidget()
        }
        .frame(width: 100, height: 50)
        .background(.gray)
    }
}
