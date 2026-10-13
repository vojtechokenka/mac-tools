import Foundation

public final class NightChain {

    public static let levelerTargetDB: Float = -3
    public static let levelerIntegrationSec: Double = 0.3
    public static let levelerAttackSec: Double = 0.15
    public static let levelerReleaseSec: Double = 3.0
    public static let levelerMaxBoostDB: Float = 0
    public static let levelerMaxCutDB: Float = -60
    public static let levelerGateDB: Float = -55

    public static let compThresholdDB: Float = -2
    public static let compRatio: Float = 20
    public static let compKneeDB: Float = 6
    public static let compAttackSec: Double = 0.003
    public static let compReleaseSec: Double = 0.2

    public static let limiterLookaheadSec: Double = 0.005
    public static let limiterReleaseSec: Double = 0.08

    public static let ceilingSmoothSec: Double = 0.005

    public private(set) var sampleRate: Double = 48_000
    public private(set) var maxFrames: Int = 0
    public private(set) var latencySamples: Int = 0

    public private(set) var levelerGainDB: Float = 0
    public private(set) var compressorGainDB: Float = 0
    public var limiterGainDB: Float { 20 * log10(max(lastLimiterGain, 1e-6)) }
    private var lastLimiterGain: Float = 1

    private static let db2lin2: Float = 0.16609640474436813
    private static let lin2db2: Float = 6.020599913279624
    private static let pow2db2: Float = 3.010299956639812

    private var msCoef: Float = 0
    private var levAttackCoef: Float = 0
    private var levReleaseCoef: Float = 0
    private var meanSquare: Float = 1e-20
    private var levGainDB: Float = 0

    private var compAttackCoef: Float = 0
    private var compReleaseCoef: Float = 0
    private var compGS: Float = 0
    private var kneeLowLin: Float = 0
    private var kneeLowDB: Float = 0
    private var compSlope: Float = 0
    private var kneeInv2W: Float = 0

    private var look: Int = 0
    private var delayL: UnsafeMutablePointer<Float>
    private var delayR: UnsafeMutablePointer<Float>
    private var delayPos: Int = 0
    private var dqVal: UnsafeMutablePointer<Float>
    private var dqIdx: UnsafeMutablePointer<Int>
    private var dqCap: Int = 0
    private var dqHead: Int = 0
    private var dqCount: Int = 0
    private var sampleIndex: Int = 0
    private var limEnv: Float = 1
    private var limRelCoef: Float = 0
    private var avgBuf: UnsafeMutablePointer<Float>
    private var avgCap: Int = 0
    private var avgPos: Int = 0
    private var avgSum: Double = 0
    private var avgInv: Float = 1

    private var ceilCoef: Float = 0
    private var ceilSmooth: Float = 1
    private var ceilPrimed = false

    private var scratchL: UnsafeMutablePointer<Float>
    private var scratchR: UnsafeMutablePointer<Float>
    private var scratchCap: Int = 0

    public init(sampleRate: Double, maxFrames: Int) {
        delayL = .allocate(capacity: 1); delayR = .allocate(capacity: 1)
        dqVal = .allocate(capacity: 1); dqIdx = .allocate(capacity: 1)
        avgBuf = .allocate(capacity: 1)
        scratchL = .allocate(capacity: 1); scratchR = .allocate(capacity: 1)
        delayL.initialize(to: 0); delayR.initialize(to: 0)
        dqVal.initialize(to: 0); dqIdx.initialize(to: 0)
        avgBuf.initialize(to: 0)
        scratchL.initialize(to: 0); scratchR.initialize(to: 0)
        reconfigure(sampleRate: sampleRate, maxFrames: maxFrames)
    }

    deinit {
        delayL.deallocate(); delayR.deallocate()
        dqVal.deallocate(); dqIdx.deallocate()
        avgBuf.deallocate()
        scratchL.deallocate(); scratchR.deallocate()
    }

    public func reconfigure(sampleRate: Double, maxFrames: Int) {
        let sr = sampleRate.isFinite && sampleRate >= 8_000 ? sampleRate : 48_000
        self.sampleRate = sr
        self.maxFrames = max(1, maxFrames)

        func coef(_ seconds: Double) -> Float { Float(1 - exp(-1 / (seconds * sr))) }

        msCoef = coef(Self.levelerIntegrationSec)
        levAttackCoef = coef(Self.levelerAttackSec)
        levReleaseCoef = coef(Self.levelerReleaseSec)

        compAttackCoef = coef(Self.compAttackSec)
        compReleaseCoef = coef(Self.compReleaseSec)
        kneeLowDB = Self.compThresholdDB - Self.compKneeDB * 0.5
        kneeLowLin = exp2(kneeLowDB * Self.db2lin2)
        compSlope = 1 / Self.compRatio - 1
        kneeInv2W = 1 / (2 * Self.compKneeDB)

        limRelCoef = coef(Self.limiterReleaseSec)
        ceilCoef = coef(Self.ceilingSmoothSec)

        look = max(1, Int((Self.limiterLookaheadSec * sr).rounded()))
        latencySamples = look

        delayL.deallocate(); delayR.deallocate()
        delayL = .allocate(capacity: look); delayR = .allocate(capacity: look)
        delayL.initialize(repeating: 0, count: look); delayR.initialize(repeating: 0, count: look)

        dqCap = look + 2
        dqVal.deallocate(); dqIdx.deallocate()
        dqVal = .allocate(capacity: dqCap); dqIdx = .allocate(capacity: dqCap)
        dqVal.initialize(repeating: 1, count: dqCap); dqIdx.initialize(repeating: 0, count: dqCap)

        avgCap = look + 1
        avgInv = 1 / Float(avgCap)
        avgBuf.deallocate()
        avgBuf = .allocate(capacity: avgCap)
        avgBuf.initialize(repeating: 1, count: avgCap)

        scratchCap = self.maxFrames
        scratchL.deallocate(); scratchR.deallocate()
        scratchL = .allocate(capacity: scratchCap); scratchR = .allocate(capacity: scratchCap)
        scratchL.initialize(repeating: 0, count: scratchCap); scratchR.initialize(repeating: 0, count: scratchCap)

        reset()
    }

    public func reset() {
        meanSquare = 1e-20
        levGainDB = 0
        compGS = 0
        for i in 0..<look { delayL[i] = 0; delayR[i] = 0 }
        delayPos = 0
        dqHead = 0
        dqCount = 0
        sampleIndex = 0
        limEnv = 1
        for i in 0..<avgCap { avgBuf[i] = 1 }
        avgPos = 0
        avgSum = Double(avgCap)
        ceilSmooth = 1
        ceilPrimed = false
        levelerGainDB = 0
        compressorGainDB = 0
        lastLimiterGain = 1
    }

    public func prime(levelerGainDB: Float, compressorGainDB: Float) {
        var l = levelerGainDB
        if !(l <= Self.levelerMaxBoostDB) { l = l.isNaN ? 0 : Self.levelerMaxBoostDB }
        if l < Self.levelerMaxCutDB { l = Self.levelerMaxCutDB }
        var c = compressorGainDB
        if !(c <= 0) { c = 0 }
        if c < -96 { c = -96 }
        levGainDB = l
        compGS = c
        meanSquare = max(1e-20, exp2((Self.levelerTargetDB - l) / Self.pow2db2))
        self.levelerGainDB = l
        self.compressorGainDB = c
    }

    public func process(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, ceiling: Float) {
        var c = ceiling
        if !(c >= 0) { c = 0 }
        if c > 1 { c = 1 }
        if !ceilPrimed { ceilSmooth = c; ceilPrimed = true }

        let msCoef = self.msCoef
        let levA = self.levAttackCoef, levR = self.levReleaseCoef
        let compA = self.compAttackCoef, compR = self.compReleaseCoef
        let limRel = self.limRelCoef
        let ceilCoef = self.ceilCoef
        let look = self.look, dqCap = self.dqCap, avgCap = self.avgCap
        let kneeLowLin = self.kneeLowLin, kneeLowDB = self.kneeLowDB
        let halfKnee = Self.compKneeDB * 0.5
        let compSlope = self.compSlope, kneeInv2W = self.kneeInv2W
        let target = Self.levelerTargetDB
        let gate = Self.levelerGateDB
        let maxBoost = Self.levelerMaxBoostDB, maxCut = Self.levelerMaxCutDB

        var ms = meanSquare
        var gLevDB = levGainDB
        var gs = compGS
        var dPos = delayPos
        var head = dqHead, count = dqCount
        var idx = sampleIndex
        var env = limEnv
        var aPos = avgPos
        var aSum = avgSum
        var cs = ceilSmooth
        var gLim: Float = lastLimiterGain

        for i in 0..<frames {
            let dc = c - cs
            if dc.magnitude < 1e-6 { cs = c } else { cs += ceilCoef * dc }
            let inv: Float = cs > 1e-4 ? 1 / cs : 1e4
            var xl = left[i]
            var xr = right[i]
            if !(xl.magnitude <= 64) { xl = xl.isNaN ? 0 : (xl > 0 ? 64 : -64) }
            if !(xr.magnitude <= 64) { xr = xr.isNaN ? 0 : (xr > 0 ? 64 : -64) }
            xl *= inv
            xr *= inv

            let p = 0.5 * (xl * xl + xr * xr)
            ms += msCoef * (p - ms)
            if ms < 1e-20 { ms = 1e-20 }
            let rmsDB = log2(ms) * Self.pow2db2
            var desired = gLevDB
            if rmsDB > gate {
                desired = target - rmsDB
                if desired > maxBoost { desired = maxBoost }
                if desired < maxCut { desired = maxCut }
            }
            let dLev = desired - gLevDB
            if dLev.magnitude < 1e-6 {
                gLevDB = desired
            } else {
                gLevDB += (dLev < 0 ? levA : levR) * dLev
            }
            let g1 = exp2(gLevDB * Self.db2lin2)
            xl *= g1
            xr *= g1

            let peak = xl.magnitude > xr.magnitude ? xl.magnitude : xr.magnitude
            var gc: Float = 0
            if peak > kneeLowLin {
                let over = log2(peak) * Self.lin2db2 - kneeLowDB
                if over < Self.compKneeDB {
                    gc = compSlope * over * over * kneeInv2W
                } else {
                    gc = compSlope * (over - halfKnee)
                }
            }
            let dGs = gc - gs
            if dGs < 0 {
                gs += compA * dGs
            } else if dGs.magnitude < 1e-5 {
                gs = gc
            } else {
                gs += compR * dGs
            }
            if gs != 0 {
                let g2 = exp2(gs * Self.db2lin2)
                xl *= g2
                xr *= g2
            }

            let pk = xl.magnitude > xr.magnitude ? xl.magnitude : xr.magnitude
            let req: Float = pk > 1 ? 1 / pk : 1
            while count > 0 {
                var back = head + count - 1
                if back >= dqCap { back -= dqCap }
                if dqVal[back] >= req { count -= 1 } else { break }
            }
            var slot = head + count
            if slot >= dqCap { slot -= dqCap }
            dqVal[slot] = req
            dqIdx[slot] = idx
            count += 1
            let expire = idx - look
            while count > 0 && dqIdx[head] < expire {
                head += 1
                if head == dqCap { head = 0 }
                count -= 1
            }
            let m = dqVal[head]
            env += limRel * (1 - env)
            if m < env { env = m }
            let old = avgBuf[aPos]
            avgBuf[aPos] = env
            aSum += Double(env) - Double(old)
            aPos += 1
            if aPos == avgCap {
                aPos = 0
                var s = 0.0
                for k in 0..<avgCap { s += Double(avgBuf[k]) }
                aSum = s
            }
            gLim = Float(aSum) * avgInv
            if gLim > 1 { gLim = 1 }
            let dl = delayL[dPos]
            let dr = delayR[dPos]
            delayL[dPos] = xl
            delayR[dPos] = xr
            dPos += 1
            if dPos == look { dPos = 0 }
            idx += 1

            let g = gLim * cs
            var ol = dl * g
            var orr = dr * g
            if ol > c { ol = c } else if ol < -c { ol = -c }
            if orr > c { orr = c } else if orr < -c { orr = -c }
            left[i] = ol
            right[i] = orr
        }

        meanSquare = ms
        levGainDB = gLevDB
        compGS = gs
        delayPos = dPos
        dqHead = head; dqCount = count
        sampleIndex = idx
        limEnv = env
        avgPos = aPos
        avgSum = aSum
        ceilSmooth = cs
        lastLimiterGain = gLim
        levelerGainDB = gLevDB
        compressorGainDB = gs
    }

    public func processInterleaved(_ buffer: UnsafeMutablePointer<Float>, frames: Int, ceiling: Float) {
        var off = 0
        while off < frames {
            let n = min(scratchCap, frames - off)
            let base = buffer + off * 2
            for i in 0..<n {
                scratchL[i] = base[2 * i]
                scratchR[i] = base[2 * i + 1]
            }
            process(left: scratchL, right: scratchR, frames: n, ceiling: ceiling)
            for i in 0..<n {
                base[2 * i] = scratchL[i]
                base[2 * i + 1] = scratchR[i]
            }
            off += n
        }
    }
}
