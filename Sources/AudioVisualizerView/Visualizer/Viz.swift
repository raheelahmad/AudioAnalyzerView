import MetalKit

enum Viz: String, CaseIterable, Identifiable {
    case radialFunk
    case kishimisu
    case bars
    case spectrum

    var id: String { rawValue }

    static var locked: [Viz] {
        [.radialFunk]
    }
    
    var fileName: String {
        switch self {
        case .radialFunk:
            "RadialViz"
        case .kishimisu:
            "Kishimisu"
        case .bars:
            "BarsViz"
        case .spectrum:
            "SpectrumViz"
        }
    }

    var vertexFunc: String {
        switch self {
        case .radialFunk:
            return "radial_viz_vertex"
        case .spectrum:
            return "spectrum_vertex"
        case .bars:
            return "bars_vertex"
        case .kishimisu:
            return "kishimisu_vertex"
        }
    }

    var fragmentFunc: String {
        switch self {
        case .radialFunk:
            return "radial_viz_fragment"
        case .spectrum:
            return "spectrum_fragment"
        case .bars:
            return "bars_fragment"
        case .kishimisu:
            return "kishimisu_fragment"
        }
    }
}

extension Viz {
    var binsCount: Int {
        switch self {
        case .radialFunk:
            return 360
        case .spectrum:
            return 80
        case .bars:
            return 40
        case .kishimisu:
            return 50
        }
    }

    var scalingMultiplier: Double {
        switch self {
        case .radialFunk:
            return 80
        case .spectrum:
            return 80
        case .bars:
            return 30
        case .kishimisu:
            return 30
        }
    }
}


extension Viz {
    func pipelineState(device: Device) -> MTLRenderPipelineState? {
        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = device.lib.makeFunction(name: vertexFunc)
        pipelineDesc.fragmentFunction = device.lib.makeFunction(name: fragmentFunc)
        pipelineDesc.colorAttachments[0].pixelFormat = device.pixelFormat
        return (try? device.mtlDevice.makeRenderPipelineState(descriptor: pipelineDesc))
    }
}
