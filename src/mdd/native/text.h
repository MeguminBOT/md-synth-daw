#ifndef MDD_TEXT_H
#define MDD_TEXT_H

#ifdef __cplusplus
extern "C" {
#endif

#define MDD_GLYPH_FLOATS 9

int mdd_font_load(const char *path);
void mdd_font_free(int font);
int mdd_font_weight(int font);
int mdd_font_resting(int font);

float mdd_font_ascent(int font, float pixels);
float mdd_font_descent(int font, float pixels);
float mdd_font_line(int font, float pixels);
float mdd_font_kern(int font, float pixels, int left, int right);

int mdd_font_bake(int font, float pixels, int first, int count, unsigned char *rgba,
	int atlasWidth, int atlasHeight, float *glyphs);

int mdd_font_extent(int font, float pixels, int codepoint, int *wide, int *tall);

int mdd_font_glyph(int font, float pixels, int codepoint, unsigned char *rgba, int atlasWidth,
	int atlasHeight, int atX, int atY, float *glyph);

#ifdef __cplusplus
}
#endif

#endif
