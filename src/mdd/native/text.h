#ifndef MDD_TEXT_H
#define MDD_TEXT_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * How many numbers describe one glyph: its atlas rectangle, its offsets and its
 * advance.
 */
#define MDD_GLYPH_FLOATS 9

/**
 * Reads a font file. A variable font is instanced to weight 400 as it loads,
 * because stb_truetype has no variation support and would otherwise draw whatever
 * the axis rests at, which is 100 or 200 on several of the faces that ship.
 *
 * @param path The file to read.
 * @return A handle, or a negative number where it would not read.
 */
int mdd_font_load(const char *path);

/**
 * Gives a font back.
 *
 * @param font A font handle from mdd_font_load.
 */
void mdd_font_free(int font);

/**
 * @param font A font handle from mdd_font_load.
 * @return The weight it was instanced to.
 */
int mdd_font_weight(int font);

/**
 * @param font A font handle from mdd_font_load.
 * @return The weight its axis rested at before instancing, or nought where it has no axis.
 */
int mdd_font_resting(int font);

/**
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @return How far above the baseline the face reaches.
 */
float mdd_font_ascent(int font, float pixels);

/**
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @return How far below it.
 */
float mdd_font_descent(int font, float pixels);

/**
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @return How far apart two lines sit.
 */
float mdd_font_line(int font, float pixels);

/**
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @param left The codepoint on the left.
 * @param right The codepoint on the right.
 * @return How much closer the pair sits than their advances alone would put them.
 */
float mdd_font_kern(int font, float pixels, int left, int right);

/**
 * Draws a run of codepoints into an atlas in one pass.
 *
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @param first The first codepoint.
 * @param count How many.
 * @param rgba The atlas to draw into.
 * @param atlasWidth How wide it is.
 * @param atlasHeight How tall it is.
 * @param glyphs Filled in with MDD_GLYPH_FLOATS numbers per glyph.
 * @return How many were drawn.
 */
int mdd_font_bake(int font, float pixels, int first, int count, unsigned char *rgba,
	int atlasWidth, int atlasHeight, float *glyphs);

/**
 * Measures one glyph without drawing it. With oversampling the packed rectangle is
 * larger than the glyph is drawn, and the width to use is the difference of the
 * offsets rather than the width of the rectangle.
 *
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @param codepoint Which glyph.
 * @param wide Filled in with its width.
 * @param tall Filled in with its height.
 * @return Nonzero where the face has the glyph.
 */
int mdd_font_extent(int font, float pixels, int codepoint, int *wide, int *tall);

/**
 * Draws one glyph into an atlas at a position.
 *
 * @param font A font handle from mdd_font_load.
 * @param pixels The size to draw at, in pixels.
 * @param codepoint Which glyph.
 * @param rgba The atlas to draw into.
 * @param atlasWidth How wide it is.
 * @param atlasHeight How tall it is.
 * @param atX Where to draw it, across.
 * @param atY Where to draw it, down.
 * @param glyph Filled in with MDD_GLYPH_FLOATS numbers describing it.
 * @return Nonzero where it was drawn.
 */
int mdd_font_glyph(int font, float pixels, int codepoint, unsigned char *rgba, int atlasWidth,
	int atlasHeight, int atX, int atY, float *glyph);

#ifdef __cplusplus
}
#endif

#endif
