// PS5 host services that are not SDL's: dialogs, save sync and upscaling.
// None of them exist yet on the console; each takes the default the game can run with.
#include <atomic>
#include <cstdint>
#include <cstring>
#include <string>

#include <unistd.h>

#include "../platform.h"
#include "ps5_console.h"
#include "recomp/host.h"

namespace platform {

std::atomic<bool> g_prompt_open{false};

// Name entry: the on-screen keyboard (ps5_console.cpp). One at a time: the game asks again for
// every press of its button while the keyboard is up. The console's own text dialog is not
// reachable from a title (its modules cannot be loaded), so the game draws one itself.
bool prompt_text(const std::string&, const std::string&, const std::string& initial, std::string& result) {
    if (g_prompt_open.exchange(true)) return false;
    result = initial;
    const bool confirmed = ps5::keyboard_run(initial, 14, result);
    rt::log("platform: name entry %s: \"%s\"", confirmed ? "confirmed" : "cancelled", confirmed ? result.c_str() : initial.c_str());
    g_prompt_open = false;
    return confirmed;
}

// No two-button dialog yet: the first option.
int choose(const std::string& title, const std::string& message, const std::string&, const std::string&) {
    rt::log("platform: %s: %s (first option taken)", title.c_str(), message.c_str());
    return 0;
}

bool choose_folder(const std::string&, std::string&) { return false; }
void set_app_icon(const std::string&) {}  // the title folder carries its icon

void cloud_saves_start(const std::string&) {}
void cloud_saves_flush() {}

// No MetalFX here, but the graphics menu's extra Off/On row (shims/frontend/menu_patch.cpp) is wanted:
// on the console it switches DXVK's statistics display (frame rate, frame times, draw calls).
namespace {
std::atomic<bool> g_statistics{false};
}
void metalfx_init() {}
bool metalfx_supported() { return true; }
bool metalfx_enabled() { return g_statistics.load(std::memory_order_relaxed); }
void set_metalfx_enabled(bool on) { g_statistics.store(on, std::memory_order_relaxed); }

}  // namespace platform

// DXVK (the console build's swapchain blitter) asks this every frame.
extern "C" bool dirt2_ps5_hud_enabled() { return platform::metalfx_enabled(); }

// DXVK's overlay (the console build) draws the keyboard from these.
extern "C" bool dirt2_ps5_keyboard_active() { return ps5::keyboard_active(); }
extern "C" int dirt2_ps5_keyboard_state(char* out, int capacity, int* row, int* col) {
    return ps5::keyboard_state(out, capacity, row, col);
}
