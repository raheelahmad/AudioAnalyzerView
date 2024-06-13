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

/// TODO: rename to AudioNode provider
public protocol VisualizerDataProcesserDelegate: AnyObject {
    /// The node to tap
    var playerNode: AVAudioPlayerNode { get }
}

public protocol VisualizerRenderInfoProvider: AnyObject {
    var mtlDevice: MTLDevice { get }
    var binsCount: Int { get }
    var scalingMultiplier: Double { get }
}

public final class VisualizerDataBuilder: ObservableObject {
    public weak var renderInfoProvider: (any VisualizerRenderInfoProvider)?
    weak var delegate: VisualizerDataProcesserDelegate?

    var device: MTLDevice? { renderInfoProvider?.mtlDevice }

    private var loudnessMagnitude: Float = 0 {
        didSet {
            loudnessBuffer = device?.makeBuffer(bytes: &loudnessMagnitude, length: MemoryLayout<Float>.stride)
            liveLoudnessignal
                .send(loudnessMagnitude)
        }
    }

    public let maxBuffersCount = 8
    public var hasBuffers: Bool {
        freqeuencyBuffer != nil && loudnessBuffer != nil
    }
    var frequencyVertices : [Float] = [] {
        didSet {
            guard frequencyVertices.count == renderInfoProvider?.binsCount else { return }
            var allFrequenciesBuffers = self.allFrequenciesBuffers
            if allFrequenciesBuffers.count == maxBuffersCount {
                allFrequenciesBuffers = Array(allFrequenciesBuffers.dropFirst())
            }
            allFrequenciesBuffers.append(frequencyVertices)
            self.allFrequenciesBuffers = allFrequenciesBuffers
        }
    }

    private var subscriptions: [AnyCancellable] = []
    let loudness = PassthroughSubject<Float, Never>.init()
    private let liveLoudnessignal = PassthroughSubject<Float, Never>.init()

    public init() {
        liveLoudnessignal
            .throttle(for: 0.15, scheduler: RunLoop.main, latest: true)
            .subscribe(self.loudness)
            .store(in: &subscriptions)
    }

    public var allFrequenciesBuffers: [[Float]] = [] {
        didSet {
            guard let binsCount = renderInfoProvider?.binsCount, let device, !allFrequenciesBuffers.isEmpty else {
//                assertionFailure("Incomplete device info")
                return
            }
            assert(allFrequenciesBuffers.allSatisfy { $0.count == binsCount })
            let frequenciesBuffer = allFrequenciesBuffers.flatMap { $0 }
            freqeuencyBuffer = device
                .makeBuffer(
                    bytes: frequenciesBuffer,
                    length: frequenciesBuffer.count * MemoryLayout<Float>.stride,
                    options: []
                )!
            print(
                "Frequencies buffer count: \(frequenciesBuffer.count): \(allFrequenciesBuffers.count) * \(binsCount)"
            )
        }
    }
    public private(set) var loudnessBuffer: MTLBuffer?
    public private(set) var freqeuencyBuffer : MTLBuffer!
    public var shouldProduceFrequenciesOnTap = false
    
    public func resetBuffers() {
        allFrequenciesBuffers.removeAll()
    }

    public func prepare() {
        let node = self.delegate?.playerNode
        node?.removeTap(onBus: 0)
        node?.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            self?.processAudioData(buffer: buffer)
        }

        // Set something for the resting state as well:
//        frequencyVertices = .init(repeating: 0, count: renderInfoProvider?.binsCount ?? 0)
        loudnessMagnitude = 0.1
    }

    func teardown() {
        self.delegate?.playerNode.removeTap(onBus: 0)
    }

    /// This is called internally on a tap if there is a `playerNodeg, or by calling it directly.
    /// This should be refactored so that either these two strategies are provided separately, or
    /// the `playerNode` tapping is done externally, and ``processAudioData(buffer:)`` is the only entry point.
    public func processAudioData(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = buffer.frameLength

        //rms
        var rmsValue = rms(data: channelData, frameLength: UInt(frames))
//        let interpolatedRMSValues = Self.interpolate(current: rmsValue, previous: loudnessMagnitude)
//        rmsValue = interpolatedRMSValues.reduce(0) { $0 + $1 } / Float(interpolatedRMSValues.count)
        loudnessMagnitude = rmsValue

        //fft
        if shouldProduceFrequenciesOnTap {
            guard let binsCount = renderInfoProvider?.binsCount, let scalingMultiplier = renderInfoProvider?.scalingMultiplier else {
                return
            }
            var fftMagnitudes = Self.fft(data: channelData, setup: fftSetup!, binsCount: binsCount, scalingMultiplier: scalingMultiplier)
            if fftMagnitudes.count == frequencyVertices.count {
                fftMagnitudes = fftMagnitudes.enumerated()
                    .map { (idx, magnitude) in
                        let values = Self.interpolate(current: magnitude, previous: frequencyVertices[idx])
                        let interpolatedValue = values.reduce(0) { $0 + $1 } / Float(values.count)
                        return interpolatedValue
                    }
            }

            frequencyVertices = fftMagnitudes
        }
    }

    static func fft(data: UnsafeMutablePointer<Float>, setup: OpaquePointer, binsCount: Int, scalingMultiplier: Double) -> [Float]{
        //output setup
        var realIn = [Float](repeating: 0, count: 1024)
        var imagIn = [Float](repeating: 0, count: 1024)
        var realOut = [Float](repeating: 0, count: 1024)
        var imagOut = [Float](repeating: 0, count: 1024)

        //fill in real input part with audio samples
        for i in 0...1023 {
            realIn[i] = data[i]
        }


        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        //our results are now inside realOut and imagOut

        //package it inside a complex vector representation used in the vDSP framework
        var complex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)

        //setup magnitude output
        var magnitudes = [Float](repeating: 0, count: binsCount)

        //calculate magnitude results
        vDSP_zvabs(&complex, 1, &magnitudes, 1, UInt(binsCount))

        //normalize
        var normalizedMagnitudes = [Float](repeating: 0.0, count: binsCount)
        var scalingFactor = Float(scalingMultiplier/Double(binsCount))
        vDSP_vsmul(&magnitudes, 1, &scalingFactor, &normalizedMagnitudes, 1, UInt(binsCount))
        return normalizedMagnitudes
    }

    static func interpolate(current: Float, previous: Float) -> [Float]{
        var vals = [Float](repeating: 0, count: 7)
        vals[6] = current
        vals[3] = (current + previous)/2
        vals[1] = (vals[2] + previous)/2

        vals[4] = (vals[3] + current)/2
        vals[5] = (vals[6] + current)/2
        vals[2] = (vals[1] + vals[3])/2
        vals[0] = (previous + vals[1])/2

        return vals
    }

    //fft setup object for 1024 values going forward (time domain -> frequency domain)
    let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)

    private func rms(data: UnsafeMutablePointer<Float>, frameLength: UInt) -> Float {
        var val : Float = 0
        vDSP_measqv(data, 1, &val, frameLength)

        var db = 10*log10f(val)
        //inverse dB to +ve range where 0(silent) -> 160(loudest)
        db = 160 + db;
        //Only take into account range from 120->160, so FSR = 40
        db = db - 120

        let dividor = Float(40/0.3)
        var adjustedVal = 0.0 + db/dividor
        adjustedVal = min(1, max(0, adjustedVal))

        let minimum: Float = 0.03
        let maximum: Float = 0.25
        // lerp from 0 → 1:
        var result = (adjustedVal - minimum) / (maximum - minimum)
        // clamp:
        result = min(1, max(0, result))
        return result
    }

}

public final class WaveformBuilder {
    // TODO: do we need to retain this?
    private var reader: AVAssetReader?
    let waveformValues: PassthroughSubject<[Float], Never> = .init()
    let snapshotWaveformValues: PassthroughSubject<SnapshotWaveform, Never> = .init()

    public struct SnapshotWaveform: Identifiable {
        public let id: String = UUID().uuidString
        public let waveformValues: [Float]
    }


    public func loadFullAndReset(file: AVAudioFile, shouldLoadWaveform: Bool) {
        reader = nil

        if shouldLoadWaveform {
            setupReaderIfNotAvailable(file: file)

            loadWaveform(range: nil, file: file) { [weak self] samples in
                if let samples {
                    self?.waveformValues.send(samples)
                }
            }
        }
    }

    /// TODO: we could also take a fraction from the full ``waveformValues`` (which should be present)
    /// that represents the segment's range, and not have to load the waveform from the file.
    public func loadSegment(_ timeRange: CMTimeRange, file: AVAudioFile) {
        loadWaveform(range: timeRange, file: file) { [weak self] samples in
            if let samples {
                self?.snapshotWaveformValues.send(.init(waveformValues: samples))
            }
        }
    }

    public func loadInflightSegment(_ timeRange: CMTimeRange, file: AVAudioFile) {
        loadWaveform(range: timeRange, file: file) { [weak self] samples in
            if let samples {
                self?.snapshotWaveformValues.send(.init(waveformValues: samples))
            }
        }
    }

    private func loadWaveform(range: CMTimeRange?, file: AVAudioFile, completion: @escaping (([Float]?) -> ())) {
        guard let reader else {
            errorLog("Asked to load waveform, but no reader was present.")
            return
        }

        guard let track = reader.asset.tracks(withMediaType: .audio).first else {
            errorLog("No audio track in \(file.url)")
            completion(nil)
            return
        }

        let desiredNumberOfSamples = range == nil ? 800 : 100

        SamplesExtractor.samples(audioTrack: track, timeRange: range, desiredNumberOfSamples: desiredNumberOfSamples) { samples, sampleMax, identifier in
            completion(samples)
        } onFailure: { error, identifier in
            errorLog(error.localizedDescription)
            completion(nil)
        }
    }

    private func setupReaderIfNotAvailable(file: AVAudioFile) {
        guard reader == nil else {
            return
        }

        let asset = AVURLAsset(url: file.url)
        do {
            let reader = try AVAssetReader(asset: asset)
            self.reader = reader
        } catch {
            errorLog("Error setting up AssetReader for \(file): " + error.localizedDescription)
        }
    }
}

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

    public init() {
        dataBuilder = .init()
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
        let p = VisualizerInfoProvider()
        p.waveformValues = (0..<100).map { _ in Float.random(in: 0..<(1.0))}
        p.snapshotWaveformValues = .init(waveformValues: (0..<100).map { _ in Float.random(in: 0..<(1.0))})
        return p
    }
}
