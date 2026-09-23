#ifndef MDD_IMAGE_H
#define MDD_IMAGE_H

#include <SDL3/SDL.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * The most pixels a picture may have on either side. A file claiming more is refused before any
 * of it is decoded, so a picture cannot ask for more memory than a video frame could use.
 */
#define MDD_IMAGE_SIDE 8192

/**
 * Reads a PNG or a JPEG into a texture at the size the file holds, with its alpha kept and
 * blended as drawn, and linear filtering for when it is drawn at another size or angle.
 *
 * @param renderer The renderer the texture is for.
 * @param path Where the file is, in UTF-8.
 * @param size Two ints the width and the height are written into, both nought where it fails.
 * @return The texture, or NULL where the file will not open, is not a PNG or a JPEG, or is wider
 *     or taller than MDD_IMAGE_SIDE.
 */
SDL_Texture *mdd_image_load(SDL_Renderer *renderer, const char *path, int *size);

#ifdef __cplusplus
}
#endif

#endif
