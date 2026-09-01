#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

#include "text.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {
	constexpr int SLOTS = 8;

	struct Face {
		unsigned char *data;
		stbtt_fontinfo info;
		bool taken;
	};

	Face faces[SLOTS];
}

extern "C" int mdd_font_load(const char *path) {
	if (path == nullptr) return -1;

	int slot = -1;
	for (int i = 0; i < SLOTS; i++) {
		if (!faces[i].taken) { slot = i; break; }
	}
	if (slot < 0) return -1;

	FILE *file = fopen(path, "rb");
	if (file == nullptr) return -1;

	fseek(file, 0, SEEK_END);
	const long size = ftell(file);
	fseek(file, 0, SEEK_SET);

	if (size <= 0) { fclose(file); return -1; }

	unsigned char *data = static_cast<unsigned char *>(malloc(static_cast<size_t>(size)));
	if (data == nullptr) { fclose(file); return -1; }

	const size_t read = fread(data, 1, static_cast<size_t>(size), file);
	fclose(file);

	if (read != static_cast<size_t>(size)) { free(data); return -1; }

	if (!stbtt_InitFont(&faces[slot].info, data, stbtt_GetFontOffsetForIndex(data, 0))) {
		free(data);
		return -1;
	}

	faces[slot].data = data;
	faces[slot].taken = true;
	return slot;
}

extern "C" void mdd_font_free(int font) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return;
	free(faces[font].data);
	faces[font].data = nullptr;
	faces[font].taken = false;
}

static float scaleOf(int font, float pixels) {
	return stbtt_ScaleForPixelHeight(&faces[font].info, pixels);
}

extern "C" float mdd_font_ascent(int font, float pixels) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return 0;
	int ascent = 0, descent = 0, gap = 0;
	stbtt_GetFontVMetrics(&faces[font].info, &ascent, &descent, &gap);
	return ascent * scaleOf(font, pixels);
}

extern "C" float mdd_font_descent(int font, float pixels) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return 0;
	int ascent = 0, descent = 0, gap = 0;
	stbtt_GetFontVMetrics(&faces[font].info, &ascent, &descent, &gap);
	return -descent * scaleOf(font, pixels);
}

extern "C" float mdd_font_line(int font, float pixels) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return 0;
	int ascent = 0, descent = 0, gap = 0;
	stbtt_GetFontVMetrics(&faces[font].info, &ascent, &descent, &gap);
	return (ascent - descent + gap) * scaleOf(font, pixels);
}

extern "C" float mdd_font_kern(int font, float pixels, int left, int right) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return 0;
	return stbtt_GetCodepointKernAdvance(&faces[font].info, left, right) * scaleOf(font, pixels);
}

extern "C" int mdd_font_bake(int font, float pixels, int first, int count, unsigned char *rgba,
		int atlasWidth, int atlasHeight, float *glyphs) {
	if (font < 0 || font >= SLOTS || !faces[font].taken) return 0;
	if (rgba == nullptr || glyphs == nullptr || count <= 0) return 0;

	const size_t cells = static_cast<size_t>(atlasWidth) * atlasHeight;
	unsigned char *coverage = static_cast<unsigned char *>(calloc(cells, 1));
	if (coverage == nullptr) return 0;

	stbtt_packedchar *packed =
		static_cast<stbtt_packedchar *>(calloc(static_cast<size_t>(count), sizeof(stbtt_packedchar)));
	if (packed == nullptr) { free(coverage); return 0; }

	stbtt_pack_context context;
	if (!stbtt_PackBegin(&context, coverage, atlasWidth, atlasHeight, 0, 1, nullptr)) {
		free(packed);
		free(coverage);
		return 0;
	}

	stbtt_PackSetOversampling(&context, 2, 2);
	const int done = stbtt_PackFontRange(&context, faces[font].data, 0, pixels, first, count, packed);
	stbtt_PackEnd(&context);

	if (!done) {
		free(packed);
		free(coverage);
		return 0;
	}

	for (size_t i = 0; i < cells; i++) {
		rgba[i * 4] = 255;
		rgba[i * 4 + 1] = 255;
		rgba[i * 4 + 2] = 255;
		rgba[i * 4 + 3] = coverage[i];
	}

	const float acrossWide = 1.0f / atlasWidth;
	const float acrossTall = 1.0f / atlasHeight;

	for (int i = 0; i < count; i++) {
		const stbtt_packedchar &one = packed[i];
		float *out = glyphs + static_cast<size_t>(i) * MDD_GLYPH_FLOATS;

		out[0] = one.x0 * acrossWide;
		out[1] = one.y0 * acrossTall;
		out[2] = one.x1 * acrossWide;
		out[3] = one.y1 * acrossTall;
		out[4] = one.xoff;
		out[5] = one.yoff;
		out[6] = one.xadvance;
		out[7] = one.xoff2 - one.xoff;
		out[8] = one.yoff2 - one.yoff;
	}

	free(packed);
	free(coverage);
	return 1;
}
