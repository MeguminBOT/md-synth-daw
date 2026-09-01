#include "window.h"

#ifdef _WIN32
#include <windows.h>
#endif

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

extern "C" SDL_Renderer *mdd_renderer_create(SDL_Window *window, int vsync) {
	SDL_Renderer *renderer = SDL_CreateRenderer(window, nullptr);
	if (renderer == nullptr) return nullptr;

	SDL_SetRenderVSync(renderer, vsync != 0 ? 1 : SDL_RENDERER_VSYNC_DISABLED);
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
	if (renderer != nullptr) SDL_RenderPresent(renderer);
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

extern "C" int mdd_reduce_motion(void) {
#ifdef _WIN32
	BOOL animate = TRUE;
	if (SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animate, 0) != 0) {
		return animate != FALSE ? 0 : 1;
	}
	return 0;
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
