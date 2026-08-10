//
//  Renderer.swift
//  petskii-maze
//
//  Created by Vladimir Kosickij on 10.08.2026.
//

import Metal
import QuartzCore
import AppKit

final class Renderer {
    private static let glyphSize = 8
    private static let sizeScale: Float = 3
    private static let charsPerSecond: Double = 120
    private static let maxBuffersInFlight = 3
    private static let empty: UInt8 = 2

    // Same struct as in Shaders.metal
    private struct Uniforms {
        var viewportSize: SIMD2<Float>
        var origin: SIMD2<Float>
        var cellSize: Float
        var cols: UInt32
    }

    private let slashBits: [UInt8] = [
        0, 0, 0, 0, 0, 0, 1, 1,
        0, 0, 0, 0, 0, 1, 1, 1,
        0, 0, 0, 0, 1, 1, 1, 0,
        0, 0, 0, 1, 1, 1, 0, 0,
        0, 0, 1, 1, 1, 0, 0, 0,
        0, 1, 1, 1, 0, 0, 0, 0,
        1, 1, 1, 0, 0, 0, 0, 0,
        1, 1, 0, 0, 0, 0, 0, 0,
    ]

    private lazy var backBits: [UInt8] = {
        var b = [UInt8](repeating: 0, count: 64)
        for r in 0..<8 {
            for k in 0..<8 {
                b[r * 8 + k] = slashBits[r * 8 + (7 - k)]
            }
        }
        return b
    }()

    private static let fgBytes: [UInt8] = [0x6C, 0x5E, 0xB5, 0xFF]
    private static let bgBytes: [UInt8] = [0x35, 0x28, 0x79, 0xFF]
    private let clearColor = MTLClearColor(
        red: Double(bgBytes[0]) / 255,
        green: Double(bgBytes[1]) / 255,
        blue: Double(bgBytes[2]) / 255,
        alpha: 1
    )

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var samplerState: MTLSamplerState!
    private var atlasTexture: MTLTexture!

    private var px = 1
    private var cellSize = 8
    private var cols = 0
    private var rows = 0
    private var ox: Float = 0
    private var oy: Float = 0
    private var cx = 0
    private var grid: [UInt8] = []
    private var reducedMotion = false

    private var lastTime: CFTimeInterval = 0
    private var carry: Double = 0
    private var lastDrawableSize: CGSize = .zero

    private var gridBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let semaphore = DispatchSemaphore(
        value: Renderer.maxBuffersInFlight
    )

    init(device: MTLDevice) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Metal is not available")
        }
        self.commandQueue = queue

        buildPipeline()
        buildSampler()
    }

    private func buildPipeline() {
        // NOT device.makeDefaultLibrary() -- that loads the host process's
        // bundle (System Settings / legacyScreenSaver), not this .saver.
        guard
            let library = try? device.makeDefaultLibrary(
                bundle: Bundle(for: Renderer.self)
            )
        else {
            fatalError("Could not load Shaders.metallib from this bundle")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexShader")
        desc.fragmentFunction = library.makeFunction(name: "fragmentShader")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
    }

    private func buildSampler() {
        let desc = MTLSamplerDescriptor()
        desc.minFilter = .nearest
        desc.magFilter = .nearest
        desc.sAddressMode = .clampToEdge
        desc.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: desc)
    }

    private func buildAtlas() {
        let size = cellSize
        let width = size * 3  // We have 3 tiles
        let height = size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)  // RGBA

        func paintCell(sliceX: Int, row: Int, col: Int, color: [UInt8]) {
            let originX = sliceX * size + col * px
            let originY = row * px

            for yy in 0..<px {
                let rowStart = ((originY + yy) * width + originX) * 4
                for xx in 0..<px {
                    let o = rowStart + xx * 4
                    pixels[o] = color[0]
                    pixels[o + 1] = color[1]
                    pixels[o + 2] = color[2]
                    pixels[o + 3] = color[3]
                }
            }
        }

        for r in 0..<Self.glyphSize {
            for c in 0..<Self.glyphSize {
                paintCell(
                    sliceX: 0, row: r, col: c,
                    color: slashBits[r * 8 + c] == 1
                        ? Self.fgBytes : Self.bgBytes
                )
                paintCell(
                    sliceX: 1, row: r, col: c,
                    color: backBits[r * 8 + c] == 1
                        ? Self.fgBytes : Self.bgBytes
                )
                paintCell(sliceX: 2, row: r, col: c, color: Self.bgBytes)
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: desc)!
        pixels.withUnsafeBytes { raw in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: raw.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        atlasTexture = texture
    }

    private func rebuildIfNeeded(size: CGSize, scale: Float) {
        guard size.width > 0, size.height > 0, size != lastDrawableSize else {
            return
        }
        lastDrawableSize = size

        px = max(1, Int((Self.sizeScale * scale).rounded()))
        cellSize = px * Self.glyphSize

        let w = Float(size.width)
        let h = Float(size.height)
        cols = max(1, Int(w / Float(cellSize)))
        rows = max(1, Int(h / Float(cellSize)))
        ox = ((w - Float(cols * cellSize)) / 2).rounded(.down)
        oy = ((h - Float(rows * cellSize)) / 2).rounded(.down)

        buildAtlas()

        let byteCount = rows * cols
        gridBuffers = (0..<Self.maxBuffersInFlight).map { _ in
            device.makeBuffer(length: byteCount, options: .storageModeShared)!
        }

        reducedMotion =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        grid = [UInt8](repeating: Self.empty, count: byteCount)
        for r in 0..<rows where reducedMotion || r < rows - 1 {
            for c in 0..<cols { grid[r * cols + c] = UInt8.random(in: 0...1) }
        }
        cx = 0
        lastTime = 0
        carry = 0
    }

    private func step() {
        grid[(rows - 1) * cols + cx] = UInt8.random(in: 0...1)
        cx += 1
        if cx >= cols {
            grid.removeFirst(cols)
            grid.append(
                contentsOf: [UInt8](repeating: Self.empty, count: cols))
            cx = 0
        }
    }

    // Called from PetskiiMazeView's CVDisplayLink callback thread, not the main thread.
    func render(layer: CAMetalLayer, scale: Float) {
        rebuildIfNeeded(size: layer.drawableSize, scale: scale)
        guard cols > 0, rows > 0, !gridBuffers.isEmpty else { return }

        let now = CACurrentMediaTime()
        if lastTime == 0 { lastTime = now }
        let dt = now - lastTime
        lastTime = now

        if !reducedMotion {
            carry += dt * Self.charsPerSecond
            var owed = Int(carry)
            carry -= Double(owed)
            owed = min(owed, cols * 3)
            for _ in 0..<owed { step() }
        }

        semaphore.wait()
        let bufferIndex = frameIndex
        frameIndex = (frameIndex + 1) % Self.maxBuffersInFlight
        let gpuBuffer = gridBuffers[bufferIndex]
        grid.withUnsafeBytes { raw in
            _ = memcpy(gpuBuffer.contents(), raw.baseAddress!, grid.count)
        }

        guard let drawable = layer.nextDrawable() else {
            semaphore.signal()
            return
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = drawable.texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor = clearColor

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: rpd
            )
        else {
            semaphore.signal()
            return
        }
        let semaphore = self.semaphore
        commandBuffer.addCompletedHandler { _ in
            semaphore.signal()
        }

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(
                Float(layer.drawableSize.width),
                Float(layer.drawableSize.height)
            ),
            origin: SIMD2<Float>(ox, oy),
            cellSize: Float(cellSize),
            cols: UInt32(cols)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(
            &uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setVertexBuffer(gpuBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(atlasTexture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: 4,
            instanceCount: rows * cols
        )
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
