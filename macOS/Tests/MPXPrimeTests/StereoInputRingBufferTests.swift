import XCTest
@testable import MPXPrime

final class StereoInputRingBufferTests: XCTestCase {
    func testStereoWriteReadRoundTrip() {
        let ring = StereoInputRingBuffer(capacityFrames: 8)
        let left: [Float] = [1, 2, 3, 4]
        let right: [Float] = [11, 12, 13, 14]
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: 4)
            }
        }

        var outLeft = [Float](repeating: 0, count: 4)
        var outRight = [Float](repeating: 0, count: 4)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 4
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, left)
        XCTAssertEqual(outRight, right)
    }

    func testMonoWriteDuplicatesChannels() {
        let ring = StereoInputRingBuffer(capacityFrames: 8)
        let mono: [Float] = [0.25, 0.5, 0.75]
        mono.withUnsafeBufferPointer { buffer in
            ring.writeMono(mono: buffer.baseAddress!, frameCount: mono.count)
        }

        var outLeft = [Float](repeating: 0, count: mono.count)
        var outRight = [Float](repeating: 0, count: mono.count)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: mono.count
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, mono)
        XCTAssertEqual(outRight, mono)
    }

    func testWraparoundReadWrite() {
        let ring = StereoInputRingBuffer(capacityFrames: 512)
        let firstLeft: [Float] = Array(0..<500).map(Float.init)
        let firstRight: [Float] = Array(1000..<1500).map(Float.init)
        firstLeft.withUnsafeBufferPointer { leftBuffer in
            firstRight.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: firstLeft.count)
            }
        }

        var discardLeft = [Float](repeating: 0, count: 496)
        var discardRight = [Float](repeating: 0, count: 496)
        _ = discardLeft.withUnsafeMutableBufferPointer { leftBuffer in
            discardRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 496
                )
            }
        }

        let secondLeft: [Float] = Array(500..<532).map(Float.init)
        let secondRight: [Float] = Array(1500..<1532).map(Float.init)
        secondLeft.withUnsafeBufferPointer { leftBuffer in
            secondRight.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: secondLeft.count)
            }
        }

        var outLeft = [Float](repeating: 0, count: 36)
        var outRight = [Float](repeating: 0, count: 36)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 36
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, Array(496..<532).map(Float.init))
        XCTAssertEqual(outRight, Array(1496..<1532).map(Float.init))
    }

    func testOverflowKeepsNewestFrames() {
        let ring = StereoInputRingBuffer(capacityFrames: 512)
        let left: [Float] = Array(0..<520).map(Float.init)
        let right: [Float] = Array(1000..<1520).map(Float.init)
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: left.count)
            }
        }

        var outLeft = [Float](repeating: 0, count: 512)
        var outRight = [Float](repeating: 0, count: 512)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 512
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, Array(8..<520).map(Float.init))
        XCTAssertEqual(outRight, Array(1008..<1520).map(Float.init))
        XCTAssertEqual(ring.stats().overflows, 8)
    }

    func testUnderflowCountsAndZeroFills() {
        let ring = StereoInputRingBuffer(capacityFrames: 8)
        let left: [Float] = [1, 2]
        let right: [Float] = [11, 12]
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: 2)
            }
        }

        var outLeft = [Float](repeating: -1, count: 4)
        var outRight = [Float](repeating: -1, count: 4)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 4
                )
            }
        }

        XCTAssertEqual(missing, 2)
        XCTAssertEqual(outLeft, [1, 2, 0, 0])
        XCTAssertEqual(outRight, [11, 12, 0, 0])
        XCTAssertEqual(ring.stats().underflows, 2)
    }

    func testBufferedFramesAndStats() {
        let ring = StereoInputRingBuffer(capacityFrames: 8)
        let left: [Float] = [1, 2, 3]
        let right: [Float] = [11, 12, 13]
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: 3)
            }
        }

        XCTAssertEqual(ring.bufferedFrames(), 3)
        let stats = ring.stats()
        XCTAssertEqual(stats.bufferedFrames, 3)
        XCTAssertEqual(stats.overflows, 0)
        XCTAssertEqual(stats.underflows, 0)
    }

    func testReadAdaptiveMatchedRateDirectPath() {
        let ring = StereoInputRingBuffer(capacityFrames: 8)
        let left: [Float] = [1, 2, 3, 4]
        let right: [Float] = [11, 12, 13, 14]
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: 4)
            }
        }

        var outLeft = [Float](repeating: 0, count: 4)
        var outRight = [Float](repeating: 0, count: 4)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.readAdaptive(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 4,
                    nominalConsume: 4,
                    targetBuffered: 4,
                    deadband: 0
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, left)
        XCTAssertEqual(outRight, right)
    }

    func testReadAdaptiveFractionalPathMaintainsContinuity() {
        let ring = StereoInputRingBuffer(capacityFrames: 16)
        let left: [Float] = Array(0..<12).map(Float.init)
        let right: [Float] = Array(100..<112).map(Float.init)
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: 12)
            }
        }

        var outLeft = [Float](repeating: 0, count: 4)
        var outRight = [Float](repeating: 0, count: 4)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.readAdaptive(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 4,
                    nominalConsume: 6,
                    targetBuffered: 8,
                    deadband: 0
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft[0], 0, accuracy: 0.0001)
        XCTAssertGreaterThan(outLeft[1], outLeft[0])
        XCTAssertGreaterThan(outLeft[2], outLeft[1])
        XCTAssertGreaterThan(outLeft[3], outLeft[2])
        XCTAssertEqual(outRight[0], 100, accuracy: 0.0001)
        XCTAssertGreaterThan(outRight[1], outRight[0])
    }

    func testReadAdaptiveMatchedRateReportsDirectMode() {
        let ring = StereoInputRingBuffer(capacityFrames: 32)
        let left: [Float] = Array(0..<16).map(Float.init)
        let right: [Float] = Array(100..<116).map(Float.init)
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: left.count)
            }
        }

        var outLeft = [Float](repeating: 0, count: 16)
        var outRight = [Float](repeating: 0, count: 16)
        _ = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.readAdaptive(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 16,
                    nominalConsume: 16,
                    targetBuffered: 16,
                    deadband: 0
                )
            }
        }

        let snapshot = ring.transportSnapshot()
        XCTAssertEqual(snapshot.resampleMode, "direct")
        XCTAssertEqual(snapshot.sampleStep, 1.0, accuracy: 0.000001)
        XCTAssertEqual(snapshot.ratioTrim, 0.0, accuracy: 0.000001)
        XCTAssertEqual(outLeft, left)
        XCTAssertEqual(outRight, right)
    }

    func testAdaptiveCubicInterpolationBeatsLinearForHighFrequencySine() {
        let ring = StereoInputRingBuffer(capacityFrames: 128)
        let omega = 2.0 * Double.pi * 0.22
        let sourceCount = 96
        let source = (0..<sourceCount).map { Float(sin(Double($0) * omega)) }
        source.withUnsafeBufferPointer { mono in
            ring.writeMono(mono: mono.baseAddress!, frameCount: source.count)
        }

        var outLeft = [Float](repeating: 0, count: 32)
        var outRight = [Float](repeating: 0, count: 32)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.readAdaptive(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 32,
                    nominalConsume: 48,
                    targetBuffered: sourceCount,
                    deadband: 0
                )
            }
        }

        XCTAssertEqual(missing, 0)
        let expected = (0..<32).map { Float(sin(Double($0) * 1.5 * omega)) }
        let cubicError = rmsError(actual: outLeft, expected: expected)
        let linearReference = (0..<32).map { index -> Float in
            let position = Double(index) * 1.5
            let base = Int(position.rounded(.down))
            let frac = Float(position - Double(base))
            let next = min(base + 1, source.count - 1)
            let a = source[base]
            let b = source[next]
            return a + ((b - a) * frac)
        }
        let linearError = rmsError(actual: linearReference, expected: expected)

        XCTAssertLessThan(cubicError, linearError)
        XCTAssertEqual(ring.transportSnapshot().resampleMode, "adaptive-cubic")
    }

    func testLargeWriteLargerThanCapacityKeepsNewestTail() {
        let ring = StereoInputRingBuffer(capacityFrames: 512)
        let left: [Float] = Array(0..<600).map(Float.init)
        let right: [Float] = Array(200..<800).map(Float.init)
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                ring.write(left: leftBuffer.baseAddress!, right: rightBuffer.baseAddress!, frameCount: left.count)
            }
        }

        var outLeft = [Float](repeating: 0, count: 512)
        var outRight = [Float](repeating: 0, count: 512)
        let missing = outLeft.withUnsafeMutableBufferPointer { leftBuffer in
            outRight.withUnsafeMutableBufferPointer { rightBuffer in
                ring.read(
                    intoLeft: leftBuffer.baseAddress!,
                    outRight: rightBuffer.baseAddress!,
                    frameCount: 512
                )
            }
        }

        XCTAssertEqual(missing, 0)
        XCTAssertEqual(outLeft, Array(88..<600).map(Float.init))
        XCTAssertEqual(outRight, Array(288..<800).map(Float.init))
        XCTAssertEqual(ring.stats().overflows, 88)
    }

    private func rmsError(actual: [Float], expected: [Float]) -> Float {
        let count = min(actual.count, expected.count)
        guard count > 0 else { return 0.0 }
        let sum = (0..<count).reduce(Float.zero) { partial, index in
            let delta = actual[index] - expected[index]
            return partial + (delta * delta)
        }
        return sqrt(sum / Float(count))
    }
}
