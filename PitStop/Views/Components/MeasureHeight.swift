import SwiftUI

extension View {
    /// Reports this view's height whenever it changes (used to keep the map camera clear of overlays).
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { geo in
            Color.clear
                .onAppear { onChange(geo.size.height) }
                .onChange(of: geo.size.height) { _, height in onChange(height) }
        })
    }
}
