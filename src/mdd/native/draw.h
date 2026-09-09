#ifndef MDD_DRAW_H
#define MDD_DRAW_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Makes a texture to be filled from pixels.
 *
 * @param renderer The renderer.
 * @param width How wide.
 * @param height How tall.
 * @return The texture, or NULL.
 */
SDL_Texture *mdd_texture_create(SDL_Renderer *renderer, int width, int height);

/**
 * Makes a texture that can be drawn into.
 *
 * @param renderer The renderer.
 * @param width How wide.
 * @param height How tall.
 * @return The texture, or NULL.
 */
SDL_Texture *mdd_texture_target(SDL_Renderer *renderer, int width, int height);

/**
 * Replaces the whole of a texture.
 *
 * @param texture The texture.
 * @param rgba The pixels.
 * @param width How wide they are.
 * @param height How tall.
 */
void mdd_texture_update(SDL_Texture *texture, const unsigned char *rgba, int width, int height);

/**
 * Replaces one rectangle of a texture, which is how a glyph reaches an atlas
 * without rewriting the whole of it.
 *
 * @param texture The texture.
 * @param rgba The pixels.
 * @param x Where they go, across.
 * @param y Where they go, down.
 * @param width How wide they are.
 * @param height How tall.
 */
void mdd_texture_patch(SDL_Texture *texture, const unsigned char *rgba, int x, int y, int width,
	int height);

/**
 * Destroys a texture.
 *
 * @param texture The texture.
 */
void mdd_texture_destroy(SDL_Texture *texture);

/**
 * Chooses whether a texture is smoothed when it is drawn at another size.
 *
 * @param texture The texture.
 * @param smooth Nonzero to smooth it.
 */
void mdd_texture_scale_mode(SDL_Texture *texture, int smooth);

/**
 * Draws into a texture from here, or back into the window when given NULL.
 *
 * @param renderer The renderer.
 * @param texture The target, or NULL for the window.
 */
void mdd_set_target(SDL_Renderer *renderer, SDL_Texture *texture);

/**
 * Reads pixels back out of the target. A target cleared opaque has alpha 255
 * everywhere, so a check looking for what was drawn has to test the colour
 * channels rather than the alpha.
 *
 * @param renderer The renderer.
 * @param x Where to read from, across.
 * @param y Where to read from, down.
 * @param width How wide.
 * @param height How tall.
 * @param rgba Filled in with the pixels.
 * @return Nonzero where they were read.
 */
int mdd_read_pixels(SDL_Renderer *renderer, int x, int y, int width, int height,
	unsigned char *rgba);

/**
 * Draws triangles, with or without a texture. Every filled shape and every run of
 * glyphs comes down to this.
 *
 * @param renderer The renderer.
 * @param texture The texture to sample, or NULL for flat colour.
 * @param vertices Position, colour and texture coordinates per vertex.
 * @param vertexCount How many vertices.
 */
void mdd_render_geometry(SDL_Renderer *renderer, SDL_Texture *texture, const float *vertices,
	int vertexCount);

/**
 * Draws one whole texture into a rectangle.
 *
 * @param renderer The renderer.
 * @param texture The texture.
 * @param x Where it goes, across.
 * @param y Where it goes, down.
 * @param width How wide to draw it.
 * @param height How tall.
 * @param alpha How opaque, 0 to 1.
 */
void mdd_render_texture(SDL_Renderer *renderer, SDL_Texture *texture, float x, float y,
	float width, float height, float alpha);

/**
 * @return How many draw calls have been made since the last reset, which is what a check measuring
 * 	an idle frame reads.
 */
int mdd_draw_calls(void);

/**
 * Sets that count back to nought.
 */
void mdd_draw_calls_reset(void);

#ifdef __cplusplus
}
#endif

#endif
