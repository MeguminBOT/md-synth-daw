/**
 * The window, the renderer and the clock, through SDL3.
 *
 * Windows defaults to direct3d11, and a flag or a setting names another. The vulkan
 * backend is given two things the others are not, a wait for its device after every
 * present and adaptive vsync, because without them it draws single frames with
 * another frame's vertices and shows a frame from two presents earlier.
 *
 * The clock is at full precision and the sleep asks the operating system for a fine
 * enough scheduler tick first, because a timestamp rounded to whole milliseconds is
 * useless for a frame of 16.688 of them and an unimproved sleep quantises to 15.6.
 */
#include "window.h"

#include <SDL3/SDL_vulkan.h>

#ifdef _WIN32
#include <windows.h>
#endif

#if defined(__APPLE__)
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#elif defined(__linux__) && !defined(__ANDROID__)
#include <cstdio>
#include <cstdlib>
#include <cstring>
#endif

/**
 * The calling convention vulkan's entry points use, which is only different from the
 * default on 32 bit Windows.
 */
#if defined(_WIN32) && !defined(_WIN64)
#define MDD_VKAPI __stdcall
#else
#define MDD_VKAPI
#endif

/**
 * Any vulkan entry point, as the loader hands one back.
 */
typedef void (MDD_VKAPI *mdd_vk_function)(void);

/**
 * vkGetInstanceProcAddr, which finds an entry point by name for an instance.
 */
typedef mdd_vk_function (MDD_VKAPI *mdd_vk_instance_proc)(void *instance, const char *name);

/**
 * vkDeviceWaitIdle, which returns once a device has finished everything submitted to it.
 */
typedef int (MDD_VKAPI *mdd_vk_device_wait)(void *device);

/**
 * Where the renderer's own properties keep the instance the wait below was looked up
 * for, and the wait itself.
 */
#define MDD_VULKAN_INSTANCE "mdd.vulkan.instance"
#define MDD_VULKAN_WAIT "mdd.vulkan.wait"

/**
 * Waits for the vulkan renderer's device to finish everything submitted to it, and
 * does nothing on any other backend.
 *
 * SDL's vulkan renderer copies each frame's vertices into one set of mapped buffers
 * starting from the first again every frame, and before recording the next frame it
 * waits only for the frame as many presents back as the swap chain has images. A
 * frame it has submitted can still be waiting for its image when the next one is
 * copied over its vertices, and it is then drawn with the next frame's vertices and
 * its own draw calls: every quad after the first place the two frames differ lands
 * on another quad's corners and texture coordinates, which is read as wrong glyphs
 * and flicker whenever the interface is changing. Waiting here keeps one frame in
 * flight, so the copy never lands on vertices a frame still needs.
 *
 * The instance and the device are read each time, because SDL makes new ones when it
 * recovers a lost device, and the wait is looked up again when the instance changes.
 *
 * @param renderer The renderer.
 */
static void mdd_vulkan_settle(SDL_Renderer *renderer) {
	const char *name = SDL_GetRendererName(renderer);
	if (name == nullptr || SDL_strcmp(name, "vulkan") != 0) return;

	const SDL_PropertiesID props = SDL_GetRendererProperties(renderer);
	void *instance = SDL_GetPointerProperty(props, SDL_PROP_RENDERER_VULKAN_INSTANCE_POINTER, nullptr);
	void *device = SDL_GetPointerProperty(props, SDL_PROP_RENDERER_VULKAN_DEVICE_POINTER, nullptr);
	if (instance == nullptr || device == nullptr) return;

	void *wait = SDL_GetPointerProperty(props, MDD_VULKAN_WAIT, nullptr);

	if (wait == nullptr || SDL_GetPointerProperty(props, MDD_VULKAN_INSTANCE, nullptr) != instance) {
		const mdd_vk_instance_proc lookup = (mdd_vk_instance_proc)SDL_Vulkan_GetVkGetInstanceProcAddr();
		if (lookup == nullptr) return;

		wait = (void *)lookup(instance, "vkDeviceWaitIdle");
		SDL_SetPointerProperty(props, MDD_VULKAN_INSTANCE, instance);
		SDL_SetPointerProperty(props, MDD_VULKAN_WAIT, wait);
	}

	if (wait != nullptr) ((mdd_vk_device_wait)wait)(device);
}

extern "C" int mdd_sdl_init(void) {
	SDL_SetHint(SDL_HINT_WINDOWS_CLOSE_ON_ALT_F4, "0");
	return SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) ? 1 : 0;
}

extern "C" void mdd_sdl_quit(void) {
	SDL_Quit();
}

extern "C" const char *mdd_sdl_error(void) {
	return SDL_GetError();
}

extern "C" SDL_Window *mdd_window_create(const char *title, int width, int height, int resizable,
		int highDpi) {
	SDL_WindowFlags flags = SDL_WINDOW_HIDDEN;
	if (resizable != 0) flags |= SDL_WINDOW_RESIZABLE;
	if (highDpi != 0) flags |= SDL_WINDOW_HIGH_PIXEL_DENSITY;

	return SDL_CreateWindow(title, width, height, flags);
}

extern "C" void mdd_window_destroy(SDL_Window *window) {
	if (window != nullptr) SDL_DestroyWindow(window);
}

extern "C" unsigned int mdd_window_id(SDL_Window *window) {
	return window == nullptr ? 0 : SDL_GetWindowID(window);
}

extern "C" void mdd_window_set_title(SDL_Window *window, const char *title) {
	if (window != nullptr) SDL_SetWindowTitle(window, title);
}

extern "C" int mdd_window_width(SDL_Window *window) {
	int width = 0;
	int height = 0;
	if (window != nullptr) SDL_GetWindowSize(window, &width, &height);
	return width;
}

extern "C" int mdd_window_height(SDL_Window *window) {
	int width = 0;
	int height = 0;
	if (window != nullptr) SDL_GetWindowSize(window, &width, &height);
	return height;
}

extern "C" int mdd_window_pixel_width(SDL_Window *window) {
	int width = 0;
	int height = 0;
	if (window != nullptr) SDL_GetWindowSizeInPixels(window, &width, &height);
	return width;
}

extern "C" int mdd_window_pixel_height(SDL_Window *window) {
	int width = 0;
	int height = 0;
	if (window != nullptr) SDL_GetWindowSizeInPixels(window, &width, &height);
	return height;
}

extern "C" void mdd_window_set_size(SDL_Window *window, int width, int height) {
	if (window != nullptr) SDL_SetWindowSize(window, width, height);
}

extern "C" void mdd_window_set_minimum_size(SDL_Window *window, int width, int height) {
	if (window != nullptr) SDL_SetWindowMinimumSize(window, width, height);
}

extern "C" void mdd_window_set_fullscreen(SDL_Window *window, int on) {
	if (window != nullptr) SDL_SetWindowFullscreen(window, on != 0);
}

extern "C" void mdd_window_show(SDL_Window *window) {
	if (window != nullptr) SDL_ShowWindow(window);
}

extern "C" void mdd_window_maximise(SDL_Window *window) {
	if (window != nullptr) SDL_MaximizeWindow(window);
}

extern "C" void mdd_window_raise(SDL_Window *window) {
	if (window == nullptr) return;

	if ((SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) != 0) SDL_RestoreWindow(window);
	SDL_RaiseWindow(window);
}

extern "C" int mdd_window_maximised(SDL_Window *window) {
	if (window == nullptr) return 0;
	return (SDL_GetWindowFlags(window) & SDL_WINDOW_MAXIMIZED) != 0 ? 1 : 0;
}

extern "C" float mdd_window_display_scale(SDL_Window *window) {
	if (window == nullptr) return 1.0f;
	const float scale = SDL_GetWindowDisplayScale(window);
	return scale > 0.0f ? scale : 1.0f;
}

extern "C" float mdd_display_pixel_density(SDL_Window *window) {
	if (window == nullptr) return 1.0f;
	const float density = SDL_GetWindowPixelDensity(window);
	return density > 0.0f ? density : 1.0f;
}

extern "C" int mdd_render_output_width(SDL_Renderer *renderer) {
	int width = 0;
	int height = 0;
	if (renderer != nullptr) SDL_GetCurrentRenderOutputSize(renderer, &width, &height);
	return width;
}

extern "C" int mdd_render_output_height(SDL_Renderer *renderer) {
	int width = 0;
	int height = 0;
	if (renderer != nullptr) SDL_GetCurrentRenderOutputSize(renderer, &width, &height);
	return height;
}

extern "C" float mdd_display_refresh(SDL_Window *window) {
	if (window == nullptr) return 60.0f;

	const SDL_DisplayMode *mode = SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(window));
	if (mode == nullptr || mode->refresh_rate <= 0.0f) return 60.0f;
	return mode->refresh_rate;
}

extern "C" void mdd_text_input_start(SDL_Window *window) {
	if (window != nullptr) SDL_StartTextInput(window);
}

extern "C" void mdd_text_input_stop(SDL_Window *window) {
	if (window != nullptr) SDL_StopTextInput(window);
}

extern "C" int mdd_render_drivers() {
	const int many = SDL_GetNumRenderDrivers();
	return many < 0 ? 0 : many;
}

extern "C" const char *mdd_render_driver(int index) {
	if (index < 0 || index >= SDL_GetNumRenderDrivers()) return "";

	const char *name = SDL_GetRenderDriver(index);
	return name == nullptr ? "" : name;
}

/**
 * The vsync setting a renderer is given.
 *
 * On the vulkan backend a synchronised swap chain is asked for with adaptive vsync,
 * which SDL turns into the relaxed FIFO present mode, rather than the strict one. Under
 * strict FIFO a window on Windows was seen showing the image from two presents earlier
 * for one refresh, about a dozen times a minute, measured on screen and never on direct3d11,
 * direct3d12 or opengl; under relaxed FIFO it did not happen at all. Relaxed FIFO still
 * waits for the display, and only presents at once when a frame is already late.
 *
 * @param renderer The renderer.
 * @param vsync Nonzero to wait for the display.
 * @return What to pass SDL_SetRenderVSync.
 */
static int mdd_vsync_for(SDL_Renderer *renderer, int vsync) {
	if (vsync == 0) return SDL_RENDERER_VSYNC_DISABLED;

	const char *name = SDL_GetRendererName(renderer);
	return name != nullptr && SDL_strcmp(name, "vulkan") == 0 ? SDL_RENDERER_VSYNC_ADAPTIVE : 1;
}

extern "C" SDL_Renderer *mdd_renderer_create(SDL_Window *window, int vsync, const char *driver) {
	const char *wanted = driver == nullptr || driver[0] == 0 ? nullptr : driver;

	SDL_Renderer *renderer = SDL_CreateRenderer(window, wanted);

	if (renderer == nullptr && wanted != nullptr) renderer = SDL_CreateRenderer(window, nullptr);
	if (renderer == nullptr) return nullptr;

	SDL_SetRenderVSync(renderer, mdd_vsync_for(renderer, vsync));
	SDL_SetRenderLogicalPresentation(renderer, 0, 0, SDL_LOGICAL_PRESENTATION_DISABLED);
	SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
	return renderer;
}

extern "C" void mdd_renderer_destroy(SDL_Renderer *renderer) {
	if (renderer != nullptr) SDL_DestroyRenderer(renderer);
}

extern "C" const char *mdd_renderer_name(SDL_Renderer *renderer) {
	if (renderer == nullptr) return "";
	const char *name = SDL_GetRendererName(renderer);
	return name == nullptr ? "" : name;
}

extern "C" int mdd_renderer_vsync(SDL_Renderer *renderer) {
	int vsync = 0;
	if (renderer != nullptr && SDL_GetRenderVSync(renderer, &vsync)) return vsync;
	return 0;
}

extern "C" void mdd_render_clear(SDL_Renderer *renderer, float r, float g, float b, float a) {
	if (renderer == nullptr) return;
	SDL_SetRenderDrawColorFloat(renderer, r, g, b, a);
	SDL_RenderClear(renderer);
}

extern "C" void mdd_render_present(SDL_Renderer *renderer) {
	if (renderer == nullptr) return;

	SDL_RenderPresent(renderer);
	mdd_vulkan_settle(renderer);
}

extern "C" void mdd_set_clip(SDL_Renderer *renderer, int x, int y, int width, int height) {
	if (renderer == nullptr) return;
	SDL_Rect rect;
	rect.x = x;
	rect.y = y;
	rect.w = width < 0 ? 0 : width;
	rect.h = height < 0 ? 0 : height;
	SDL_SetRenderClipRect(renderer, &rect);
}

extern "C" void mdd_clear_clip(SDL_Renderer *renderer) {
	if (renderer != nullptr) SDL_SetRenderClipRect(renderer, nullptr);
}

#if defined(__linux__) && !defined(__ANDROID__)

/**
 * Runs a command and keeps the start of what it prints.
 *
 * @param command The command, for the shell, its errors sent nowhere.
 * @param out Where what it printed goes, always ended.
 * @param room How many bytes out holds.
 * @return Nonzero where it printed anything.
 */
static int mdd_asked(const char *command, char *out, int room) {
	out[0] = 0;

	FILE *pipe = popen(command, "r");
	if (pipe == nullptr) return 0;

	const size_t held = fread(out, 1, (size_t)(room - 1), pipe);
	pclose(pipe);

	out[held] = 0;
	return held > 0 ? 1 : 0;
}

/**
 * @return Nonzero where KDE's animation speed is set to nought, which is how it turns them off,
 *     and -1 where it says nothing.
 */
static int mdd_reduce_motion_kde(void) {
	char said[64];

	if (!mdd_asked("kreadconfig6 --group KDE --key AnimationDurationFactor 2>/dev/null", said, sizeof(said))
			&& !mdd_asked("kreadconfig5 --group KDE --key AnimationDurationFactor 2>/dev/null", said,
				sizeof(said))) {
		return -1;
	}

	char *end = nullptr;
	const double factor = std::strtod(said, &end);

	return end == said ? -1 : (factor <= 0 ? 1 : 0);
}

/**
 * @return Nonzero where GNOME's animations are turned off, and -1 where it says nothing.
 */
static int mdd_reduce_motion_gnome(void) {
	char said[64];

	if (!mdd_asked("gsettings get org.gnome.desktop.interface enable-animations 2>/dev/null", said,
			sizeof(said))) {
		return -1;
	}

	if (std::strncmp(said, "false", 5) == 0) return 1;
	if (std::strncmp(said, "true", 4) == 0) return 0;

	return -1;
}

#endif

extern "C" int mdd_reduce_motion(void) {
#if defined(_WIN32)
	BOOL animate = TRUE;
	if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animate, 0) != 0) {
		return animate != FALSE ? 0 : 1;
	}
	return 0;
#elif defined(__APPLE__)
	Class workspace = objc_getClass("NSWorkspace");
	if (workspace == nullptr) return 0;

	id shared = ((id (*)(Class, SEL))objc_msgSend)(workspace, sel_registerName("sharedWorkspace"));
	SEL asks = sel_registerName("accessibilityDisplayShouldReduceMotion");

	if (shared == nullptr || !class_respondsToSelector(object_getClass(shared), asks)) return 0;

	return ((BOOL (*)(id, SEL))objc_msgSend)(shared, asks) ? 1 : 0;
#elif defined(__linux__) && !defined(__ANDROID__)
	const char *desktop = std::getenv("XDG_CURRENT_DESKTOP");
	const bool kde = desktop != nullptr && std::strstr(desktop, "KDE") != nullptr;

	int said = kde ? mdd_reduce_motion_kde() : mdd_reduce_motion_gnome();
	if (said < 0) said = kde ? mdd_reduce_motion_gnome() : mdd_reduce_motion_kde();

	return said > 0 ? 1 : 0;
#else
	return 0;
#endif
}

extern "C" void mdd_sleep(double seconds) {
	if (seconds <= 0.0) return;
	SDL_DelayNS(static_cast<Uint64>(seconds * 1000000000.0));
}

extern "C" double mdd_ticks(void) {
	return static_cast<double>(SDL_GetTicksNS()) / 1000000000.0;
}

extern "C" void mdd_message(const char *title, const char *said) {
	SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION, title, said, NULL);
}

extern "C" void mdd_fault(const char *title, const char *said) {
	SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, title, said, NULL);
}

extern "C" int mdd_ask(const char *title, const char *said, const char *first, const char *second,
	const char *third, const char *fourth, int fault) {
	const char *names[4] = {first, second, third, fourth};
	SDL_MessageBoxButtonData buttons[4];
	int count = 0;

	for (int at = 0; at < 4; at++) {
		if (names[at] == NULL || names[at][0] == 0) continue;

		buttons[count].flags = count == 0 ? SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT : 0;
		buttons[count].buttonID = at;
		buttons[count].text = names[at];
		count++;
	}

	if (count > 0) buttons[count - 1].flags |= SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT;

	SDL_MessageBoxData data;
	SDL_zero(data);

	data.flags = (fault != 0 ? SDL_MESSAGEBOX_ERROR : SDL_MESSAGEBOX_INFORMATION)
		| SDL_MESSAGEBOX_BUTTONS_LEFT_TO_RIGHT;
	data.title = title;
	data.message = said;
	data.numbuttons = count;
	data.buttons = buttons;

	int chosen = -1;
	if (!SDL_ShowMessageBox(&data, &chosen)) return -1;

	return chosen;
}

extern "C" void mdd_window_icon(SDL_Window *window, const unsigned char *pixels, int width,
	int height) {
	if (window == NULL || pixels == NULL) return;

	SDL_Surface *face = SDL_CreateSurfaceFrom(width, height, SDL_PIXELFORMAT_RGBA32,
		(void *) pixels, width * 4);

	if (face == NULL) return;

	SDL_SetWindowIcon(window, face);
	SDL_DestroySurface(face);
}

static SDL_Cursor *mdd_cursors[MDD_CURSORS];
static int mdd_cursor_now = -1;

extern "C" void mdd_cursor_set(int shape) {
	if (shape < 0 || shape >= MDD_CURSORS) shape = MDD_CURSOR_ARROW;
	if (shape == mdd_cursor_now) return;

	if (mdd_cursors[shape] == NULL) {
		SDL_SystemCursor want = SDL_SYSTEM_CURSOR_DEFAULT;

		switch (shape) {
			case MDD_CURSOR_TEXT: want = SDL_SYSTEM_CURSOR_TEXT; break;
			case MDD_CURSOR_ACROSS: want = SDL_SYSTEM_CURSOR_EW_RESIZE; break;
			case MDD_CURSOR_DOWN: want = SDL_SYSTEM_CURSOR_NS_RESIZE; break;
			case MDD_CURSOR_HAND: want = SDL_SYSTEM_CURSOR_POINTER; break;
			case MDD_CURSOR_MOVE: want = SDL_SYSTEM_CURSOR_MOVE; break;
			default: want = SDL_SYSTEM_CURSOR_DEFAULT; break;
		}

		mdd_cursors[shape] = SDL_CreateSystemCursor(want);
		if (mdd_cursors[shape] == NULL) return;
	}

	SDL_SetCursor(mdd_cursors[shape]);
	mdd_cursor_now = shape;
}

extern "C" void mdd_cursor_free(void) {
	for (int index = 0; index < MDD_CURSORS; index++) {
		if (mdd_cursors[index] == NULL) continue;

		SDL_DestroyCursor(mdd_cursors[index]);
		mdd_cursors[index] = NULL;
	}

	mdd_cursor_now = -1;
}

extern "C" void mdd_pointer_warp(SDL_Window *window, float x, float y) {
	if (window != nullptr) SDL_WarpMouseInWindow(window, x, y);
}
