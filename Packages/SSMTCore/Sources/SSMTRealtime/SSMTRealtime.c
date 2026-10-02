#include "SSMTRealtime.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct SSMTRingBuffer {
    float *data;
    uint64_t capacity; // frames, power of two
    uint64_t mask;
    uint32_t channels;
    _Atomic uint64_t writeIndex; // frames, monotonic
    _Atomic uint64_t readIndex;  // frames, monotonic
    _Atomic uint64_t overflow;
};

static uint64_t next_pow2(uint64_t v) {
    uint64_t p = 1;
    while (p < v) p <<= 1;
    return p;
}

SSMTRingBuffer *ssmt_ring_create(uint64_t minFrames, uint32_t channels) {
    if (channels == 0 || minFrames == 0) return NULL;
    SSMTRingBuffer *ring = calloc(1, sizeof(SSMTRingBuffer));
    if (!ring) return NULL;
    ring->capacity = next_pow2(minFrames);
    ring->mask = ring->capacity - 1;
    ring->channels = channels;
    ring->data = calloc(ring->capacity * channels, sizeof(float));
    if (!ring->data) {
        free(ring);
        return NULL;
    }
    atomic_init(&ring->writeIndex, 0);
    atomic_init(&ring->readIndex, 0);
    atomic_init(&ring->overflow, 0);
    return ring;
}

void ssmt_ring_destroy(SSMTRingBuffer *ring) {
    if (!ring) return;
    free(ring->data);
    free(ring);
}

uint32_t ssmt_ring_channels(const SSMTRingBuffer *ring) { return ring->channels; }
uint64_t ssmt_ring_capacity(const SSMTRingBuffer *ring) { return ring->capacity; }

uint64_t ssmt_ring_write_planar(SSMTRingBuffer *ring, const float *const *channels, uint64_t frames) {
    uint64_t w = atomic_load_explicit(&ring->writeIndex, memory_order_relaxed);
    uint64_t r = atomic_load_explicit(&ring->readIndex, memory_order_acquire);
    uint64_t space = ring->capacity - (w - r);
    uint64_t n = frames < space ? frames : space;
    if (n < frames) {
        atomic_fetch_add_explicit(&ring->overflow, frames - n, memory_order_relaxed);
    }
    const uint32_t ch = ring->channels;
    for (uint64_t i = 0; i < n; i++) {
        float *dst = ring->data + ((w + i) & ring->mask) * ch;
        for (uint32_t c = 0; c < ch; c++) {
            const float *src = channels[c];
            dst[c] = src ? src[i] : 0.0f;
        }
    }
    atomic_store_explicit(&ring->writeIndex, w + n, memory_order_release);
    return n;
}

uint64_t ssmt_ring_readable(const SSMTRingBuffer *ring) {
    uint64_t w = atomic_load_explicit(&((SSMTRingBuffer *)ring)->writeIndex, memory_order_acquire);
    uint64_t r = atomic_load_explicit(&((SSMTRingBuffer *)ring)->readIndex, memory_order_relaxed);
    return w - r;
}

uint64_t ssmt_ring_read_planar(SSMTRingBuffer *ring, float *const *channels, uint64_t frames) {
    uint64_t r = atomic_load_explicit(&ring->readIndex, memory_order_relaxed);
    uint64_t w = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    uint64_t avail = w - r;
    uint64_t n = frames < avail ? frames : avail;
    const uint32_t ch = ring->channels;
    for (uint64_t i = 0; i < n; i++) {
        const float *src = ring->data + ((r + i) & ring->mask) * ch;
        for (uint32_t c = 0; c < ch; c++) {
            if (channels[c]) channels[c][i] = src[c];
        }
    }
    atomic_store_explicit(&ring->readIndex, r + n, memory_order_release);
    return n;
}

uint64_t ssmt_ring_total_written(const SSMTRingBuffer *ring) {
    return atomic_load_explicit(&((SSMTRingBuffer *)ring)->writeIndex, memory_order_acquire);
}

uint64_t ssmt_ring_overflow_count(const SSMTRingBuffer *ring) {
    return atomic_load_explicit(&((SSMTRingBuffer *)ring)->overflow, memory_order_relaxed);
}

void ssmt_ring_clear(SSMTRingBuffer *ring) {
    uint64_t w = atomic_load_explicit(&ring->writeIndex, memory_order_acquire);
    atomic_store_explicit(&ring->readIndex, w, memory_order_release);
}

struct SSMTAtomicFlag { _Atomic bool value; };

SSMTAtomicFlag *ssmt_flag_create(bool initial) {
    SSMTAtomicFlag *f = malloc(sizeof(SSMTAtomicFlag));
    if (f) atomic_init(&f->value, initial);
    return f;
}
void ssmt_flag_destroy(SSMTAtomicFlag *flag) { free(flag); }
bool ssmt_flag_load(const SSMTAtomicFlag *flag) {
    return atomic_load_explicit(&((SSMTAtomicFlag *)flag)->value, memory_order_acquire);
}
void ssmt_flag_store(SSMTAtomicFlag *flag, bool value) {
    atomic_store_explicit(&flag->value, value, memory_order_release);
}

struct SSMTAtomicCounter { _Atomic uint64_t value; };

SSMTAtomicCounter *ssmt_counter_create(void) {
    SSMTAtomicCounter *c = malloc(sizeof(SSMTAtomicCounter));
    if (c) atomic_init(&c->value, 0);
    return c;
}
void ssmt_counter_destroy(SSMTAtomicCounter *counter) { free(counter); }
uint64_t ssmt_counter_load(const SSMTAtomicCounter *counter) {
    return atomic_load_explicit(&((SSMTAtomicCounter *)counter)->value, memory_order_acquire);
}
void ssmt_counter_store(SSMTAtomicCounter *counter, uint64_t value) {
    atomic_store_explicit(&counter->value, value, memory_order_release);
}
uint64_t ssmt_counter_add(SSMTAtomicCounter *counter, uint64_t delta) {
    return atomic_fetch_add_explicit(&counter->value, delta, memory_order_acq_rel) + delta;
}

struct SSMTAtomicFloat { _Atomic uint32_t bits; };

static uint32_t float_bits(float f) { uint32_t b; memcpy(&b, &f, sizeof b); return b; }
static float bits_float(uint32_t b) { float f; memcpy(&f, &b, sizeof f); return f; }

SSMTAtomicFloat *ssmt_float_create(float initial) {
    SSMTAtomicFloat *v = malloc(sizeof(SSMTAtomicFloat));
    if (v) atomic_init(&v->bits, float_bits(initial));
    return v;
}
void ssmt_float_destroy(SSMTAtomicFloat *value) { free(value); }
float ssmt_float_load(const SSMTAtomicFloat *value) {
    return bits_float(atomic_load_explicit(&((SSMTAtomicFloat *)value)->bits, memory_order_relaxed));
}
void ssmt_float_store(SSMTAtomicFloat *value, float newValue) {
    atomic_store_explicit(&value->bits, float_bits(newValue), memory_order_relaxed);
}
float ssmt_float_store_max(SSMTAtomicFloat *value, float candidate) {
    uint32_t cur = atomic_load_explicit(&value->bits, memory_order_relaxed);
    for (;;) {
        float curF = bits_float(cur);
        if (!(candidate > curF)) return curF;
        if (atomic_compare_exchange_weak_explicit(&value->bits, &cur, float_bits(candidate),
                                                  memory_order_relaxed, memory_order_relaxed)) {
            return candidate;
        }
    }
}

struct SSMTPointerQueue {
    void **items;
    uint64_t capacity; // power of two
    uint64_t mask;
    _Atomic uint64_t head; // next write, monotonic
    _Atomic uint64_t tail; // next read, monotonic
};

SSMTPointerQueue *ssmt_ptrq_create(uint32_t minCapacity) {
    if (minCapacity == 0) return NULL;
    SSMTPointerQueue *q = calloc(1, sizeof(SSMTPointerQueue));
    if (!q) return NULL;
    q->capacity = next_pow2(minCapacity);
    q->mask = q->capacity - 1;
    q->items = calloc(q->capacity, sizeof(void *));
    if (!q->items) {
        free(q);
        return NULL;
    }
    atomic_init(&q->head, 0);
    atomic_init(&q->tail, 0);
    return q;
}

void ssmt_ptrq_destroy(SSMTPointerQueue *queue) {
    if (!queue) return;
    free(queue->items);
    free(queue);
}

bool ssmt_ptrq_push(SSMTPointerQueue *queue, void *item) {
    uint64_t h = atomic_load_explicit(&queue->head, memory_order_relaxed);
    uint64_t t = atomic_load_explicit(&queue->tail, memory_order_acquire);
    if (h - t >= queue->capacity) return false;
    queue->items[h & queue->mask] = item;
    atomic_store_explicit(&queue->head, h + 1, memory_order_release);
    return true;
}

void *ssmt_ptrq_pop(SSMTPointerQueue *queue) {
    uint64_t t = atomic_load_explicit(&queue->tail, memory_order_relaxed);
    uint64_t h = atomic_load_explicit(&queue->head, memory_order_acquire);
    if (t == h) return NULL;
    void *item = queue->items[t & queue->mask];
    atomic_store_explicit(&queue->tail, t + 1, memory_order_release);
    return item;
}
