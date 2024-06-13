//
//  AVAudio+PCM.swift
//  FileProviderSample
//
//  Created by Raheel Ahmad on 6/17/23.
//

import Foundation
import AVFoundation

extension AVAudioPCMBuffer {
    /// Returns audio data as an `Array` of `Float` Arrays.
    ///
    /// If stereo:
    /// - `floatChannelData?[0]` will contain an Array of left channel samples as `Float`
    /// - `floatChannelData?[1]` will contains an Array of right channel samples as `Float`
    func toFloatChannelData() -> [[Float]]? {
        // Do we have PCM channel data?
        guard let pcmFloatChannelData = floatChannelData else {
            return nil
        }

        let channelCount = Int(format.channelCount)
        let frameLength = Int(self.frameLength)
        let stride = self.stride

        // Preallocate our Array so we're not constantly thrashing while resizing as we append.
        let zeroes: [Float] = Array(repeating: 0, count: frameLength)
        var result = Array(repeating: zeroes, count: channelCount)

        // Loop across our channels...
        for channel in 0 ..< channelCount {
            // Make sure we go through all of the frames...
            for sampleIndex in 0 ..< frameLength {
                result[channel][sampleIndex] = pcmFloatChannelData[channel][sampleIndex * stride]
            }
        }

        return result
    }
}

extension AVAudioFile {
    /// converts to a 32 bit PCM buffer
    func toAVAudioPCMBuffer() -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                            frameCapacity: AVAudioFrameCount(length)) else { return nil }

        do {
            framePosition = 0
            try read(into: buffer)
        } catch let error as NSError {
            errorLog("Cannot read into buffer " + error.localizedDescription)
        }

        return buffer
    }

    /// converts to Swift friendly Float array
    public func toFloatChannelData() -> [[Float]]? {
        guard let pcmBuffer = toAVAudioPCMBuffer(),
              let data = pcmBuffer.toFloatChannelData() else { return nil }
        return data
    }
}
/// Returns the minimums of chunks of binSize.
func binMin(samples: [Float], binSize: Int) -> [Float] {
    var out: [Float] = .init(repeating: 0.0, count: samples.count / binSize)

    // Note: we have to use a dumb while loop to avoid swift's Range and have
    //       decent perf in debug.
    var bin = 0
    while bin < out.count {

        // Note: we could do the following but it's too slow in debug
        // out[bin] = samples[(bin * binSize) ..< ((bin + 1) * binSize)].min()!

        var v = Float.greatestFiniteMagnitude
        let start: Int = bin * binSize
        let end: Int = (bin + 1) * binSize
        var i = start
        while i < end {
            v = min(samples[i], v)
            i += 1
        }
        out[bin] = v
        bin += 1
    }
    return out
}

/// Returns the maximums of chunks of binSize.
func binMax(samples: [Float], binSize: Int) -> [Float] {
    var out: [Float] = .init(repeating: 0.0, count: samples.count / binSize)

    // Note: we have to use a dumb while loop to avoid swift's Range and have
    //       decent perf in debug.
    var bin = 0
    while bin < out.count {

        // Note: we could do the following but it's too slow in debug
        // out[bin] = samples[(bin * binSize) ..< ((bin + 1) * binSize)].max()!

        var v = -Float.greatestFiniteMagnitude
        let start: Int = bin * binSize
        let end: Int = (bin + 1) * binSize
        var i = start
        while i < end {
            v = max(samples[i], v)
            i += 1
        }
        out[bin] = v
        bin += 1
    }
    return out
}

public final class SampleBuffer: Sendable {
    let samples: [Float]

    /// Initialize the buffer with samples
    public init(samples: [Float]) {
        self.samples = samples
    }

    /// Number of samples
    public var count: Int {
        samples.count
    }
}

