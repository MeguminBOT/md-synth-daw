#pragma once

#include <SDL3/SDL.h>

/**
 * Writes what this machine offers the interface to a file, one fact a line, a name and then what
 * it has: every renderer the application offers with the level it reaches, `0` where it cannot be
 * made at all, and the graphics memory the card can use. The Windows installer runs the
 * application with `--requirements` to have this written before it installs anything.
 *
 * Starts SDL and shuts it down again, so it is called instead of the application rather than
 * inside it.
 *
 * @param path Where to write, in UTF-8.
 * @return Nought where the file was written, and one where it could not be opened.
 */
extern "C" int mdd_requirements_write(const char *path);

/**
 * Asks a renderer already made what level it reached: the feature level of a Direct3D 11 device,
 * the version of an OpenGL or OpenGL ES context, or the pixel shader model of a Direct3D 9 device.
 * That costs nothing, where asking the driver before making one costs as much as loading it.
 *
 * @param renderer The renderer, just made, which for OpenGL is while its context is still the
 * 	current one.
 * @return The level as `major << 8 | minor`, `0x0A00` for feature level 10_0 and `0x0200` for
 * 	OpenGL 2.0, or nought where the renderer has no level to read.
 */
extern "C" int mdd_requirements_reached(SDL_Renderer *renderer);
