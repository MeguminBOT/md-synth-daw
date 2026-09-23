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
 * How tall the pixels are is not asked for: the whole texture is replaced, so the
 * height is the one it was made at, and the width is only there to say how far
 * apart two rows of pixels are.
 *
 * @param texture The texture.
 * @param rgba The pixels.
 * @param width How wide they are.
 */
void mdd_texture_update(SDL_Texture *texture, const unsigned char *rgba, int width);

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
 * Sets how a texture is laid over what is under it: as colour already multiplied by its own
 * alpha, which is what drawing into a cleared target leaves, or as colour with alpha beside it.
 *
 * @param texture The texture.
 * @param premultiplied Nonzero where its colour is already multiplied by its alpha.
 */
void mdd_texture_premultiplied(SDL_Texture *texture, int premultiplied);

/**
 * Draws one whole texture into a rectangle turned about its own centre.
 *
 * @param renderer The renderer.
 * @param texture The texture.
 * @param x Where the rectangle's centre is, across.
 * @param y Where its centre is, down.
 * @param width How wide the rectangle is before it is turned.
 * @param height How tall.
 * @param degrees How far it is turned, clockwise.
 * @param alpha How opaque, 0 to 1. A texture blended as premultiplied has its colour scaled by
 *     it as well, because its colour already carries its alpha.
 */
void mdd_render_turned(SDL_Renderer *renderer, SDL_Texture *texture, float x, float y,
	float width, float height, float degrees, float alpha);

/**
 * Draws a part of a texture into a rectangle turned about its own centre, which is how one
 * texture kept larger than anything drawn into it is laid over a picture.
 *
 * @param renderer The renderer.
 * @param texture The texture.
 * @param fromWide How much of the texture to take, across from its left edge.
 * @param fromTall How much, down from its top edge.
 * @param x Where the rectangle's centre is, across.
 * @param y Where its centre is, down.
 * @param width How wide the rectangle is before it is turned.
 * @param height How tall.
 * @param degrees How far it is turned, clockwise.
 * @param alpha How opaque, 0 to 1, scaling a premultiplied texture's colour as well.
 */
void mdd_render_turned_part(SDL_Renderer *renderer, SDL_Texture *texture, float fromWide,
	float fromTall, float x, float y, float width, float height, float degrees, float alpha);

/**
 * Draws a part of a texture tinted, into a rectangle turned about its own centre: its colour
 * multiplied by the tint, which on a texture holding white is a silhouette in the tint's colour.
 *
 * @param renderer The renderer.
 * @param texture The texture.
 * @param fromWide How much of the texture to take, across from its left edge.
 * @param fromTall How much, down from its top edge.
 * @param x Where the rectangle's centre is, across.
 * @param y Where its centre is, down.
 * @param width How wide the rectangle is before it is turned.
 * @param height How tall.
 * @param degrees How far it is turned, clockwise.
 * @param alpha How opaque, 0 to 1, scaling a premultiplied texture's colour as well.
 * @param tint The colour to multiply by, as 0xRRGGBB.
 */
void mdd_render_tinted(SDL_Renderer *renderer, SDL_Texture *texture, float fromWide,
	float fromTall, float x, float y, float width, float height, float degrees, float alpha,
	int tint);

/**
 * mdd_render_shape: the target's alpha becomes the texture's laid over it, s + d(1 - s).
 */
#define MDD_SHAPE_OVER 0

/**
 * mdd_render_shape: the target's alpha becomes the two added, s + d, stopping at one.
 */
#define MDD_SHAPE_ADD 1

/**
 * mdd_render_shape: the target keeps its alpha only where the texture has one, ds.
 */
#define MDD_SHAPE_WITHIN 2

/**
 * mdd_render_shape: the target loses its alpha where the texture has one, d(1 - s).
 */
#define MDD_SHAPE_CUT 3

/**
 * mdd_render_shape: the target's alpha becomes the texture's where the target had none,
 * s(1 - d).
 */
#define MDD_SHAPE_OUTSIDE 4

/**
 * Lays a part of a texture's alpha over the target's, unturned, and leaves the target's colour as
 * it was. A target cleared to white with no alpha and drawn into this way holds a shape: white
 * everywhere, with the alpha the modes make of it, which drawn tinted is a silhouette.
 *
 * In the modes, s is the texture's alpha times `alpha` and d is the target's.
 *
 * @param renderer The renderer.
 * @param texture The texture, whose own blend mode is put back afterwards.
 * @param fromWide How much of the texture to take, across from its left edge.
 * @param fromTall How much, down from its top edge.
 * @param x Where the rectangle's left edge is.
 * @param y Where its top edge is.
 * @param width How wide the rectangle is.
 * @param height How tall.
 * @param alpha What the texture's alpha is multiplied by.
 * @param mode One of the MDD_SHAPE modes.
 * @return Nonzero where it was drawn, and nought where the renderer cannot blend this way, which
 *     the software renderer cannot.
 */
int mdd_render_shape(SDL_Renderer *renderer, SDL_Texture *texture, float fromWide,
	float fromTall, float x, float y, float width, float height, float alpha, int mode);

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
