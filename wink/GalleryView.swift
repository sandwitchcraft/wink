//
//  GalleryView.swift
//  wink
//

import SwiftUI

/// One page of the applet gallery: up to four icons in a 2 x 2 grid.
struct GalleryPage: View {
    let applets: [Applet]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.fixed(pt(104)), spacing: pt(24)), GridItem(.fixed(pt(104)))],
            spacing: pt(24)
        ) {
            ForEach(applets) { applet in
                AppletIcon(applet: applet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, WinkLayout.islandClearance)
        .padding(.bottom, WinkLayout.bottomInset)
    }
}

#Preview {
    WindowPreview {
        GalleryPage(applets: AppModel.galleryPages[0])
    }
}
