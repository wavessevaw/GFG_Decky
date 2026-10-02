#ifndef SSMT_REALTIME_H
#define SSMT_REALTIME_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Single-producer / single-consumer ring buffer of interleaved float frames.
/// The producer (audio thread) never allocates, locks or blocks.
typedef struct SSMTRingBuffer SSMTRingBuffer;

/// Creates a ring with room for at least `minFrames` frames (rounded up to a power of two).
SSMTRingBuffer *ssmt_ring_create(uint64_t minFrames, uint32_t channels);
void ssmt_ring_destroy(SSMTRingBuffer *ring);

uint32_t ssmt_ring_channels(const SSMTRingBuffer *ring);
uint64_t ssmt_ring_capacity(const SSMTRingBuffer *ring);

/// Producer: writes `frames` frames from planar channel pointers (`channels[c]` may be NULL → zeros).
/// If the ring is full the excess frames are dropped and counted as overflow. Returns frames written.
uint64_t ssmt_ring_write_planar(SSMTRingBuffer *ring, const float *const *channels, uint64_t frames);

/// Consumer: number of frames ready to read.
uint64_t ssmt_ring_readable(const SSMTRingBuffer *ring);

/// Consumer: reads up to `frames` frames into planar destination buffers. Returns frames read.
uint64_t ssmt_ring_read_planar(SSMTRingBuffer *ring, float *const *channels, uint64_t frames);

/// Total frames ever written (monotonic) and frames dropped because of overflow.
uint64_t ssmt_ring_total_written(const SSMTRingBuffer *ring);
uint64_t ssmt_ring_overflow_count(const SSMTRingBuffer *ring);

/// Consumer: discards everything currently readable.
void ssmt_ring_clear(SSMTRingBuffer *ring);

/// Atomic boolean / counter usable from both the audio thread and Swift.
typedef struct SSMTAtomicFlag SSMTAtomicFlag;
SSMTAtomicFlag *ssmt_flag_create(bool initial);
void ssmt_flag_destroy(SSMTAtomicFlag *flag);
bool ssmt_flag_load(const SSMTAtomicFlag *flag);
void ssmt_flag_store(SSMTAtomicFlag *flag, bool value);

typedef struct SSMTAtomicCounter SSMTAtomicCounter;
SSMTAtomicCounter *ssmt_counter_create(void);
void ssmt_counter_destroy(SSMTAtomicCounter *counter);
uint64_t ssmt_counter_load(const SSMTAtomicCounter *counter);
void ssmt_counter_store(SSMTAtomicCounter *counter, uint64_t value);
uint64_t ssmt_counter_add(SSMTAtomicCounter *counter, uint64_t delta);

/// Atomic float stored as bits (relaxed); used for meters and gain targets.
typedef struct SSMTAtomicFloat SSMTAtomicFloat;
SSMTAtomicFloat *ssmt_float_create(float initial);
void ssmt_float_destroy(SSMTAtomicFloat *value);
float ssmt_float_load(const SSMTAtomicFloat *value);
void ssmt_float_store(SSMTAtomicFloat *value, float newValue);
/// Stores max(current, candidate). Returns the resulting value.
float ssmt_float_store_max(SSMTAtomicFloat *value, float candidate);

#ifdef __cplusplus
}
#endif

#endif
