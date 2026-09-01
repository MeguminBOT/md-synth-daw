#ifndef MDD_WINDOW_H
#define MDD_WINDOW_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

int mdd_sdl_init(void);
void mdd_sdl_quit(void);
const char *mdd_sdl_error(void);

SDL_Window *mdd_window_create(const char *title, int width, int height, int resizable,
	int highDpi);
void mdd_window_destroy(SDL_Window *window);
unsigned int mdd_window_id(SDL_Window *window);
void mdd_window_set_title(SDL_Window *window, const char *title);
int mdd_window_width(SDL_Window *window);
int mdd_window_height(SDL_Window *window);
int mdd_window_pixel_width(SDL_Window *window);
int mdd_window_pixel_height(SDL_Window *window);
void mdd_window_set_size(SDL_Window *window, int width, int height);
void mdd_window_set_minimum_size(SDL_Window *window, int width, int height);
void mdd_window_set_fullscreen(SDL_Window *window, int on);
void mdd_window_show(SDL_Window *window);
float mdd_window_display_scale(SDL_Window *window);
float mdd_display_pixel_density(SDL_Window *window);
float mdd_display_refresh(SDL_Window *window);

void mdd_text_input_start(SDL_Window *window);
void mdd_text_input_stop(SDL_Window *window);

SDL_Renderer *mdd_renderer_create(SDL_Window *window, int vsync);
void mdd_renderer_destroy(SDL_Renderer *renderer);
const char *mdd_renderer_name(SDL_Renderer *renderer);
int mdd_renderer_vsync(SDL_Renderer *renderer);

void mdd_render_clear(SDL_Renderer *renderer, float r, float g, float b, float a);
void mdd_render_present(SDL_Renderer *renderer);
int mdd_render_output_width(SDL_Renderer *renderer);
int mdd_render_output_height(SDL_Renderer *renderer);
void mdd_set_clip(SDL_Renderer *renderer, int x, int y, int width, int height);
void mdd_clear_clip(SDL_Renderer *renderer);

int mdd_reduce_motion(void);

void mdd_sleep(double seconds);
double mdd_ticks(void);

#ifdef __cplusplus
}
#endif

#endif
