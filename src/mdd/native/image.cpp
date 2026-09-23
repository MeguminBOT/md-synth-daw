#include "image.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_PNG
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#define STBI_MAX_DIMENSIONS MDD_IMAGE_SIDE
#include "stb_image.h"

extern "C" SDL_Texture *mdd_image_load(SDL_Renderer *renderer, const char *path, int *size) {
	size[0] = 0;
	size[1] = 0;

	if (renderer == nullptr || path == nullptr) return nullptr;

	size_t length = 0;
	void *file = SDL_LoadFile(path, &length);
	if (file == nullptr) return nullptr;

	int width = 0;
	int height = 0;
	int held = 0;

	stbi_uc *pixels = length > 0 && length < 0x7fffffff
		? stbi_load_from_memory((const stbi_uc *) file, (int) length, &width, &height, &held, 4)
		: nullptr;

	SDL_free(file);
	if (pixels == nullptr) return nullptr;

	SDL_Texture *texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
		SDL_TEXTUREACCESS_STATIC, width, height);

	if (texture == nullptr) {
		stbi_image_free(pixels);
		return nullptr;
	}

	SDL_UpdateTexture(texture, nullptr, pixels, width * 4);
	SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
	SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_LINEAR);

	stbi_image_free(pixels);

	size[0] = width;
	size[1] = height;

	return texture;
}
