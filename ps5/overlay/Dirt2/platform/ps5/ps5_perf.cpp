// Why a frame, or a stretch of frames, was slow: the PS5 title's frame-time diagnosis.
//
// The game's Present calls dirt2_ps5_perf_frame once per frame. Each call takes a snapshot:
// the clock, the processor time of the calling thread (the game's main thread), the
// counters DXVK reports (dirt2_ps5_dxvk_stats, called from its swap chain) and the bridge's
// own (buffers and textures created, exposure readback waits, cold-code lookups).
//
// Two kinds of lines go to the log, both starting with "perf:":
//
//   hitch    one frame much slower than the last 64: what happened during that frame alone
//            (at most 4 a second, 300 in a run) and the likely reason.
//   window   every 300 frames: frame-time percentiles, Present wait, GPU and DXVK thread load,
//            scene size (draw calls), how busy the main thread was, the likely reason, and, when the
//            window is slower than the best race-like one so far, what is different from it.
//
// "Likely reason" is a rule of thumb over those numbers, not a proof; the numbers are printed
// beside it so that it can be checked.
#include "recomp/host.h"

#if defined(__PROSPERO__)
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <time.h>

namespace {

using Clock = std::chrono::steady_clock;

// The order DXVK's hook reports in (D3D11SwapChain::reportFrameStats, patch 0009).
enum Dx { Draws, Passes, PipeGfx, PipeLib, PipeComp, Submits, GpuSyncN, GpuSyncUs, GpuIdleUs, CsSyncN, CsSyncUs,
          CsIdleUs, CsChunks, Barriers, DescSets, PipeDone, PipeTotal, kDx };
// The bridge's cumulative counters, in the order it passes them.
enum Ext { Buffers, Textures, ExpWaits, ExpWaitNs, SlowLookups, kExt };
constexpr int kWindow = 300;

uint64_t g_dx[kDx];  // DXVK's latest, written just before each frame call (same thread)

// Only the calling thread's processor time can be read on the console (the clock of another
// thread comes back as the caller's own), and the caller is the game's main thread, which is
// also the one that presents.
int64_t self_cpu_ns() {
    timespec t;
    if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t) != 0) return 0;
    return int64_t(t.tv_sec) * 1000000000 + t.tv_nsec;
}

struct Snap {
    Clock::time_point t;
    int64_t self_ns = 0;
    uint64_t dx[kDx] = {};
    uint64_t ext[kExt] = {};
};

void take(Snap& s, const uint64_t* ext) {
    s.t = Clock::now();
    s.self_ns = self_cpu_ns();
    std::memcpy(s.dx, g_dx, sizeof s.dx);
    std::memcpy(s.ext, ext, sizeof s.ext);
}

// Everything measured between two snapshots.
struct Metrics {
    double wall_ms = 0, present_ms = 0;
    uint32_t frames = 0;
    double gpu_busy = 0, cs_busy = 0, gpu_sync_ms = 0, exposure_ms = 0;
    uint64_t draws = 0, passes = 0, submits = 0, barriers = 0;
    uint64_t pipes = 0, backlog = 0, buffers = 0, textures = 0, slow = 0;
    double main_pct = 0;  // the main thread's share of one core, over the interval
};

uint64_t diff(const Snap& a, const Snap& b, Dx k) { return b.dx[k] >= a.dx[k] ? b.dx[k] - a.dx[k] : 0; }

Metrics measure(const Snap& a, const Snap& b, double present_ms, uint32_t frames) {
    Metrics m;
    m.frames = frames;
    m.present_ms = present_ms;
    const double wall_ns = std::chrono::duration<double, std::nano>(b.t - a.t).count();
    m.wall_ms = wall_ns / 1e6;
    const double wall_us = wall_ns / 1e3;
    // DXVK counts idle time in microseconds: busy is what is left of the wall time.
    m.gpu_busy = std::clamp(1.0 - double(diff(a, b, GpuIdleUs)) / wall_us, 0.0, 1.0);
    m.cs_busy = std::clamp(1.0 - double(diff(a, b, CsIdleUs)) / wall_us, 0.0, 1.0);
    m.gpu_sync_ms = diff(a, b, GpuSyncUs) / 1000.0;
    m.draws = diff(a, b, Draws);
    m.passes = diff(a, b, Passes);
    m.submits = diff(a, b, Submits);
    m.barriers = diff(a, b, Barriers);
    m.pipes = diff(a, b, PipeGfx) + diff(a, b, PipeComp);
    m.backlog = b.dx[PipeTotal] > b.dx[PipeDone] ? b.dx[PipeTotal] - b.dx[PipeDone] : 0;
    m.buffers = b.ext[Buffers] - a.ext[Buffers];
    m.textures = b.ext[Textures] - a.ext[Textures];
    m.slow = b.ext[SlowLookups] - a.ext[SlowLookups];
    m.exposure_ms = (b.ext[ExpWaitNs] - a.ext[ExpWaitNs]) / 1e6;

    m.main_pct = 100.0 * double(std::max<int64_t>(0, b.self_ns - a.self_ns)) / wall_ns;
    return m;
}

// The rules of thumb, strongest evidence first. For one frame the load limits are lower: a
// single frame cannot average out a busy thread.
std::string cause(const Metrics& m, bool one_frame) {
    std::vector<std::string> why;
    char buf[200];
    if (m.pipes > 0 || (one_frame && m.backlog > 0)) {
        std::snprintf(buf, sizeof buf, "pipeline compiling (%llu new pipelines, %llu compile tasks waiting)",
                      (unsigned long long)m.pipes, (unsigned long long)m.backlog);
        why.push_back(buf);
    }
    if (m.exposure_ms >= 0.35 * m.wall_ms && m.exposure_ms > 5) {
        std::snprintf(buf, sizeof buf, "the game waited %.1f ms for its exposure readback (the GPU result it reads back)", m.exposure_ms);
        why.push_back(buf);
    }
    if (m.gpu_busy >= 0.88) {
        std::snprintf(buf, sizeof buf, "GPU-bound (busy %.0f%% of the time)", 100 * m.gpu_busy);
        why.push_back(buf);
    } else if (m.gpu_sync_ms >= 0.25 * m.wall_ms) {
        std::snprintf(buf, sizeof buf, "the CPU waited %.1f ms for the GPU (a readback or sync)", m.gpu_sync_ms);
        why.push_back(buf);
    }
    const double load_limit = one_frame ? 75 : 85;
    if (m.main_pct >= load_limit) {
        std::snprintf(buf, sizeof buf, "CPU-bound on the game's main thread (%.0f%% of a core)", m.main_pct);
        why.push_back(buf);
    }
    if (m.slow >= (one_frame ? 300u : 100u * m.frames)) {
        std::snprintf(buf, sizeof buf, "cold code: %llu slow function lookups", (unsigned long long)m.slow);
        why.push_back(buf);
    }
    if (m.buffers + m.textures >= (one_frame ? 20u : 10u * m.frames)) {
        std::snprintf(buf, sizeof buf, "resource creation (%llu buffers, %llu textures)", (unsigned long long)m.buffers,
                      (unsigned long long)m.textures);
        why.push_back(buf);
    }
    if (why.empty() && m.present_ms >= 0.6 * m.wall_ms && m.gpu_busy < 0.88) {
        std::snprintf(buf, sizeof buf, "waiting in Present (%.0f%% of the time) while the GPU was not busy: display pacing", 100 * m.present_ms / m.wall_ms);
        why.push_back(buf);
    }
    if (why.empty()) {
        std::snprintf(buf, sizeof buf,
                      "neither the main thread (%.0f%% busy) nor the GPU (%.0f%%) was busy: the main thread was blocked "
                      "(a lock, a file read or a sleep)", m.main_pct, 100 * m.gpu_busy);
        why.push_back(buf);
    }
    std::string out;
    for (size_t i = 0; i < why.size() && i < 3; ++i) out += (i ? "; " : "") + why[i];
    return out;
}

double percentile(std::vector<double>& v, double p) {
    if (v.empty()) return 0;
    const size_t i = std::min(v.size() - 1, size_t(p * double(v.size())));
    std::nth_element(v.begin(), v.begin() + long(i), v.end());
    return v[i];
}

// The best race-like window so far, to say what is different about a slower one.
struct Baseline {
    bool set = false;
    double fps = 0, draws = 0, gpu = 0, cs = 0, main = 0, present = 0, backlog = 0;
    unsigned window = 0;
};

void report_window(const Snap& a, const Snap& b, std::vector<double>& frame_ms, double present_total, unsigned index, Baseline& base) {
    const Metrics m = measure(a, b, present_total, uint32_t(frame_ms.size()));
    const double f = double(m.frames);
    double sum = 0, worst = 0;
    unsigned over25 = 0, over50 = 0;
    for (double ms : frame_ms) {
        sum += ms;
        worst = std::max(worst, ms);
        over25 += ms > 25;
        over50 += ms > 50;
    }
    const double fps = 1000.0 * f / m.wall_ms;
    const double p50 = percentile(frame_ms, 0.5), p95 = percentile(frame_ms, 0.95), p99 = percentile(frame_ms, 0.99);
    rt::log("perf: window %u: %.1f fps; frame ms avg %.1f p50 %.1f p95 %.1f p99 %.1f max %.0f; %u over 25 ms, %u over 50 ms", index, fps,
            sum / f, p50, p95, p99, worst, over25, over50);
    rt::log("perf: present wait %.1f ms/frame (%.0f%% of the frame); GPU busy %.0f%%; DXVK command thread busy %.0f%%; CPU waited for GPU %.1f ms/frame",
            m.present_ms / f, 100 * m.present_ms / m.wall_ms, 100 * m.gpu_busy, 100 * m.cs_busy, m.gpu_sync_ms / f);
    rt::log("perf: scene %.0f draws, %.0f render passes, %.0f submits, %.0f barriers per frame; +%llu pipelines, %llu compile tasks waiting; "
            "+%llu buffers, +%llu textures, %llu slow lookups, exposure wait %.1f ms/frame",
            m.draws / f, m.passes / f, m.submits / f, m.barriers / f, (unsigned long long)m.pipes, (unsigned long long)m.backlog,
            (unsigned long long)m.buffers, (unsigned long long)m.textures, (unsigned long long)m.slow, m.exposure_ms / f);
    rt::log("perf: main thread (game logic and rendering calls) busy %.0f%% of the frame", m.main_pct);
    std::string why = cause(m, false);
    if (p50 > 31 && p50 < 36) why += "; frames land on 33 ms steps (a 60 Hz frame missed each time)";
    rt::log("perf: likely reason: %s", why.c_str());

    const bool race_like = m.draws / f >= 300;
    if (base.set && race_like && fps < 0.85 * base.fps) {
        char line[600];
        int n = std::snprintf(line, sizeof line, "perf: slower than the best race-like window (%u: %.1f fps), by %.0f%%; differences:", base.window,
                              base.fps, 100 * (1 - fps / base.fps));
        // Shown when the value moved by a fifth or more, and by at least min_abs.
        auto cmp = [&](const char* name, double now, double then, double min_abs, const char* unit) {
            if (n >= int(sizeof line) - 80) return;
            const double d = std::abs(now - then);
            if (d < min_abs || d < 0.20 * then) return;
            n += std::snprintf(line + n, sizeof line - n, " %s %.0f%s (was %.0f%s);", name, now, unit, then, unit);
        };
        cmp("draws/frame", m.draws / f, base.draws, 1, "");
        cmp("GPU busy", 100 * m.gpu_busy, base.gpu, 5, "%");
        cmp("DXVK command thread", 100 * m.cs_busy, base.cs, 5, "%");
        cmp("main thread", m.main_pct, base.main, 5, "%");
        cmp("Present wait", 100 * m.present_ms / m.wall_ms, base.present, 5, "%");
        cmp("compile tasks waiting", double(m.backlog), base.backlog, 1, "");
        rt::log("%s", line);
    }
    if (race_like && fps > base.fps) {
        base = Baseline{true, fps, m.draws / f, 100 * m.gpu_busy, 100 * m.cs_busy, m.main_pct, 100 * m.present_ms / m.wall_ms, double(m.backlog), index};
    }
}

void report_hitch(const Snap& a, const Snap& b, double present_ms, double typical_ms, unsigned count) {
    const Metrics m = measure(a, b, present_ms, 1);
    rt::log("perf: hitch %u: frame %.1f ms (typical %.1f); Present %.1f ms; GPU busy %.0f%%; %llu draws; +%llu pipelines, %llu compile tasks waiting; "
            "+%llu buffers, +%llu textures, %llu slow lookups, exposure wait %.1f ms; main thread busy %.0f%%",
            count, m.wall_ms, typical_ms, present_ms, 100 * m.gpu_busy, (unsigned long long)m.draws, (unsigned long long)m.pipes,
            (unsigned long long)m.backlog, (unsigned long long)m.buffers, (unsigned long long)m.textures, (unsigned long long)m.slow,
            m.exposure_ms, m.main_pct);
    rt::log("perf: hitch %u likely reason: %s", count, cause(m, true).c_str());
}

}  // namespace

extern "C" void dirt2_ps5_dxvk_stats(const uint64_t* values, int count) {
    std::memcpy(g_dx, values, sizeof(uint64_t) * size_t(std::min(count, int(kDx))));
}

// ext: buffers created, textures created, exposure waits, exposure wait ns, slow lookups (all cumulative).
extern "C" void dirt2_ps5_perf_frame(double present_ms, const uint64_t* ext) {
    static bool started = false;
    static Snap prev, cur, window_start;
    static std::vector<double> frames;
    static double ring[64];
    static unsigned ring_n = 0, window_index = 0, hitches = 0, hitch_second = 0, hitches_this_second = 0;
    static double window_present = 0;
    static Baseline base;
    static Clock::time_point t0;
    take(cur, ext);
    if (!started) {
        started = true;
        prev = window_start = cur;
        t0 = cur.t;
        frames.reserve(kWindow);
        return;
    }
    const double ms = std::chrono::duration<double, std::milli>(cur.t - prev.t).count();

    // One frame far slower than the last 64: say what it was.
    double typical = 0;
    if (ring_n >= 16) {
        double sorted[64];
        const unsigned n = std::min(ring_n, 64u);
        std::memcpy(sorted, ring, sizeof(double) * n);
        std::nth_element(sorted, sorted + n / 2, sorted + n);
        typical = sorted[n / 2];
    }
    if (typical > 0 && ms > 40 && ms > 1.8 * typical && hitches < 300) {
        const unsigned second = unsigned(std::chrono::duration_cast<std::chrono::seconds>(cur.t - t0).count());
        if (second != hitch_second) { hitch_second = second; hitches_this_second = 0; }
        if (hitches_this_second++ < 4) report_hitch(prev, cur, present_ms, typical, ++hitches);
    }
    ring[ring_n++ % 64] = ms;
    frames.push_back(ms);
    window_present += present_ms;
    prev = cur;
    if (frames.size() >= size_t(kWindow)) {
        report_window(window_start, cur, frames, window_present, ++window_index, base);
        frames.clear();
        window_present = 0;
        window_start = cur;
    }
}
#endif
