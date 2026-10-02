import Foundation
import SSMTRealtime

/// Swift wrapper over the C SPSC ring. `write` is real-time safe; everything else is for the consumer.
public final class RealtimeRing: @unchecked Sendable {
    public let raw: OpaquePointer
    public let channels: Int

    public init(minimumFrames: Int, channels: Int) {
        guard let r = ssmt_ring_create(UInt64(minimumFrames), UInt32(channels)) else {
            fatalError("Ring allocation failed")
        }
        raw = r
        self.channels = channels
    }

    deinit { ssmt_ring_destroy(raw) }

    public var capacity: Int { Int(ssmt_ring_capacity(raw)) }
    public var readable: Int { Int(ssmt_ring_readable(raw)) }
    public var overflowCount: UInt64 { ssmt_ring_overflow_count(raw) }
    public var totalWritten: UInt64 { ssmt_ring_total_written(raw) }

    /// Real-time safe write from planar channel pointers (nil → zeros).
    @inline(__always)
    public func write(_ channelPointers: UnsafePointer<UnsafePointer<Float>?>, frames: Int) -> Int {
        Int(ssmt_ring_write_planar(raw, channelPointers, UInt64(frames)))
    }

    /// Convenience (allocates): writes Swift arrays. For simulation and tests only.
    @discardableResult
    public func write(_ data: [[Float]]) -> Int {
        precondition(data.count == channels)
        let frames = data.map(\.count).min() ?? 0
        var ptrs: [UnsafePointer<Float>?] = []
        var result = 0
        func recurse(_ i: Int) {
            if i == data.count {
                result = ptrs.withUnsafeBufferPointer { write($0.baseAddress!, frames: frames) }
                return
            }
            data[i].withUnsafeBufferPointer { p in
                ptrs.append(p.baseAddress)
                recurse(i + 1)
            }
        }
        recurse(0)
        return result
    }

    /// Consumer: reads up to `maxFrames` into per-channel arrays.
    public func read(maxFrames: Int) -> [[Float]] {
        let n = min(maxFrames, readable)
        guard n > 0 else { return [[Float]](repeating: [], count: channels) }
        var flat = [Float](repeating: 0, count: n * channels)
        let got = flat.withUnsafeMutableBufferPointer { p -> Int in
            var ptrs: [UnsafeMutablePointer<Float>?] = (0..<channels).map { p.baseAddress! + $0 * n }
            return ptrs.withUnsafeMutableBufferPointer { Int(ssmt_ring_read_planar(raw, $0.baseAddress!, UInt64(n))) }
        }
        return (0..<channels).map { Array(flat[($0 * n)..<($0 * n + got)]) }
    }

    public func clear() { ssmt_ring_clear(raw) }
}

public final class AtomicBool: @unchecked Sendable {
    private let raw: OpaquePointer
    public init(_ v: Bool) { raw = ssmt_flag_create(v) }
    deinit { ssmt_flag_destroy(raw) }
    @inline(__always) public var value: Bool {
        get { ssmt_flag_load(raw) }
        set { ssmt_flag_store(raw, newValue) }
    }
}

public final class AtomicFloat: @unchecked Sendable {
    private let raw: OpaquePointer
    public init(_ v: Float) { raw = ssmt_float_create(v) }
    deinit { ssmt_float_destroy(raw) }
    @inline(__always) public var value: Float {
        get { ssmt_float_load(raw) }
        set { ssmt_float_store(raw, newValue) }
    }
}

public final class AtomicCounter: @unchecked Sendable {
    private let raw: OpaquePointer
    public init() { raw = ssmt_counter_create() }
    deinit { ssmt_counter_destroy(raw) }
    @inline(__always) public var value: UInt64 {
        get { ssmt_counter_load(raw) }
        set { ssmt_counter_store(raw, newValue) }
    }
    @inline(__always) @discardableResult public func increment(by d: UInt64 = 1) -> UInt64 { ssmt_counter_add(raw, d) }
}
