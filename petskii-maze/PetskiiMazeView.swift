//
//  PetskiiMazeView.swift
//  petskii-maze
//
//  Created by Vladimir Kosickij on 10.08.2026.
//

import AppKit
import CoreVideo
import Metal
import QuartzCore
import ScreenSaver

@objc(PetskiiMazeView)
final class PetskiiMazeView: ScreenSaverView {
    private var metalLayer: CAMetalLayer!
    private var renderer: Renderer!
    private var displayLink: CVDisplayLink?
    private var sizeDidChange = true

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        wantsLayer = true
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        self.layer = layer
        metalLayer = layer

        renderer = Renderer(device: device)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeBackingPropertiesNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sizeDidChange = true }
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizeDidChange = true
        // Only render directly here if the display link isn't driving frames
        // itself -- once it's running, calling into the renderer from the
        // main thread too would race with the display link's own thread.
        if displayLink == nil {
            updateDrawableSizeAndRenderOnce()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sizeDidChange = true
        if displayLink == nil {
            updateDrawableSizeAndRenderOnce()
        }
    }

    // Renders one frame immediately on resize/attach, rather than only ever
    // drawing from the CVDisplayLink loop. Some hosts (e.g. the small
    // Screen Saver list thumbnail) apparently never call startAnimation(),
    // which would otherwise leave the layer permanently black.
    private func updateDrawableSizeAndRenderOnce() {
        let scale = window?.screen?.backingScaleFactor ?? 2.0
        var size = bounds.size
        size.width *= scale
        size.height *= scale
        guard size.width > 0, size.height > 0 else { return }
        metalLayer.drawableSize = size
        sizeDidChange = false
        renderer.render(layer: metalLayer, scale: Float(scale))
    }

    // Deliberately not calling super.startAnimation()/stopAnimation() here.
    // ScreenSaverView's built-in NSTimer-driven animation loop stutters badly
    // with Metal; driving our own CVDisplayLink synced to the real screen
    // refresh is the standard fix (same approach used by working Metal
    // screensavers such as nickzman/rainingcubes).
    override func startAnimation() {
        guard displayLink == nil else { return }

        var link: CVDisplayLink?
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        let screenID =
            (window?.screen?.deviceDescription[screenNumberKey] as? NSNumber)?
            .uint32Value ?? CGMainDisplayID()
        CVDisplayLinkCreateWithCGDisplay(screenID, &link)
        guard let link else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(
            link,
            { _, _, _, _, _, ctx -> CVReturn in
                let view = Unmanaged<PetskiiMazeView>.fromOpaque(ctx!)
                    .takeUnretainedValue()
                view.tick()
                return kCVReturnSuccess
            }, context)

        displayLink = link
        sizeDidChange = true
        CVDisplayLinkStart(link)
    }

    override func stopAnimation() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    // Called on the CVDisplayLink's own high-priority thread, not the main thread.
    private func tick() {
        if sizeDidChange {
            DispatchQueue.main.sync { [weak self] in
                self?.updateDrawableSizeAndRenderOnce()
            }
        } else {
            let scale = Float(window?.screen?.backingScaleFactor ?? 2.0)
            renderer.render(layer: metalLayer, scale: scale)
        }
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
