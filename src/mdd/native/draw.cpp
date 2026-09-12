/**
 * Textures and the drawing calls that use them, through SDL.
 *
 * Every filled shape and every run of glyphs comes down to one geometry call, and the
 * count of those calls is kept so a check can measure what an idle frame costs.
 */
#include "draw.h"

namespace {
	int calls = 0;
}

extern "C" SDL_Texture *mdd_texture_create(SDL_Renderer *renderer, int width, int height) {
	SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
		SDL_TEXTUREACCESS_STATIC, width, height);
	if (texture != nullptr) {
		SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
		SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);
	}
	return texture;
}

extern "C" SDL_Texture *mdd_texture_target(SDL_Renderer *renderer, int width, int height) {
	SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
		SDL_TEXTUREACCESS_TARGET, width, height);
	if (texture != nullptr) SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
	return texture;
}

extern "C" void mdd_texture_update(SDL_Texture *texture, const unsigned char *rgba,
		int width) {
	if (texture != nullptr) SDL_UpdateTexture(texture, nullptr, rgba, width * 4);
}

extern "C" void mdd_texture_patch(SDL_Texture *texture, const unsigned char *rgba, int x, int y,
		int width, int height) {
	if (texture == nullptr || rgba == nullptr || width <= 0 || height <= 0) return;

	SDL_Rect where;
	where.x = x;
	where.y = y;
	where.w = width;
	where.h = height;

	SDL_UpdateTexture(texture, &where, rgba, width * 4);
}

extern "C" void mdd_texture_destroy(SDL_Texture *texture) {
	if (texture != nullptr) SDL_DestroyTexture(texture);
}

extern "C" void mdd_texture_scale_mode(SDL_Texture *texture, int smooth) {
	if (texture != nullptr) {
		SDL_SetTextureScaleMode(texture, smooth != 0 ? SDL_SCALEMODE_LINEAR : SDL_SCALEMODE_NEAREST);
	}
}

extern "C" void mdd_set_target(SDL_Renderer *renderer, SDL_Texture *texture) {
	if (renderer != nullptr) SDL_SetRenderTarget(renderer, texture);
}

extern "C" int mdd_read_pixels(SDL_Renderer *renderer, int x, int y, int width, int height,
		unsigned char *rgba) {
	if (renderer == nullptr || rgba == nullptr) return 0;

	SDL_Rect rect;
	rect.x = x;
	rect.y = y;
	rect.w = width;
	rect.h = height;

	SDL_Surface *taken = SDL_RenderReadPixels(renderer, &rect);
	if (taken == nullptr) return 0;

	SDL_Surface *shaped = taken->format == SDL_PIXELFORMAT_RGBA32
		? taken : SDL_ConvertSurface(taken, SDL_PIXELFORMAT_RGBA32);

	if (shaped == nullptr) {
		SDL_DestroySurface(taken);
		return 0;
	}

	for (int row = 0; row < height; row++) {
		SDL_memcpy(rgba + static_cast<size_t>(row) * width * 4,
			static_cast<const unsigned char *>(shaped->pixels) + static_cast<size_t>(row) * shaped->pitch,
			static_cast<size_t>(width) * 4);
	}

	if (shaped != taken) SDL_DestroySurface(shaped);
	SDL_DestroySurface(taken);
	return 1;
}

extern "C" void mdd_render_geometry(SDL_Renderer *renderer, SDL_Texture *texture,
		const float *vertices, int vertexCount) {
	if (renderer == nullptr || vertices == nullptr || vertexCount <= 0) return;

	SDL_RenderGeometry(renderer, texture, reinterpret_cast<const SDL_Vertex *>(vertices),
		vertexCount, nullptr, 0);
	calls++;
}

extern "C" void mdd_render_texture(SDL_Renderer *renderer, SDL_Texture *texture, float x, float y,
		float width, float height, float alpha) {
	if (renderer == nullptr || texture == nullptr) return;

	SDL_FRect into;
	into.x = x;
	into.y = y;
	into.w = width;
	into.h = height;

	SDL_SetTextureAlphaModFloat(texture, alpha);
	SDL_RenderTexture(renderer, texture, nullptr, &into);
	calls++;
}

extern "C" int mdd_draw_calls(void) {
	return calls;
}

extern "C" void mdd_draw_calls_reset(void) {
	calls = 0;
}
