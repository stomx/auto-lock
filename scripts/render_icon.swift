#!/usr/bin/env swift
// Renders Resources/icon.svg into the full macOS iconset and packs it as
// AppIcon.icns. Run from the repo root: ./scripts/render_icon.swift

import Foundation
import AppKit
import WebKit

let root = FileManager.default.currentDirectoryPath
let svgURL = URL(fileURLWithPath: "\(root)/Resources/icon.svg")
let outDir = URL(fileURLWithPath: "\(root)/Resources/AppIcon.iconset")
let icnsOut = URL(fileURLWithPath: "\(root)/Resources/AppIcon.icns")

guard FileManager.default.fileExists(atPath: svgURL.path) else {
    fputs("icon.svg not found at \(svgURL.path)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Required iconset filenames per Apple HIG.
let sizes: [(file: String, px: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// Render the SVG once at 1024 via WKWebView, then downsample with NSImage.
final class Renderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let onDone: (NSImage?) -> Void
    init(svg: String, onDone: @escaping (NSImage?) -> Void) {
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024))
        self.onDone = onDone
        super.init()
        webView.navigationDelegate = self
        let html = """
        <html><head><style>
        html,body{margin:0;padding:0;background:transparent;}
        svg{display:block;width:1024px;height:1024px;}
        </style></head><body>\(svg)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give WebKit a frame to lay out, then snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
            self.webView.takeSnapshot(with: cfg) { [self] image, _ in
                onDone(image)
            }
        }
    }
}

let svg = try String(contentsOf: svgURL)

let app = NSApplication.shared
let renderer = Renderer(svg: svg) { image in
    guard let image else {
        fputs("snapshot failed\n", stderr)
        exit(1)
    }

    for (file, px) in sizes {
        let target = NSImage(size: NSSize(width: px, height: px))
        target.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px),
                   from: .zero,
                   operation: .sourceOver,
                   fraction: 1.0)
        target.unlockFocus()
        guard
            let tiff = target.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            fputs("encode \(file) failed\n", stderr)
            exit(1)
        }
        try? png.write(to: outDir.appendingPathComponent(file))
        print("✓ \(file) (\(px)px)")
    }

    // Pack iconset → icns
    let task = Process()
    task.launchPath = "/usr/bin/iconutil"
    task.arguments = ["-c", "icns", outDir.path, "-o", icnsOut.path]
    do { try task.run() } catch { fputs("iconutil failed: \(error)\n", stderr); exit(1) }
    task.waitUntilExit()
    print("✅ \(icnsOut.lastPathComponent) written")
    exit(0)
}

// Keep `renderer` alive
withExtendedLifetime(renderer) {
    app.run()
}
