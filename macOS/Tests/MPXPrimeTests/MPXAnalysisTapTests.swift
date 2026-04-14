import XCTest
@testable import MPXPrime

final class MPXAnalysisTapTests: XCTestCase {
    func testAnalysisBuffersPreserveStereoOrdering() {
        var config = AppConfig()
        config.processingBypass = true
        config.widebandAGCEnabled = false
        config.inputGainDB = 0.0
        config.monoMode = false

        let generator = MPXGenerator(config: config, sampleRate: config.sampleRate)
        let frameCount = 512
        var inputLeft = Array(repeating: Float(0.20), count: frameCount)
        var inputRight = Array(repeating: Float(0.60), count: frameCount)
        var postAGCLeft = Array(repeating: Float.zero, count: frameCount)
        var postAGCRight = Array(repeating: Float.zero, count: frameCount)
        var preMPXLeft = Array(repeating: Float.zero, count: frameCount)
        var preMPXRight = Array(repeating: Float.zero, count: frameCount)

        inputLeft.withUnsafeMutableBufferPointer { leftBuffer in
            inputRight.withUnsafeMutableBufferPointer { rightBuffer in
                postAGCLeft.withUnsafeMutableBufferPointer { postLeftBuffer in
                    postAGCRight.withUnsafeMutableBufferPointer { postRightBuffer in
                        preMPXLeft.withUnsafeMutableBufferPointer { preLeftBuffer in
                            preMPXRight.withUnsafeMutableBufferPointer { preRightBuffer in
                                generator.renderFromInputInPlace(
                                    frameCount: frameCount,
                                    left: leftBuffer.baseAddress!,
                                    right: rightBuffer.baseAddress!,
                                    analysis: MPXGenerator.AnalysisBuffers(
                                        postAGCLeft: postLeftBuffer.baseAddress!,
                                        postAGCRight: postRightBuffer.baseAddress!,
                                        preMPXLeft: preLeftBuffer.baseAddress!,
                                        preMPXRight: preRightBuffer.baseAddress!
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }

        let stableRange = 256..<frameCount
        let meanPostLeft = stableRange.reduce(Float.zero) { $0 + postAGCLeft[$1] } / Float(stableRange.count)
        let meanPostRight = stableRange.reduce(Float.zero) { $0 + postAGCRight[$1] } / Float(stableRange.count)
        let meanPreLeft = stableRange.reduce(Float.zero) { $0 + preMPXLeft[$1] } / Float(stableRange.count)
        let meanPreRight = stableRange.reduce(Float.zero) { $0 + preMPXRight[$1] } / Float(stableRange.count)

        XCTAssertEqual(meanPostLeft, 0.20, accuracy: 0.01)
        XCTAssertEqual(meanPostRight, 0.60, accuracy: 0.01)
        XCTAssertGreaterThan(meanPreRight, meanPreLeft)
        XCTAssertGreaterThan(meanPreRight - meanPreLeft, 0.20)
    }

    func testMonitorBypassAnalysisTracksDirectStereoPath() {
        var config = AppConfig()
        config.processingBypass = true
        config.widebandAGCEnabled = false
        config.inputGainDB = 0.0
        config.monoMode = false

        let generator = MPXGenerator(config: config, sampleRate: config.sampleRate)
        let frameCount = 64
        var inputLeft = Array(repeating: Float(0.15), count: frameCount)
        var inputRight = Array(repeating: Float(-0.35), count: frameCount)
        var postAGCLeft = Array(repeating: Float.zero, count: frameCount)
        var postAGCRight = Array(repeating: Float.zero, count: frameCount)
        var preMPXLeft = Array(repeating: Float.zero, count: frameCount)
        var preMPXRight = Array(repeating: Float.zero, count: frameCount)

        inputLeft.withUnsafeMutableBufferPointer { leftBuffer in
            inputRight.withUnsafeMutableBufferPointer { rightBuffer in
                postAGCLeft.withUnsafeMutableBufferPointer { postLeftBuffer in
                    postAGCRight.withUnsafeMutableBufferPointer { postRightBuffer in
                        preMPXLeft.withUnsafeMutableBufferPointer { preLeftBuffer in
                            preMPXRight.withUnsafeMutableBufferPointer { preRightBuffer in
                                generator.renderMonitorFromInputInPlace(
                                    frameCount: frameCount,
                                    left: leftBuffer.baseAddress!,
                                    right: rightBuffer.baseAddress!,
                                    analysis: MPXGenerator.AnalysisBuffers(
                                        postAGCLeft: postLeftBuffer.baseAddress!,
                                        postAGCRight: postRightBuffer.baseAddress!,
                                        preMPXLeft: preLeftBuffer.baseAddress!,
                                        preMPXRight: preRightBuffer.baseAddress!
                                    )
                                )
                            }
                        }
                    }
                }
            }
        }

        XCTAssertEqual(inputLeft[frameCount - 1], postAGCLeft[frameCount - 1], accuracy: 0.0001)
        XCTAssertEqual(inputRight[frameCount - 1], postAGCRight[frameCount - 1], accuracy: 0.0001)
        XCTAssertEqual(preMPXLeft[frameCount - 1], postAGCLeft[frameCount - 1], accuracy: 0.0001)
        XCTAssertEqual(preMPXRight[frameCount - 1], postAGCRight[frameCount - 1], accuracy: 0.0001)
    }
}
