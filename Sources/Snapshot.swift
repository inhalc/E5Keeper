import SwiftUI
import AppKit

enum Snapshot {
    @MainActor
    static func render(to path: String) {
        let view = SettingsView(scrollable: false)
            .frame(width: 580, height: 720)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("snapshot ok -> \(path)")
        } else {
            print("snapshot failed")
        }
        exit(0)
    }
}
