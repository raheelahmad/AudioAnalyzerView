//
//  VisualizerDataProcesser.swift
//  FileProviderSample
//
//  Created by Raheel Ahmad on 6/17/23.
//

import Foundation
import AVFoundation
import Accelerate
import SwiftUI
import MetalKit
import Logging
import Combine


/// Only a liaison between the VizDataBuilder (which processes the audio and produces the data)
/// and the user.
public final class VisualizerInfoProvider: ObservableObject {
    public let dataBuilder: VisualizerDataBuilder
    public let waveformBuilder: WaveformBuilder
    @Published public var loudness: Double = 0
    @Published public var waveformValues: [Float] = []
    @Published public var snapshotWaveformValues: WaveformBuilder.SnapshotWaveform = .init(waveformValues: [])

    private var subscriptions: [AnyCancellable] = []

    public weak var delegate: VisualizerDataProcesserDelegate? {
        didSet {
            dataBuilder.delegate = delegate
        }
    }

    public init(config: RendererConfig) {
        dataBuilder = .init(config: config)
        waveformBuilder = .init()
        dataBuilder.loudness.sink { [weak self] in
            self?.loudness = Double($0)
        }.store(in: &subscriptions)
        waveformBuilder.waveformValues.sink { [weak self] in
            self?.waveformValues = $0
        }.store(in: &subscriptions)
        waveformBuilder.snapshotWaveformValues.sink { [weak self] in
            self?.snapshotWaveformValues = $0
        }.store(in: &subscriptions)
    }

    public func prepare() {
        dataBuilder.prepare()
    }

    public func teardown() {
        dataBuilder.teardown()
    }

}

extension VisualizerInfoProvider {
    public static var forPreview: VisualizerInfoProvider {
        let p = VisualizerInfoProvider(
            config: .init(
                amplitude: .init(min: 20, max: 40),
                liveReload: false,
                historicalBuffers: 4
            )
        )
        p.waveformValues = (0..<100).map { _ in Float.random(in: 0..<(1.0))}
        p.snapshotWaveformValues = .init(waveformValues: (0..<100).map { _ in Float.random(in: 0..<(1.0))})
        return p
    }
}
