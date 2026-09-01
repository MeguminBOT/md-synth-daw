#ifndef MDD_DRAW_H
#define MDD_DRAW_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

SDL_Texture *mdd_texture_create(SDL_Renderer *renderer, int width, int height);
SDL_Texture *mdd_texture_target(SDL_Renderer *renderer, int width, int height);
void mdd_texture_update(SDL_Texture *texture, const unsigned char *rgba, int width, int height);
void mdd_texture_destroy(SDL_Texture *texture);
void mdd_texture_scale_mode(SDL_Texture *texture, int smooth);

void mdd_set_target(SDL_Renderer *renderer, SDL_Texture *texture);
int mdd_read_pixels(SDL_Renderer *renderer, int x, int y, int width, int height,
	unsigned char *rgba);

void mdd_render_geometry(SDL_Renderer *renderer, SDL_Texture *texture, const float *vertices,
	int vertexCount);
void mdd_render_texture(SDL_Renderer *renderer, SDL_Texture *texture, float x, float y,
	float width, float height);

int mdd_draw_calls(void);
void mdd_draw_calls_reset(void);

#ifdef __cplusplus
}
#endif

#endif
