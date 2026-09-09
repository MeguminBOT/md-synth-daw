#ifndef MDD_VARY_H
#define MDD_VARY_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Instances a variable font at a weight, so a rasteriser with no variation support
 * draws the face that was asked for rather than whatever its axis rests at.
 *
 * Three things here are easy to get wrong. A glyph with no outline still carries an
 * advance delta in its phantom points, so a zero length entry has to be read rather
 * than skipped. Where two reference points share a coordinate the inferred delta is
 * zero unless both deltas agree, rather than the nearer one. And the coordinate the
 * deltas are scaled by is F2Dot14, so normalising in wider precision than the
 * format holds moves points that land on a half unit.
 *
 * It parses a file at every start, so it is bounded against a truncated download:
 * every offset is checked against the length of the table it points into.
 *
 * @param data The font file.
 * @param size How long it is.
 * @param weight The weight to instance to.
 * @param made Filled in with the length of what comes back.
 * @return A new font file at that weight, to be freed by the caller, or NULL where the face has no
 * 	variation axis or the file will not parse.
 */
unsigned char *mdd_vary_instance(const unsigned char *data, long size, float weight, long *made);

/**
 * @param data A font file.
 * @param size How long it is.
 * @return The weight its name table declares.
 */
int mdd_vary_weight(const unsigned char *data, long size);

/**
 * @param data A font file.
 * @param size How long it is.
 * @return The weight its variation axis rests at, or nought where it has no axis. Several of the
 * 	faces that ship rest at 100, 200 or 300.
 */
int mdd_vary_resting(const unsigned char *data, long size);

#ifdef __cplusplus
}
#endif

#endif
