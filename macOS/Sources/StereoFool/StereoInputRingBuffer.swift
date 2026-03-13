import Foundation

final class StereoInputRingBuffer {
    private let capacity: Int
    private var left: [Float]
    private var right: [Float]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var lastLeft: Float = 0.0
    private var lastRight: Float = 0.0
    private var resamplePhase: Double = 0.0
    private var resampleRatioTrim: Double = 0.0
    private var overflowCount: UInt64 = 0
    private var underflowCount: UInt64 = 0
    private let lock = NSLock()

    init(capacityFrames: Int) {
        let n = max(512, capacityFrames)
        self.capacity = n
        self.left = Array(repeating: 0.0, count: n)
        self.right = Array(repeating: 0.0, count: n)
    }

    func write(
        left inLeft: UnsafePointer<Float>, right inRight: UnsafePointer<Float>, frameCount: Int
    ) {
        guard frameCount > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        dropOldestIfNeeded(framesToWrite: frameCount)
        var remaining = frameCount
        var srcOffset = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - writeIndex)
            left.withUnsafeMutableBufferPointer { dstL in
                right.withUnsafeMutableBufferPointer { dstR in
                    let dl = dstL.baseAddress!.advanced(by: writeIndex)
                    let dr = dstR.baseAddress!.advanced(by: writeIndex)
                    dl.update(from: inLeft.advanced(by: srcOffset), count: chunk)
                    dr.update(from: inRight.advanced(by: srcOffset), count: chunk)
                }
            }
            writeIndex = (writeIndex + chunk) % capacity
            count += chunk
            srcOffset += chunk
            remaining -= chunk
        }
    }

    func writeMono(mono inMono: UnsafePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        dropOldestIfNeeded(framesToWrite: frameCount)
        var remaining = frameCount
        var srcOffset = 0
        while remaining > 0 {
            let chunk = min(remaining, capacity - writeIndex)
            left.withUnsafeMutableBufferPointer { dstL in
                right.withUnsafeMutableBufferPointer { dstR in
                    let dl = dstL.baseAddress!.advanced(by: writeIndex)
                    let dr = dstR.baseAddress!.advanced(by: writeIndex)
                    for i in 0..<chunk {
                        let s = inMono[srcOffset + i]
                        dl[i] = s
                        dr[i] = s
                    }
                }
            }
            writeIndex = (writeIndex + chunk) % capacity
            count += chunk
            srcOffset += chunk
            remaining -= chunk
        }
    }

    func read(
        intoLeft outLeft: UnsafeMutablePointer<Float>,
        outRight: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        var missing = 0
        lock.lock()
        let available = min(frameCount, count)
        if available > 0 {
            var remaining = available
            var dstOffset = 0
            var srcIdx = readIndex
            while remaining > 0 {
                let chunk = min(remaining, capacity - srcIdx)
                left.withUnsafeBufferPointer { srcL in
                    right.withUnsafeBufferPointer { srcR in
                        outLeft.advanced(by: dstOffset).update(
                            from: srcL.baseAddress!.advanced(by: srcIdx),
                            count: chunk
                        )
                        outRight.advanced(by: dstOffset).update(
                            from: srcR.baseAddress!.advanced(by: srcIdx),
                            count: chunk
                        )
                    }
                }
                srcIdx = (srcIdx + chunk) % capacity
                dstOffset += chunk
                remaining -= chunk
            }
            lastLeft = outLeft[available - 1]
            lastRight = outRight[available - 1]
            readIndex = (readIndex + available) % capacity
            count -= available
        }
        if available < frameCount {
            for i in available..<frameCount {
                outLeft[i] = 0.0
                outRight[i] = 0.0
            }
            missing = frameCount - available
            if available == 0 {
                lastLeft = 0.0
                lastRight = 0.0
            }
            underflowCount += UInt64(missing)
        }
        lock.unlock()
        return missing
    }

    func readAdaptive(
        intoLeft outLeft: UnsafeMutablePointer<Float>,
        outRight: UnsafeMutablePointer<Float>,
        frameCount: Int,
        nominalConsume: Int,
        targetBuffered: Int,
        deadband: Int
    ) -> Int {
        guard frameCount > 0 else { return 0 }
        lock.lock()
        let available = count
        if available <= 0 {
            for i in 0..<frameCount {
                outLeft[i] = 0.0
                outRight[i] = 0.0
            }
            lastLeft = 0.0
            lastRight = 0.0
            resamplePhase = 0.0
            resampleRatioTrim = 0.0
            underflowCount += UInt64(frameCount)
            lock.unlock()
            return frameCount
        }

        let nominal = max(1, nominalConsume)
        // When input and render rates are matched (nominal == frameCount),
        // use pure direct copy with NO adaptive resampling to preserve stereo phase.
        // This avoids long-term phase drift from trim accumulation.
        if nominal == frameCount {
            // Always direct copy - don't condition on buffer level
            let available_ = min(frameCount, available)
            var missing = 0

            if available_ > 0 {
                var remaining = available_
                var dstOffset = 0
                var srcIdx = readIndex
                while remaining > 0 {
                    let chunk = min(remaining, capacity - srcIdx)
                    left.withUnsafeBufferPointer { srcL in
                        right.withUnsafeBufferPointer { srcR in
                            outLeft.advanced(by: dstOffset).update(
                                from: srcL.baseAddress!.advanced(by: srcIdx),
                                count: chunk
                            )
                            outRight.advanced(by: dstOffset).update(
                                from: srcR.baseAddress!.advanced(by: srcIdx),
                                count: chunk
                            )
                        }
                    }
                    srcIdx = (srcIdx + chunk) % capacity
                    dstOffset += chunk
                    remaining -= chunk
                }
                lastLeft = outLeft[available_ - 1]
                lastRight = outRight[available_ - 1]
                readIndex = (readIndex + available_) % capacity
                count -= available_

                if available_ < frameCount {
                    for i in available_..<frameCount {
                        outLeft[i] = lastLeft
                        outRight[i] = lastRight
                    }
                    missing = frameCount - available_
                    underflowCount += UInt64(missing)
                }
            } else {
                for i in 0..<frameCount {
                    outLeft[i] = 0.0
                    outRight[i] = 0.0
                }
                missing = frameCount
                underflowCount += UInt64(missing)
            }

            // Reset adaptive state when using direct copy
            resamplePhase = 0.0
            resampleRatioTrim = 0.0
            lock.unlock()
            return missing
        }

        let target = max(1, targetBuffered)
        let deadbandFrames = max(0, deadband)
        let errorFrames = Double(available - target)
        let trimTarget: Double
        if abs(errorFrames) <= Double(deadbandFrames) {
            trimTarget = 0.0
        } else {
            let normalized = errorFrames / Double(target)
            trimTarget = max(-0.02, min(0.02, normalized * 0.06))
        }
        resampleRatioTrim += (trimTarget - resampleRatioTrim) * 0.025

        let nominalRatio = Double(nominal) / Double(max(1, frameCount))
        let step = max(0.25, min(4.0, nominalRatio * (1.0 + resampleRatioTrim)))

        var localPhase = resamplePhase
        var missing = 0
        for i in 0..<frameCount {
            let base = Int(localPhase)
            if base >= available {
                outLeft[i] = 0.0
                outRight[i] = 0.0
                missing += 1
            } else {
                let frac = Float(localPhase - Double(base))
                let idx0 = (readIndex + base) % capacity
                let nextBase = min(base + 1, available - 1)
                let idx1 = (readIndex + nextBase) % capacity
                let l0 = left[idx0]
                let l1 = left[idx1]
                let r0 = right[idx0]
                let r1 = right[idx1]
                let l = l0 + ((l1 - l0) * frac)
                let r = r0 + ((r1 - r0) * frac)
                outLeft[i] = l
                outRight[i] = r
                lastLeft = l
                lastRight = r
            }
            localPhase += step
        }

        let consumed = min(available, Int(localPhase))
        readIndex = (readIndex + consumed) % capacity
        count -= consumed
        if consumed >= available {
            resamplePhase = 0.0
        } else {
            resamplePhase = localPhase - Double(consumed)
            // Prevent extreme phase values from accumulating
            if resamplePhase > Double(capacity) / 2 {
                resamplePhase = Double(capacity) / 4
            }
        }
        if missing > 0 {
            underflowCount += UInt64(missing)
        }
        lock.unlock()
        return missing
    }

    private func dropOldestIfNeeded(framesToWrite: Int) {
        let overflow = max(0, (count + framesToWrite) - capacity)
        if overflow > 0 {
            readIndex = (readIndex + overflow) % capacity
            count -= overflow
            overflowCount += UInt64(overflow)
        }
    }

    func bufferedFrames() -> Int {
        lock.lock()
        let buffered = count
        lock.unlock()
        return buffered
    }

    func stats() -> (overflows: UInt64, underflows: UInt64, bufferedFrames: Int) {
        lock.lock()
        let over = overflowCount
        let under = underflowCount
        let buffered = count
        lock.unlock()
        return (over, under, buffered)
    }
}
