#ifndef MDD_TEXT_H
#define MDD_TEXT_H

#ifdef __cplusplus
extern "C" {
#endif

#define MDD_GLYPH_FLOATS 9

int mdd_font_load(const char *path);
void mdd_font_free(int font);

float mdd_font_ascent(int font, float pixels);
float mdd_font_descent(int font, float pixels);
float mdd_font_line(int font, float pixels);
float mdd_font_kern(int font, float pixels, int left, int right);

int mdd_font_bake(int font, float pixels, int first, int count, unsigned char *rgba,
	int atlasWidth, int atlasHeight, float *glyphs);

#ifdef __cplusplus
}
#endif

#endif
