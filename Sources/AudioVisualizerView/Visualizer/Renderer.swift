//
//  Renderer.swift
//  FileProviderSample
//
//  Created by Raheel Ahmad on 6/17/23.
//

import Metal
import MetalKit
import Logging

struct Vertex {
    var position: vector_float2;
}

struct FragmentUniforms {
    var time: Float
    var screen_width: Float
    var screen_height: Float
    var screen_scale: Float
    var mouseLocation: vector_float2
}

struct VizUniforms {
    var binsCount: Float
    var buffersCount: Float
    var maxFrequency: Float
}

public struct RendererConfig {
    public init(
        maxFrequencyAmpitude: Float? = nil,
        liveReload: Bool,
        historicalBuffers: Int
    ) {
        self.maxFrequencyAmpitude = maxFrequencyAmpitude
        self.liveReload = liveReload
        self.historicalBuffers = historicalBuffers
    }
    
    public let maxFrequencyAmpitude: Float?
    public let liveReload: Bool
    public let historicalBuffers: Int

    public static let muziqi: RendererConfig = .init(
        maxFrequencyAmpitude: 20,
        liveReload: false,
        historicalBuffers: 4
    )

    public static let awaaz: RendererConfig = .init(
        maxFrequencyAmpitude: nil,
        liveReload: true,
        historicalBuffers: 8
    )
}

final class Device {
    init?(mtlDevice: MTLDevice, pixelFormat: MTLPixelFormat) {
        self.mtlDevice = mtlDevice
        do {
            self.lib = try mtlDevice.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            errorLog(error.localizedDescription)
            return nil
        }
        self.pixelFormat = pixelFormat
    }

    let mtlDevice: MTLDevice
    var lib: MTLLibrary
    let pixelFormat: MTLPixelFormat
}

final class Renderer: NSObject, MTKViewDelegate, VisualizerRenderInfoProvider {
    var binsCount: Int {
        viz.binsCount
    }

    var scalingMultiplier: Double {
        viz.scalingMultiplier
    }

    var mouseLocation: vector_float2 = .init(repeating: 0) {
        didSet {
            uniforms.mouseLocation = vector_float2(mouseLocation.x / uniforms.screen_width, 1 - mouseLocation.y / uniforms.screen_height)
        }
    }
    var basicVertices: [Vertex] {
        [
            Vertex(position: [-1, -1]),
            Vertex(position: [-1, 1]),
            Vertex(position: [1, 1]),

            Vertex(position: [-1, -1]),
            Vertex(position: [1, 1]),
            Vertex(position: [1, -1]),
        ]
    }

    var mtlDevice: MTLDevice { device.mtlDevice }
    let device: Device
    var pixelFormat: MTLPixelFormat?
    let queue: MTLCommandQueue
    private let compileQueue = DispatchQueue.init(label: "Shader compile queue")

    static var aspectRatio: Float = 1.0
    
    private let config: RendererConfig

    var pipelineState: MTLRenderPipelineState!
    weak var dataProcessor: VisualizerDataBuilder?

    private var uniforms: FragmentUniforms = .init(time: 0, screen_width: 0, screen_height: 0, screen_scale: 0, mouseLocation: .init(0,0))
    private var vizUniforms: VizUniforms = .init(
        binsCount: 100,
        buffersCount: 1,
        maxFrequency: 30
    )

    init?(failable: Bool = true, config: RendererConfig) {
        guard
            let mtlDevice = MTLCreateSystemDefaultDevice(),
            let queue = mtlDevice.makeCommandQueue(),
            let device = Device(mtlDevice: mtlDevice, pixelFormat: .bgra8Unorm)
        else {
            errorLog("No Device on this device!")
            return nil
        }

        self.device = device
        self.queue = queue
        self.config = config

        super.init()
    }

    func setup(_ view: MTKView, dataProcessor: VisualizerDataBuilder) {
        self.dataProcessor = dataProcessor
        view.device = mtlDevice
        view.colorPixelFormat = device.pixelFormat
        view.delegate = self
        uniforms.screen_scale = 2
        setupInitialBuffers()
        setupPipeline()
    }

    var lastRenderTime: CFTimeInterval? = nil
    var currentTime: Double = 0
    let gpuLock = DispatchSemaphore(value: 1)

    var vertexBuffer: MTLBuffer?
    var viz: Viz = .kishimisu {
        didSet { setupPipeline() }
    }

    private func setupInitialBuffers() {
        vertexBuffer = mtlDevice.makeBuffer(bytes: basicVertices, length: MemoryLayout<Vertex>.stride * basicVertices.count, options: [])
    }

    private func setupPipeline() {
        dataProcessor?.resetBuffers()
        self.pipelineState = viz.pipelineState(device: device)
    }
    
    private var liveReload: Bool { config.liveReload }
    var shaderContents = ""
    func compileScenePipeline() {
        guard liveReload else { return }
        let fm = FileManager()
        let filePath = #filePath as NSString
        let fileName = viz.fileName
        let shaderPath: String = filePath.deletingLastPathComponent.appending("/\(fileName).metal")
        let helpersPath = (filePath.deletingLastPathComponent) + "/Helpers.metal"
        let url = URL(string: shaderPath)
        url!.startAccessingSecurityScopedResource()

        guard
            let shaderContentsData = fm.contents(atPath: shaderPath),
            let helpersData = fm.contents(atPath: helpersPath),
            var shaderContents = String(data: shaderContentsData, encoding: .utf8),
            let helperContents = String(data: helpersData, encoding: .utf8)
        else {
            assertionFailure()
            return
        }
        var shaderContentLines = shaderContents.split(separator: "\n")
        if let headerIndex = shaderContentLines.firstIndex(where: { $0 == "#include \"ShaderHeaders.h\"" }) {
            shaderContentLines.remove(at: headerIndex)

            var headerLines = helperContents.split(separator: "\n")
            if let helperHeaderIndex = headerLines.firstIndex(where: { String($0) == "#include \"ShaderHeaders.h\"" }) {
                headerLines.remove(at: helperHeaderIndex)
            }
            shaderContentLines.insert(contentsOf: headerLines, at: headerIndex)
        }
        shaderContents = shaderContentLines.joined(separator: "\n")

        let oldValue = self.shaderContents
        self.shaderContents = shaderContents

        guard shaderContents != oldValue && !oldValue.isEmpty else {
            return
        }

        do {
            let library = try device.mtlDevice.makeLibrary(
                source: shaderContents,
                options: nil
            )
            device.lib = library
            let pipeline = viz.pipelineState(device: device)

            DispatchQueue.main.async {
                self.pipelineState = pipeline
            }
        } catch {
            print(error.localizedDescription)
        }

    }

    func draw(in view: MTKView) {
        guard dataProcessor?.hasBuffers == true else { return }
        guard let commandBuffer = queue.makeCommandBuffer() else { return }
        guard let passDescriptor = view.currentRenderPassDescriptor else { return }
        guard let pipelineState = self.pipelineState else { return }

        // update time
        let systemTime = CACurrentMediaTime()
        let timeDiff = lastRenderTime.map { systemTime - $0 } ?? 0
        currentTime += timeDiff
        lastRenderTime = systemTime

        uniforms.time = Float(currentTime)
        vizUniforms.binsCount = Float(viz.binsCount)
        let values = (dataProcessor?.allFrequenciesBuffers ?? [])
        vizUniforms.maxFrequency = values.flatMap { $0 }.max() ?? 0
        let buffersCount = dataProcessor?.allFrequenciesBuffers.count ?? 0
        vizUniforms.buffersCount = Float(buffersCount)

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        
        compileQueue.async {
            self.compileScenePipeline()
        }

        encoder.setRenderPipelineState(pipelineState)

        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        let uniformsBuffer = mtlDevice.makeBuffer(bytes: &uniforms, length: MemoryLayout<FragmentUniforms>.size, options: [])
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        let vizUniformsBuffer = mtlDevice.makeBuffer(bytes: &vizUniforms, length: MemoryLayout<VizUniforms>.size, options: [])
        encoder.setFragmentBuffer(vizUniformsBuffer, offset: 0, index: 3)

        setUniforms(encoder: encoder)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: basicVertices.count)

        encoder.endEncoding()
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }

    func setUniforms(encoder: MTLRenderCommandEncoder) {
        guard
            let loudnessBuffer = dataProcessor?.loudnessBuffer,
            let frequencyBuffer = dataProcessor?.freqeuencyBuffer
        else {
//            errorLog("No Data Processor set up")
            return
        }
        encoder.setFragmentBuffer(loudnessBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(frequencyBuffer, offset: 0, index: 2)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.screen_width = Float(size.width)
        uniforms.screen_height = Float(size.height)
        Self.aspectRatio = Float(uniforms.screen_width/uniforms.screen_height)
    }
}
