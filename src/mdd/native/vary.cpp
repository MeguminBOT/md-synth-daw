/*
	MD Synth DAW
	https://github.com/MeguminBOT/md-synth-daw

	MIT License

	Copyright (c) 2026 MeguminBOT and the md-synth-daw contributors

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

	SPDX-License-Identifier: MIT
*/

/**
 * Instancing a variable font at a weight, so a rasteriser with no variation support
 * draws the face that was asked for.
 *
 * google/fonts ships only the variable file for several of the faces here, with no
 * static directory to fetch instead, and their axes rest at 300, 200, 200 and 100. A
 * rasteriser that cannot vary draws the resting instance, so CJK fallbacks came out as
 * hairlines beside 400 weight Latin. This reads the variation tables, moves every
 * point to the weight asked for, and writes a new font file at that instance. A face
 * whose axis already rests at 400 is left alone, so most of what ships pays nothing.
 *
 * Three things here are easy to get wrong. A glyph with no outline still carries an
 * advance delta in its phantom points, so a zero length entry has to be read rather
 * than skipped. Where two reference points share a coordinate the inferred delta is
 * zero unless both deltas agree, rather than the nearer one. And the coordinate the
 * deltas are scaled by is F2Dot14, so normalising in wider precision than the format
 * holds moves points that land on a half unit.
 *
 * It parses a file at every start, so it is bounded against a truncated download: an
 * offset into the outline table and an offset measured from a table data offset are
 * both untrustworthy until they are checked against the length of the table. Fuzzing
 * aimed at those tables faulted five times in three hundred before they were.
 */
#include "vary.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

namespace {
	constexpr int AXES = 8;
	constexpr int NESTED = 8;

	constexpr unsigned int ARGS_ARE_WORDS = 0x0001;
	constexpr unsigned int ARGS_ARE_XY = 0x0002;
	constexpr unsigned int HAVE_A_SCALE = 0x0008;
	constexpr unsigned int MORE_COMPONENTS = 0x0020;
	constexpr unsigned int HAVE_XY_SCALE = 0x0040;
	constexpr unsigned int HAVE_TWO_BY_TWO = 0x0080;
	constexpr unsigned int HAVE_INSTRUCTIONS = 0x0100;

	constexpr unsigned int ON_CURVE = 0x01;
	constexpr unsigned int X_SHORT = 0x02;
	constexpr unsigned int Y_SHORT = 0x04;
	constexpr unsigned int REPEATS = 0x08;
	constexpr unsigned int X_SAME = 0x10;
	constexpr unsigned int Y_SAME = 0x20;
	constexpr unsigned int OVERLAPS = 0x40;

	constexpr unsigned char BOX_UNKNOWN = 0;
	constexpr unsigned char BOX_KNOWN = 1;
	constexpr unsigned char BOX_EMPTY = 2;

	inline unsigned int wordAt(const unsigned char *at) {
		return (unsigned int) at[0] << 8 | (unsigned int) at[1];
	}

	inline int shortAt(const unsigned char *at) {
		return (int) (short) (unsigned short) ((unsigned int) at[0] << 8 | (unsigned int) at[1]);
	}

	inline unsigned long longAt(const unsigned char *at) {
		return (unsigned long) at[0] << 24 | (unsigned long) at[1] << 16
			| (unsigned long) at[2] << 8 | (unsigned long) at[3];
	}

	inline double fixedAt(const unsigned char *at) {
		return (double) (int) (unsigned int) longAt(at) / 65536.0;
	}

	inline double fractionAt(const unsigned char *at) {
		return (double) shortAt(at) / 16384.0;
	}


	inline int rounded(double value) {
		return (int) floor(value + 0.5);
	}

	inline double quantised(double held) {
		return (double) rounded(held * 16384.0) / 16384.0;
	}

	struct Slot {
		unsigned char tag[4];
		unsigned long offset;
		unsigned long length;
	};

	struct Grown {
		unsigned char *data;
		size_t used;
		size_t room;
	};

	struct Piece {
		unsigned int flags;
		unsigned int index;
		int argOne;
		int argTwo;
		unsigned char shape[8];
		int shapeBytes;
	};

	struct Later {
		unsigned int glyph;
		size_t where;
		int first;
		int many;
		int origin;
	};

	template <typename Held> bool widen(Held **held, int *room, int want) {
		if (*room >= want) return true;

		int bigger = *room == 0 ? 64 : *room;
		while (bigger < want) bigger *= 2;

		Held *moved = (Held *) realloc(*held, (size_t) bigger * sizeof(Held));
		if (moved == nullptr) return false;

		*held = moved;
		*room = bigger;
		return true;
	}

	bool roomFor(Grown *grown, size_t more) {
		if (grown->used + more <= grown->room) return true;

		size_t want = grown->room == 0 ? 8192 : grown->room;
		while (want < grown->used + more) want *= 2;

		unsigned char *bigger = (unsigned char *) realloc(grown->data, want);
		if (bigger == nullptr) return false;

		grown->data = bigger;
		grown->room = want;
		return true;
	}

	bool putByte(Grown *grown, unsigned int value) {
		if (!roomFor(grown, 1)) return false;
		grown->data[grown->used++] = (unsigned char) (value & 0xFF);
		return true;
	}

	bool putWord(Grown *grown, unsigned int value) {
		if (!roomFor(grown, 2)) return false;
		grown->data[grown->used++] = (unsigned char) (value >> 8 & 0xFF);
		grown->data[grown->used++] = (unsigned char) (value & 0xFF);
		return true;
	}

	bool putLong(Grown *grown, unsigned long value) {
		if (!roomFor(grown, 4)) return false;
		grown->data[grown->used++] = (unsigned char) (value >> 24 & 0xFF);
		grown->data[grown->used++] = (unsigned char) (value >> 16 & 0xFF);
		grown->data[grown->used++] = (unsigned char) (value >> 8 & 0xFF);
		grown->data[grown->used++] = (unsigned char) (value & 0xFF);
		return true;
	}

	bool putBytes(Grown *grown, const unsigned char *from, size_t many) {
		if (many == 0) return true;
		if (!roomFor(grown, many)) return false;
		memcpy(grown->data + grown->used, from, many);
		grown->used += many;
		return true;
	}

	bool putPadding(Grown *grown) {
		while ((grown->used & 3) != 0) {
			if (!putByte(grown, 0)) return false;
		}
		return true;
	}

	struct Scratch {
		int *ends = nullptr;
		int endsRoom = 0;
		unsigned char *flags = nullptr;
		int flagsRoom = 0;
		int *fromX = nullptr;
		int *fromY = nullptr;
		double *intoX = nullptr;
		double *intoY = nullptr;
		double *deltaX = nullptr;
		double *deltaY = nullptr;
		unsigned char *touched = nullptr;
		int pointRoom = 0;
		int *numbers = nullptr;
		int numbersRoom = 0;
		int *sharedNumbers = nullptr;
		int sharedRoom = 0;
		int *readX = nullptr;
		int readRoomX = 0;
		int *readY = nullptr;
		int readRoomY = 0;
		Piece *pieces = nullptr;
		int pieceRoom = 0;
		int pieceUsed = 0;
		Later *laters = nullptr;
		int laterRoom = 0;
		int laterUsed = 0;
	};

	void shed(Scratch *scratch) {
		free(scratch->ends);
		free(scratch->flags);
		free(scratch->fromX);
		free(scratch->fromY);
		free(scratch->intoX);
		free(scratch->intoY);
		free(scratch->deltaX);
		free(scratch->deltaY);
		free(scratch->touched);
		free(scratch->numbers);
		free(scratch->sharedNumbers);
		free(scratch->readX);
		free(scratch->readY);
		free(scratch->pieces);
		free(scratch->laters);
	}

	bool pointsFit(Scratch *scratch, int want) {
		if (scratch->pointRoom >= want) return true;

		int room = scratch->pointRoom == 0 ? 64 : scratch->pointRoom;
		while (room < want) room *= 2;

		int one = scratch->pointRoom;
		int two = scratch->pointRoom;
		int three = scratch->pointRoom;
		int four = scratch->pointRoom;
		int five = scratch->pointRoom;
		int six = scratch->pointRoom;
		int seven = scratch->pointRoom;

		if (!widen(&scratch->fromX, &one, room)) return false;
		if (!widen(&scratch->fromY, &two, room)) return false;
		if (!widen(&scratch->intoX, &three, room)) return false;
		if (!widen(&scratch->intoY, &four, room)) return false;
		if (!widen(&scratch->deltaX, &five, room)) return false;
		if (!widen(&scratch->deltaY, &six, room)) return false;
		if (!widen(&scratch->touched, &seven, room)) return false;

		scratch->pointRoom = room;
		return true;
	}

	bool readsFit(Scratch *scratch, int want) {
		if (!widen(&scratch->readX, &scratch->readRoomX, want)) return false;
		if (!widen(&scratch->readY, &scratch->readRoomY, want)) return false;
		return true;
	}

	double normalised(double user, double least, double usual, double most) {
		if (user < least) user = least;
		if (user > most) user = most;
		if (user == usual) return 0.0;

		if (user < usual) {
			if (usual == least) return 0.0;
			return quantised((user - usual) / (usual - least));
		}

		if (most == usual) return 0.0;
		return quantised((user - usual) / (most - usual));
	}

	double remapped(const unsigned char *map, const unsigned char *end, double held) {
		if (map + 2 > end) return held;

		const unsigned int pairs = wordAt(map);
		const unsigned char *at = map + 2;

		if (pairs < 2) return held;
		if (at + (size_t) pairs * 4 > end) return held;

		double wasFrom = fractionAt(at);
		double wasTo = fractionAt(at + 2);

		for (unsigned int index = 1; index < pairs; index++) {
			const double from = fractionAt(at + (size_t) index * 4);
			const double to = fractionAt(at + (size_t) index * 4 + 2);

			if (held <= from) {
				if (held <= wasFrom) return wasTo;
				if (from == wasFrom) return to;
				return quantised(wasTo + (to - wasTo) * (held - wasFrom) / (from - wasFrom));
			}

			wasFrom = from;
			wasTo = to;
		}

		return wasTo;
	}

	double scalarOf(const double *peak, const double *start, const double *stop,
			const double *coords, int axisCount) {
		double scalar = 1.0;

		for (int index = 0; index < axisCount; index++) {
			const double peaked = peak[index];
			if (peaked == 0.0) continue;

			const double held = coords[index];
			if (held == peaked) continue;

			if (held <= start[index] || held >= stop[index]) return 0.0;

			if (held < peaked) scalar *= (held - start[index]) / (peaked - start[index]);
			else scalar *= (stop[index] - held) / (stop[index] - peaked);
		}

		return scalar;
	}

	const unsigned char *packedPoints(const unsigned char *at, const unsigned char *end,
			int **into, int *room, int *made) {
		if (at + 1 > end) return nullptr;

		int count = *at++;

		if ((count & 0x80) != 0) {
			if (at + 1 > end) return nullptr;
			count = (count & 0x7F) << 8 | *at++;
		}

		*made = count;
		if (count == 0) return at;

		if (!widen(into, room, count)) return nullptr;

		int *held = *into;
		int value = 0;
		int done = 0;

		while (done < count) {
			if (at + 1 > end) return nullptr;

			const unsigned int control = *at++;
			int run = (int) (control & 0x7F) + 1;

			if (done + run > count) run = count - done;

			if ((control & 0x80) != 0) {
				if (at + (size_t) run * 2 > end) return nullptr;
				for (int step = 0; step < run; step++) {
					value += (int) wordAt(at);
					at += 2;
					held[done++] = value;
				}
			} else {
				if (at + (size_t) run > end) return nullptr;
				for (int step = 0; step < run; step++) {
					value += *at++;
					held[done++] = value;
				}
			}
		}

		return at;
	}

	const unsigned char *packedDeltas(const unsigned char *at, const unsigned char *end,
			int *into, int count) {
		int done = 0;

		while (done < count) {
			if (at + 1 > end) return nullptr;

			const unsigned int control = *at++;
			int run = (int) (control & 0x3F) + 1;

			if (done + run > count) run = count - done;

			if ((control & 0x80) != 0) {
				for (int step = 0; step < run; step++) into[done++] = 0;
			} else if ((control & 0x40) != 0) {
				if (at + (size_t) run * 2 > end) return nullptr;
				for (int step = 0; step < run; step++) {
					into[done++] = shortAt(at);
					at += 2;
				}
			} else {
				if (at + (size_t) run > end) return nullptr;
				for (int step = 0; step < run; step++) into[done++] = (int) (signed char) *at++;
			}
		}

		return at;
	}

	inline double carried(int held, int lower, int upper, double lowerDelta, double upperDelta) {
		if (lower == upper) return lowerDelta == upperDelta ? lowerDelta : 0.0;

		if (lower > upper) {
			const int swapped = lower;
			lower = upper;
			upper = swapped;

			const double moved = lowerDelta;
			lowerDelta = upperDelta;
			upperDelta = moved;
		}

		if (held <= lower) return lowerDelta;
		if (held >= upper) return upperDelta;
		if (lower == upper) return lowerDelta;

		const double ratio = (double) (held - lower) / (double) (upper - lower);
		return lowerDelta + ratio * (upperDelta - lowerDelta);
	}

	void inferred(Scratch *scratch, int contours) {
		int first = 0;

		for (int contour = 0; contour < contours; contour++) {
			const int last = scratch->ends[contour];

			if (last < first) {
				first = last + 1;
				continue;
			}

			int anchor = -1;
			int many = 0;

			for (int index = first; index <= last; index++) {
				if (scratch->touched[index] == 0) continue;
				if (anchor < 0) anchor = index;
				many++;
			}

			if (many == 0 || many == last - first + 1) {
				first = last + 1;
				continue;
			}

			if (many == 1) {
				for (int index = first; index <= last; index++) {
					if (scratch->touched[index] != 0) continue;
					scratch->deltaX[index] = scratch->deltaX[anchor];
					scratch->deltaY[index] = scratch->deltaY[anchor];
				}

				first = last + 1;
				continue;
			}

			int lower = anchor;

			for (;;) {
				int upper = lower;

				do {
					upper++;
					if (upper > last) upper = first;
				} while (scratch->touched[upper] == 0);

				int between = lower;

				for (;;) {
					between++;
					if (between > last) between = first;
					if (between == upper) break;

					scratch->deltaX[between] = carried(scratch->fromX[between],
						scratch->fromX[lower], scratch->fromX[upper],
						scratch->deltaX[lower], scratch->deltaX[upper]);

					scratch->deltaY[between] = carried(scratch->fromY[between],
						scratch->fromY[lower], scratch->fromY[upper],
						scratch->deltaY[lower], scratch->deltaY[upper]);
				}

				lower = upper;
				if (lower == anchor) break;
			}

			first = last + 1;
		}
	}
}

extern "C" int mdd_vary_weight(const unsigned char *data, long size) {
	if (data == nullptr || size < 12) return 0;

	const unsigned int tables = wordAt(data + 4);

	for (unsigned int index = 0; index < tables; index++) {
		const unsigned char *entry = data + 12 + (size_t) index * 16;
		if (entry + 16 > data + size) break;

		if (memcmp(entry, "OS/2", 4) != 0) continue;

		const unsigned long offset = longAt(entry + 8);
		if (offset + 6 > (unsigned long) size) return 0;

		return (int) wordAt(data + offset + 4);
	}

	return 0;
}

extern "C" int mdd_vary_resting(const unsigned char *data, long size) {
	if (data == nullptr || size < 12) return 0;

	const unsigned int tables = wordAt(data + 4);

	for (unsigned int index = 0; index < tables; index++) {
		const unsigned char *entry = data + 12 + (size_t) index * 16;
		if (entry + 16 > data + size) break;

		if (memcmp(entry, "fvar", 4) != 0) continue;

		const unsigned long offset = longAt(entry + 8);
		if (offset + 12 > (unsigned long) size) return 0;

		const unsigned char *fvar = data + offset;
		const unsigned int axesAt = wordAt(fvar + 4);
		const unsigned int axisCount = wordAt(fvar + 8);
		const unsigned int axisSize = wordAt(fvar + 10);

		for (unsigned int axis = 0; axis < axisCount; axis++) {
			const unsigned char *held = fvar + axesAt + (size_t) axis * axisSize;
			if (held + 20 > data + size) break;
			if (memcmp(held, "wght", 4) != 0) continue;

			return rounded(fixedAt(held + 8));
		}

		return 0;
	}

	return 0;
}

extern "C" unsigned char *mdd_vary_instance(const unsigned char *data, long size, float weight,
		long *made) {
	if (made != nullptr) *made = 0;
	if (data == nullptr || size < 12) return nullptr;

	const unsigned int tables = wordAt(data + 4);
	if (tables == 0 || tables > 512) return nullptr;
	if (12 + (size_t) tables * 16 > (size_t) size) return nullptr;

	Slot *slots = (Slot *) calloc(tables, sizeof(Slot));
	if (slots == nullptr) return nullptr;

	const unsigned char *fvar = nullptr;
	const unsigned char *avar = nullptr;
	const unsigned char *gvar = nullptr;
	const unsigned char *glyf = nullptr;
	const unsigned char *loca = nullptr;
	const unsigned char *head = nullptr;
	const unsigned char *maxp = nullptr;
	const unsigned char *hhea = nullptr;
	const unsigned char *hmtx = nullptr;

	unsigned long gvarLength = 0;
	unsigned long locaLength = 0;
	unsigned long hmtxLength = 0;
	unsigned long glyfLength = 0;
	unsigned long headLength = 0;
	unsigned long maxpLength = 0;
	unsigned long hheaLength = 0;

	for (unsigned int index = 0; index < tables; index++) {
		const unsigned char *entry = data + 12 + (size_t) index * 16;

		memcpy(slots[index].tag, entry, 4);
		slots[index].offset = longAt(entry + 8);
		slots[index].length = longAt(entry + 12);

		if (slots[index].offset > (unsigned long) size) { free(slots); return nullptr; }
		if (slots[index].offset + slots[index].length > (unsigned long) size) {
			slots[index].length = (unsigned long) size - slots[index].offset;
		}

		const unsigned char *held = data + slots[index].offset;

		if (memcmp(entry, "fvar", 4) == 0) fvar = held;
		else if (memcmp(entry, "avar", 4) == 0) avar = held;
		else if (memcmp(entry, "gvar", 4) == 0) { gvar = held; gvarLength = slots[index].length; }
		else if (memcmp(entry, "glyf", 4) == 0) { glyf = held; glyfLength = slots[index].length; }
		else if (memcmp(entry, "loca", 4) == 0) { loca = held; locaLength = slots[index].length; }
		else if (memcmp(entry, "head", 4) == 0) { head = held; headLength = slots[index].length; }
		else if (memcmp(entry, "maxp", 4) == 0) { maxp = held; maxpLength = slots[index].length; }
		else if (memcmp(entry, "hhea", 4) == 0) { hhea = held; hheaLength = slots[index].length; }
		else if (memcmp(entry, "hmtx", 4) == 0) { hmtx = held; hmtxLength = slots[index].length; }
	}

	if (fvar == nullptr || gvar == nullptr || glyf == nullptr || loca == nullptr
		|| head == nullptr || maxp == nullptr || hhea == nullptr || hmtx == nullptr) {
		free(slots);
		return nullptr;
	}

	if (headLength < 54 || maxpLength < 6 || hheaLength < 36) { free(slots); return nullptr; }

	const unsigned int axesAt = wordAt(fvar + 4);
	const unsigned int axisCount = wordAt(fvar + 8);
	const unsigned int axisSize = wordAt(fvar + 10);

	if (axisCount == 0 || axisCount > AXES || axisSize < 20) { free(slots); return nullptr; }

	double coords[AXES];
	bool moves = false;

	for (unsigned int index = 0; index < axisCount; index++) {
		const unsigned char *axis = fvar + axesAt + (size_t) index * axisSize;
		if (axis + 20 > data + size) { free(slots); return nullptr; }

		const double least = fixedAt(axis + 4);
		const double usual = fixedAt(axis + 8);
		const double most = fixedAt(axis + 12);

		const bool weighs = memcmp(axis, "wght", 4) == 0;
		coords[index] = weighs ? normalised(weight, least, usual, most) : 0.0;

		if (coords[index] != 0.0) moves = true;
	}

	if (!moves) { free(slots); return nullptr; }

	if (avar != nullptr && wordAt(avar) == 1) {
		const unsigned int mapped = wordAt(avar + 6);
		const unsigned char *at = avar + 8;
		const unsigned char *end = data + size;

		for (unsigned int index = 0; index < mapped && index < axisCount && at + 2 <= end; index++) {
			const unsigned int pairs = wordAt(at);
			coords[index] = remapped(at, end, coords[index]);
			at += 2 + (size_t) pairs * 4;
		}
	}

	const int numGlyphs = (int) wordAt(maxp + 4);
	const int longLoca = shortAt(head + 50) != 0;
	const int metrics = (int) wordAt(hhea + 34);

	if (numGlyphs <= 0) { free(slots); return nullptr; }

	const unsigned long wantLoca = (unsigned long) (numGlyphs + 1) * (longLoca ? 4 : 2);
	if (locaLength < wantLoca) { free(slots); return nullptr; }

	if (gvarLength < 20) { free(slots); return nullptr; }

	const unsigned int gvarAxes = wordAt(gvar + 4);
	const unsigned int sharedCount = wordAt(gvar + 6);
	const unsigned long sharedAt = longAt(gvar + 8);
	const int gvarGlyphs = (int) wordAt(gvar + 12);
	const unsigned int gvarFlags = wordAt(gvar + 14);
	const unsigned long gvarData = longAt(gvar + 16);

	if (gvarAxes != axisCount) { free(slots); return nullptr; }

	const int gvarLong = (gvarFlags & 1) != 0;
	const unsigned long wantOffsets = (unsigned long) (gvarGlyphs + 1) * (gvarLong ? 4 : 2);

	if (sharedAt > gvarLength || gvarData > gvarLength) { free(slots); return nullptr; }
	if (wantOffsets > gvarLength - 20) { free(slots); return nullptr; }
	if (sharedCount != 0 && sharedAt + (unsigned long) sharedCount * axisCount * 2 > gvarLength) {
		free(slots);
		return nullptr;
	}

	const unsigned char *shared = gvar + sharedAt;
	const unsigned char *gvarOffsets = gvar + 20;
	const unsigned char *varied = gvar + gvarData;

	Grown newGlyf = {nullptr, 0, 0};
	Grown newLoca = {nullptr, 0, 0};
	Scratch scratch;

	unsigned short *advances = (unsigned short *) calloc((size_t) numGlyphs, sizeof(unsigned short));
	short *bearings = (short *) calloc((size_t) numGlyphs, sizeof(short));
	short *boxes = (short *) calloc((size_t) numGlyphs * 4, sizeof(short));
	unsigned char *states = (unsigned char *) calloc((size_t) numGlyphs, 1);

	bool well = advances != nullptr && bearings != nullptr && boxes != nullptr && states != nullptr;

	for (int glyph = 0; well && glyph < numGlyphs; glyph++) {
		const unsigned long start = longLoca ? longAt(loca + (size_t) glyph * 4)
			: wordAt(loca + (size_t) glyph * 2) * 2;
		const unsigned long stop = longLoca ? longAt(loca + (size_t) (glyph + 1) * 4)
			: wordAt(loca + (size_t) (glyph + 1) * 2) * 2;

		const int paired = glyph < metrics ? glyph : metrics - 1;
		unsigned int advance = 0;
		int bearing = 0;

		if (paired >= 0 && (unsigned long) paired * 4 + 4 <= hmtxLength) {
			advance = wordAt(hmtx + (size_t) paired * 4);
			bearing = shortAt(hmtx + (size_t) paired * 4 + 2);
		}

		if (glyph >= metrics) {
			const unsigned long spare = (unsigned long) metrics * 4
				+ (unsigned long) (glyph - metrics) * 2;

			bearing = spare + 2 <= hmtxLength ? shortAt(hmtx + spare) : 0;
		}

		advances[glyph] = (unsigned short) advance;
		bearings[glyph] = (short) bearing;

		if (!putLong(&newLoca, (unsigned long) newGlyf.used)) { well = false; break; }

		if (start > glyfLength || stop > glyfLength) { well = false; break; }

		const bool blank = stop <= start || stop - start < 10;

		const unsigned char *entry = glyf + start;
		const unsigned char *entryEnd = glyf + stop;
		const int contours = blank ? 0 : shortAt(entry);

		boxes[glyph * 4] = blank ? 0 : (short) shortAt(entry + 2);
		boxes[glyph * 4 + 1] = blank ? 0 : (short) shortAt(entry + 4);
		boxes[glyph * 4 + 2] = blank ? 0 : (short) shortAt(entry + 6);
		boxes[glyph * 4 + 3] = blank ? 0 : (short) shortAt(entry + 8);
		states[glyph] = blank ? BOX_EMPTY : contours >= 0 ? BOX_KNOWN : BOX_UNKNOWN;

		const unsigned char *tuples = nullptr;
		const unsigned char *tuplesEnd = nullptr;

		if (glyph < gvarGlyphs) {
			const unsigned long from = gvarLong ? longAt(gvarOffsets + (size_t) glyph * 4)
				: wordAt(gvarOffsets + (size_t) glyph * 2) * 2;
			const unsigned long till = gvarLong ? longAt(gvarOffsets + (size_t) (glyph + 1) * 4)
				: wordAt(gvarOffsets + (size_t) (glyph + 1) * 2) * 2;

			if (till > from && gvarData + till <= gvarLength && till - from >= 4) {
				tuples = varied + from;
				tuplesEnd = varied + till;
			}
		}

		if (tuples == nullptr && contours >= 0) {
			if (blank) continue;
			if (!putBytes(&newGlyf, entry, (size_t) (stop - start))) { well = false; break; }
			if (!putPadding(&newGlyf)) { well = false; break; }
			continue;
		}

		int points = 0;
		int total = 0;
		const unsigned char *instructions = nullptr;
		unsigned int instructionBytes = 0;

		const int pieceFrom = scratch.pieceUsed;

		if (blank) {
			total = 4;
			if (!pointsFit(&scratch, total)) { well = false; break; }
		} else if (contours >= 0) {
			if (!widen(&scratch.ends, &scratch.endsRoom, contours + 1)) { well = false; break; }

			const unsigned char *at = entry + 10;
			if (at + (size_t) contours * 2 + 2 > entryEnd) { well = false; break; }

			for (int contour = 0; contour < contours; contour++) {
				scratch.ends[contour] = (int) wordAt(at + (size_t) contour * 2);
			}

			points = contours == 0 ? 0 : scratch.ends[contours - 1] + 1;
			at += (size_t) contours * 2;

			instructionBytes = wordAt(at);
			at += 2;
			instructions = at;
			at += instructionBytes;

			if (points < 0 || at > entryEnd) { well = false; break; }

			total = points + 4;
			if (!pointsFit(&scratch, total)) { well = false; break; }
			if (!widen(&scratch.flags, &scratch.flagsRoom, total)) { well = false; break; }

			int read = 0;

			while (read < points) {
				if (at >= entryEnd) { well = false; break; }

				const unsigned int flag = *at++;
				scratch.flags[read++] = (unsigned char) flag;

				if ((flag & REPEATS) == 0) continue;
				if (at >= entryEnd) { well = false; break; }

				int again = *at++;
				while (again-- > 0 && read < points) scratch.flags[read++] = (unsigned char) flag;
			}

			if (!well || read < points) { well = false; break; }

			int value = 0;

			for (int index = 0; index < points; index++) {
				const unsigned int flag = scratch.flags[index];

				if ((flag & X_SHORT) != 0) {
					if (at >= entryEnd) { well = false; break; }
					const int step = *at++;
					value += (flag & X_SAME) != 0 ? step : -step;
				} else if ((flag & X_SAME) == 0) {
					if (at + 2 > entryEnd) { well = false; break; }
					value += shortAt(at);
					at += 2;
				}

				scratch.fromX[index] = value;
			}

			if (!well) break;
			value = 0;

			for (int index = 0; index < points; index++) {
				const unsigned int flag = scratch.flags[index];

				if ((flag & Y_SHORT) != 0) {
					if (at >= entryEnd) { well = false; break; }
					const int step = *at++;
					value += (flag & Y_SAME) != 0 ? step : -step;
				} else if ((flag & Y_SAME) == 0) {
					if (at + 2 > entryEnd) { well = false; break; }
					value += shortAt(at);
					at += 2;
				}

				scratch.fromY[index] = value;
			}

			if (!well) break;
		} else {
			const unsigned char *at = entry + 10;
			unsigned int flags = MORE_COMPONENTS;

			while ((flags & MORE_COMPONENTS) != 0) {
				if (at + 4 > entryEnd) { well = false; break; }

				flags = wordAt(at);
				const unsigned int which = wordAt(at + 2);
				at += 4;

				int argOne = 0;
				int argTwo = 0;

				if ((flags & ARGS_ARE_WORDS) != 0) {
					if (at + 4 > entryEnd) { well = false; break; }
					argOne = shortAt(at);
					argTwo = shortAt(at + 2);
					at += 4;
				} else {
					if (at + 2 > entryEnd) { well = false; break; }
					argOne = (int) (signed char) at[0];
					argTwo = (int) (signed char) at[1];
					at += 2;
				}

				int shapeBytes = 0;
				if ((flags & HAVE_A_SCALE) != 0) shapeBytes = 2;
				else if ((flags & HAVE_XY_SCALE) != 0) shapeBytes = 4;
				else if ((flags & HAVE_TWO_BY_TWO) != 0) shapeBytes = 8;

				if (at + shapeBytes > entryEnd) { well = false; break; }

				if (!widen(&scratch.pieces, &scratch.pieceRoom, scratch.pieceUsed + 1)) {
					well = false;
					break;
				}

				Piece *piece = scratch.pieces + scratch.pieceUsed++;
				piece->flags = flags;
				piece->index = which;
				piece->argOne = argOne;
				piece->argTwo = argTwo;
				piece->shapeBytes = shapeBytes;

				if (shapeBytes > 0) memcpy(piece->shape, at, (size_t) shapeBytes);
				at += shapeBytes;
			}

			if (!well) break;

			if ((flags & HAVE_INSTRUCTIONS) != 0 && at + 2 <= entryEnd) {
				instructionBytes = wordAt(at);
				at += 2;
				instructions = at;
				if (at + instructionBytes > entryEnd) instructionBytes = 0;
			}

			points = scratch.pieceUsed - pieceFrom;
			total = points + 4;

			if (!pointsFit(&scratch, total)) { well = false; break; }

			for (int index = 0; index < points; index++) {
				const Piece *piece = scratch.pieces + pieceFrom + index;
				const bool placed = (piece->flags & ARGS_ARE_XY) != 0;

				scratch.fromX[index] = placed ? piece->argOne : 0;
				scratch.fromY[index] = placed ? piece->argTwo : 0;
			}
		}

		scratch.fromX[points] = boxes[glyph * 4] - bearing;
		scratch.fromY[points] = 0;
		scratch.fromX[points + 1] = scratch.fromX[points] + (int) advance;
		scratch.fromY[points + 1] = 0;
		scratch.fromX[points + 2] = 0;
		scratch.fromY[points + 2] = 0;
		scratch.fromX[points + 3] = 0;
		scratch.fromY[points + 3] = 0;

		for (int index = 0; index < total; index++) {
			scratch.intoX[index] = (double) scratch.fromX[index];
			scratch.intoY[index] = (double) scratch.fromY[index];
		}

		const unsigned int header = tuples == nullptr ? 0 : wordAt(tuples);
		const unsigned int serialAt = tuples == nullptr ? 0 : wordAt(tuples + 2);
		const int howMany = (int) (header & 0x0FFF);

		const unsigned char *reading = tuples == nullptr ? nullptr : tuples + 4;
		const unsigned char *serial = tuples == nullptr ? nullptr : tuples + serialAt;

		int sharedMade = -1;

		if ((header & 0x8000) != 0) {
			serial = packedPoints(serial, tuplesEnd, &scratch.sharedNumbers, &scratch.sharedRoom,
				&sharedMade);
			if (serial == nullptr) { well = false; break; }
		}

		for (int tuple = 0; tuple < howMany; tuple++) {
			if (reading + 4 > tuplesEnd) { well = false; break; }

			const unsigned int span = wordAt(reading);
			const unsigned int which = wordAt(reading + 2);
			reading += 4;

			double peak[AXES];
			double began[AXES];
			double ended[AXES];

			if ((which & 0x8000) != 0) {
				if (reading + (size_t) axisCount * 2 > tuplesEnd) { well = false; break; }
				for (unsigned int axis = 0; axis < axisCount; axis++) {
					peak[axis] = fractionAt(reading + (size_t) axis * 2);
				}
				reading += (size_t) axisCount * 2;
			} else {
				const unsigned int slot = which & 0x0FFF;
				if (slot >= sharedCount) { well = false; break; }

				const unsigned char *from = shared + (size_t) slot * axisCount * 2;
				if (from + (size_t) axisCount * 2 > data + size) { well = false; break; }

				for (unsigned int axis = 0; axis < axisCount; axis++) {
					peak[axis] = fractionAt(from + (size_t) axis * 2);
				}
			}

			if ((which & 0x4000) != 0) {
				if (reading + (size_t) axisCount * 4 > tuplesEnd) { well = false; break; }
				for (unsigned int axis = 0; axis < axisCount; axis++) {
					began[axis] = fractionAt(reading + (size_t) axis * 2);
					ended[axis] = fractionAt(reading + (size_t) axisCount * 2 + (size_t) axis * 2);
				}
				reading += (size_t) axisCount * 4;
			} else {
				for (unsigned int axis = 0; axis < axisCount; axis++) {
					began[axis] = peak[axis] < 0.0 ? peak[axis] : 0.0;
					ended[axis] = peak[axis] > 0.0 ? peak[axis] : 0.0;
				}
			}

			const unsigned char *next = serial + span;
			const double scalar = scalarOf(peak, began, ended, coords, (int) axisCount);

			if (scalar == 0.0) { serial = next; continue; }

			const unsigned char *step = serial;
			const int *chosen = scratch.sharedNumbers;
			int many = sharedMade;

			if ((which & 0x2000) != 0) {
				step = packedPoints(step, next, &scratch.numbers, &scratch.numbersRoom, &many);
				if (step == nullptr) { well = false; break; }
				chosen = scratch.numbers;
			}

			if (many < 0) { serial = next; continue; }

			const int reads = many == 0 ? total : many;

			if (!readsFit(&scratch, reads)) { well = false; break; }

			step = packedDeltas(step, next, scratch.readX, reads);
			if (step == nullptr) { well = false; break; }

			step = packedDeltas(step, next, scratch.readY, reads);
			if (step == nullptr) { well = false; break; }

			if (many == 0) {
				for (int index = 0; index < total; index++) {
					scratch.intoX[index] += scalar * (double) scratch.readX[index];
					scratch.intoY[index] += scalar * (double) scratch.readY[index];
				}

				serial = next;
				continue;
			}

			memset(scratch.deltaX, 0, (size_t) total * sizeof(double));
			memset(scratch.deltaY, 0, (size_t) total * sizeof(double));
			memset(scratch.touched, 0, (size_t) total);

			for (int index = 0; index < many; index++) {
				const int where = chosen[index];
				if (where < 0 || where >= total) continue;

				scratch.deltaX[where] = (double) scratch.readX[index];
				scratch.deltaY[where] = (double) scratch.readY[index];
				scratch.touched[where] = 1;
			}

			if (contours > 0) inferred(&scratch, contours);

			for (int index = 0; index < total; index++) {
				scratch.intoX[index] += scalar * scratch.deltaX[index];
				scratch.intoY[index] += scalar * scratch.deltaY[index];
			}

			serial = next;
		}

		if (!well) break;

		const int origin = rounded(scratch.intoX[points]);
		const int reach = rounded(scratch.intoX[points + 1]);
		const int wide = reach - origin;

		advances[glyph] = (unsigned short) (wide < 0 ? 0 : wide > 65535 ? 65535 : wide);

		if (contours >= 0) {
			int least = 0;
			int most = 0;
			int lowest = 0;
			int highest = 0;

			for (int index = 0; index < points; index++) {
				const int held = rounded(scratch.intoX[index]);
				const int lift = rounded(scratch.intoY[index]);

				if (index == 0 || held < least) least = held;
				if (index == 0 || held > most) most = held;
				if (index == 0 || lift < lowest) lowest = lift;
				if (index == 0 || lift > highest) highest = lift;
			}

			boxes[glyph * 4] = (short) least;
			boxes[glyph * 4 + 1] = (short) lowest;
			boxes[glyph * 4 + 2] = (short) most;
			boxes[glyph * 4 + 3] = (short) highest;
			states[glyph] = points == 0 ? BOX_EMPTY : BOX_KNOWN;
			bearings[glyph] = points == 0 ? 0 : (short) (least - origin);

			if (points == 0) continue;

			if (!putWord(&newGlyf, (unsigned int) contours)) { well = false; break; }
			if (!putWord(&newGlyf, (unsigned int) least)) { well = false; break; }
			if (!putWord(&newGlyf, (unsigned int) lowest)) { well = false; break; }
			if (!putWord(&newGlyf, (unsigned int) most)) { well = false; break; }
			if (!putWord(&newGlyf, (unsigned int) highest)) { well = false; break; }

			for (int contour = 0; contour < contours; contour++) {
				if (!putWord(&newGlyf, (unsigned int) scratch.ends[contour])) { well = false; break; }
			}

			if (!well) break;

			if (!putWord(&newGlyf, instructionBytes)) { well = false; break; }
			if (instructionBytes > 0 && !putBytes(&newGlyf, instructions, instructionBytes)) {
				well = false;
				break;
			}

			Grown alongX = {nullptr, 0, 0};
			Grown alongY = {nullptr, 0, 0};
			bool laid = true;

			int wasX = 0;
			int wasY = 0;

			for (int index = 0; index < points && laid; index++) {
				const int nowX = rounded(scratch.intoX[index]);
				const int nowY = rounded(scratch.intoY[index]);

				int stepX = nowX - wasX;
				int stepY = nowY - wasY;

				if (stepX < -32768) stepX = -32768;
				if (stepX > 32767) stepX = 32767;
				if (stepY < -32768) stepY = -32768;
				if (stepY > 32767) stepY = 32767;

				unsigned int flag = scratch.flags[index] & (ON_CURVE | OVERLAPS);

				if (stepX == 0) {
					flag |= X_SAME;
				} else if (stepX >= -255 && stepX <= 255) {
					flag |= X_SHORT;
					if (stepX > 0) flag |= X_SAME;
					laid = putByte(&alongX, (unsigned int) (stepX < 0 ? -stepX : stepX));
				} else {
					laid = putWord(&alongX, (unsigned int) stepX);
				}

				if (stepY == 0) {
					flag |= Y_SAME;
				} else if (stepY >= -255 && stepY <= 255) {
					flag |= Y_SHORT;
					if (stepY > 0) flag |= Y_SAME;
					laid = laid && putByte(&alongY, (unsigned int) (stepY < 0 ? -stepY : stepY));
				} else {
					laid = laid && putWord(&alongY, (unsigned int) stepY);
				}

				scratch.flags[index] = (unsigned char) flag;

				wasX += stepX;
				wasY += stepY;
			}

			for (int index = 0; index < points && laid;) {
				const unsigned int flag = scratch.flags[index];
				int run = 1;

				while (index + run < points && scratch.flags[index + run] == flag && run < 256) run++;

				if (run < 2) {
					laid = putByte(&newGlyf, flag);
					index++;
					continue;
				}

				laid = putByte(&newGlyf, flag | REPEATS) && putByte(&newGlyf, (unsigned int) (run - 1));
				index += run;
			}

			laid = laid && putBytes(&newGlyf, alongX.data, alongX.used);
			laid = laid && putBytes(&newGlyf, alongY.data, alongY.used);

			free(alongX.data);
			free(alongY.data);

			if (!laid || !putPadding(&newGlyf)) { well = false; break; }
			continue;
		}

		const size_t sits = newGlyf.used;

		if (!putWord(&newGlyf, 0xFFFF)) { well = false; break; }
		if (!putBytes(&newGlyf, entry + 2, 8)) { well = false; break; }

		if (!widen(&scratch.laters, &scratch.laterRoom, scratch.laterUsed + 1)) { well = false; break; }

		bool laid = true;

		for (int index = 0; index < points && laid; index++) {
			Piece *piece = scratch.pieces + pieceFrom + index;
			unsigned int flags = piece->flags;

			int argOne = piece->argOne;
			int argTwo = piece->argTwo;

			if ((flags & ARGS_ARE_XY) != 0) {
				argOne = rounded(scratch.intoX[index]);
				argTwo = rounded(scratch.intoY[index]);

				if (argOne < -128 || argOne > 127 || argTwo < -128 || argTwo > 127) {
					flags |= ARGS_ARE_WORDS;
				}
			}

			if (index + 1 < points) flags |= MORE_COMPONENTS;
			else flags &= ~MORE_COMPONENTS;

			if (index + 1 == points && instructionBytes > 0) flags |= HAVE_INSTRUCTIONS;
			else if (index + 1 == points) flags &= ~HAVE_INSTRUCTIONS;

			piece->flags = flags;
			piece->argOne = argOne;
			piece->argTwo = argTwo;

			laid = putWord(&newGlyf, flags) && putWord(&newGlyf, piece->index);

			if ((flags & ARGS_ARE_WORDS) != 0) {
				laid = laid && putWord(&newGlyf, (unsigned int) argOne)
					&& putWord(&newGlyf, (unsigned int) argTwo);
			} else {
				laid = laid && putByte(&newGlyf, (unsigned int) argOne & 0xFF)
					&& putByte(&newGlyf, (unsigned int) argTwo & 0xFF);
			}

			if (piece->shapeBytes > 0) {
				laid = laid && putBytes(&newGlyf, piece->shape, (size_t) piece->shapeBytes);
			}
		}

		if (laid && instructionBytes > 0) {
			laid = putWord(&newGlyf, instructionBytes)
				&& putBytes(&newGlyf, instructions, instructionBytes);
		}

		if (!laid || !putPadding(&newGlyf)) { well = false; break; }

		Later *later = scratch.laters + scratch.laterUsed++;
		later->glyph = (unsigned int) glyph;
		later->where = sits + 2;
		later->first = pieceFrom;
		later->many = points;
		later->origin = origin;

		states[glyph] = BOX_UNKNOWN;
	}

	if (well && !putLong(&newLoca, (unsigned long) newGlyf.used)) well = false;

	Grown newHmtx = {nullptr, 0, 0};

	for (int round = 0; well && round < NESTED; round++) {
		const bool forced = round + 1 == NESTED;
		bool moved = false;

		for (int index = 0; index < scratch.laterUsed; index++) {
			const Later *later = scratch.laters + index;
			const unsigned int glyph = later->glyph;

			if (states[glyph] != BOX_UNKNOWN) continue;

			if (!forced) {
				bool waits = false;

				for (int step = 0; step < later->many; step++) {
					const Piece *piece = scratch.pieces + later->first + step;
					if (piece->index >= (unsigned int) numGlyphs) continue;
					if (piece->index == glyph) continue;
					if (states[piece->index] == BOX_UNKNOWN) waits = true;
				}

				if (waits) continue;
			}

			int least = 0;
			int lowest = 0;
			int most = 0;
			int highest = 0;
			bool any = false;

			for (int step = 0; step < later->many; step++) {
				const Piece *piece = scratch.pieces + later->first + step;
				if (piece->index >= (unsigned int) numGlyphs) continue;
				if (states[piece->index] == BOX_EMPTY) continue;

				float scaleX = 1.0f;
				float scaleY = 1.0f;
				float skewX = 0.0f;
				float skewY = 0.0f;

				if ((piece->flags & HAVE_A_SCALE) != 0) {
					scaleX = scaleY = fractionAt(piece->shape);
				} else if ((piece->flags & HAVE_XY_SCALE) != 0) {
					scaleX = fractionAt(piece->shape);
					scaleY = fractionAt(piece->shape + 2);
				} else if ((piece->flags & HAVE_TWO_BY_TWO) != 0) {
					scaleX = fractionAt(piece->shape);
					skewY = fractionAt(piece->shape + 2);
					skewX = fractionAt(piece->shape + 4);
					scaleY = fractionAt(piece->shape + 6);
				}

				const int placed = (piece->flags & ARGS_ARE_XY) != 0;
				const float shiftX = placed ? (float) piece->argOne : 0.0f;
				const float shiftY = placed ? (float) piece->argTwo : 0.0f;

				const short *box = boxes + (size_t) piece->index * 4;

				for (int corner = 0; corner < 4; corner++) {
					const float held = (float) box[(corner & 1) != 0 ? 2 : 0];
					const float lift = (float) box[(corner & 2) != 0 ? 3 : 1];

					const int atX = rounded(held * scaleX + lift * skewX + shiftX);
					const int atY = rounded(held * skewY + lift * scaleY + shiftY);

					if (!any || atX < least) least = atX;
					if (!any || atX > most) most = atX;
					if (!any || atY < lowest) lowest = atY;
					if (!any || atY > highest) highest = atY;
					any = true;
				}
			}

			moved = true;

			if (!any) {
				states[glyph] = BOX_EMPTY;
				continue;
			}

			boxes[glyph * 4] = (short) least;
			boxes[glyph * 4 + 1] = (short) lowest;
			boxes[glyph * 4 + 2] = (short) most;
			boxes[glyph * 4 + 3] = (short) highest;
			states[glyph] = BOX_KNOWN;
			bearings[glyph] = (short) (least - later->origin);

			unsigned char *at = newGlyf.data + later->where;

			at[0] = (unsigned char) ((unsigned int) least >> 8 & 0xFF);
			at[1] = (unsigned char) ((unsigned int) least & 0xFF);
			at[2] = (unsigned char) ((unsigned int) lowest >> 8 & 0xFF);
			at[3] = (unsigned char) ((unsigned int) lowest & 0xFF);
			at[4] = (unsigned char) ((unsigned int) most >> 8 & 0xFF);
			at[5] = (unsigned char) ((unsigned int) most & 0xFF);
			at[6] = (unsigned char) ((unsigned int) highest >> 8 & 0xFF);
			at[7] = (unsigned char) ((unsigned int) highest & 0xFF);
		}

		if (!moved) break;
	}

	for (int glyph = 0; glyph < numGlyphs && well; glyph++) {
		well = putWord(&newHmtx, advances[glyph])
			&& putWord(&newHmtx, (unsigned int) bearings[glyph] & 0xFFFF);
	}

	shed(&scratch);
	free(advances);
	free(bearings);
	free(boxes);
	free(states);

	if (!well) {
		free(newGlyf.data);
		free(newLoca.data);
		free(newHmtx.data);
		free(slots);
		return nullptr;
	}

	static const char *const dropped[] = {"fvar", "gvar", "avar", "cvar", "HVAR", "VVAR", "MVAR",
		"STAT"};

	int kept = 0;

	for (unsigned int index = 0; index < tables; index++) {
		bool skip = false;

		for (size_t named = 0; named < sizeof(dropped) / sizeof(dropped[0]); named++) {
			if (memcmp(slots[index].tag, dropped[named], 4) == 0) skip = true;
		}

		if (!skip) kept++;
	}

	size_t total = 12 + (size_t) kept * 16;

	for (unsigned int index = 0; index < tables; index++) {
		bool skip = false;

		for (size_t named = 0; named < sizeof(dropped) / sizeof(dropped[0]); named++) {
			if (memcmp(slots[index].tag, dropped[named], 4) == 0) skip = true;
		}

		if (skip) continue;

		unsigned long length = slots[index].length;

		if (memcmp(slots[index].tag, "glyf", 4) == 0) length = (unsigned long) newGlyf.used;
		else if (memcmp(slots[index].tag, "loca", 4) == 0) length = (unsigned long) newLoca.used;
		else if (memcmp(slots[index].tag, "hmtx", 4) == 0) length = (unsigned long) newHmtx.used;

		total += (length + 3) & ~(size_t) 3;
	}

	unsigned char *out = (unsigned char *) calloc(total, 1);

	if (out == nullptr) {
		free(newGlyf.data);
		free(newLoca.data);
		free(newHmtx.data);
		free(slots);
		return nullptr;
	}

	memcpy(out, data, 4);

	unsigned int power = 1;
	unsigned int selector = 0;

	while (power * 2 <= (unsigned int) kept) { power *= 2; selector++; }

	out[4] = (unsigned char) (kept >> 8 & 0xFF);
	out[5] = (unsigned char) (kept & 0xFF);
	out[6] = (unsigned char) (power * 16 >> 8 & 0xFF);
	out[7] = (unsigned char) (power * 16 & 0xFF);
	out[8] = (unsigned char) (selector >> 8 & 0xFF);
	out[9] = (unsigned char) (selector & 0xFF);
	out[10] = (unsigned char) ((unsigned int) (kept * 16 - (int) power * 16) >> 8 & 0xFF);
	out[11] = (unsigned char) ((unsigned int) (kept * 16 - (int) power * 16) & 0xFF);

	size_t entry = 12;
	size_t where = 12 + (size_t) kept * 16;
	size_t headAt = 0;

	for (unsigned int index = 0; index < tables; index++) {
		bool skip = false;

		for (size_t named = 0; named < sizeof(dropped) / sizeof(dropped[0]); named++) {
			if (memcmp(slots[index].tag, dropped[named], 4) == 0) skip = true;
		}

		if (skip) continue;

		const unsigned char *from = data + slots[index].offset;
		unsigned long length = slots[index].length;

		if (memcmp(slots[index].tag, "glyf", 4) == 0) {
			from = newGlyf.data;
			length = (unsigned long) newGlyf.used;
		} else if (memcmp(slots[index].tag, "loca", 4) == 0) {
			from = newLoca.data;
			length = (unsigned long) newLoca.used;
		} else if (memcmp(slots[index].tag, "hmtx", 4) == 0) {
			from = newHmtx.data;
			length = (unsigned long) newHmtx.used;
		}

		if (length > 0 && from != nullptr) memcpy(out + where, from, length);

		if (memcmp(slots[index].tag, "head", 4) == 0) {
			headAt = where;
			out[where + 51] = 1;
			out[where + 50] = 0;
			out[where + 8] = 0;
			out[where + 9] = 0;
			out[where + 10] = 0;
			out[where + 11] = 0;
		} else if (memcmp(slots[index].tag, "hhea", 4) == 0) {
			out[where + 34] = (unsigned char) ((unsigned int) numGlyphs >> 8 & 0xFF);
			out[where + 35] = (unsigned char) ((unsigned int) numGlyphs & 0xFF);
		} else if (memcmp(slots[index].tag, "OS/2", 4) == 0 && length >= 6) {
			const int asked = rounded(weight);
			out[where + 4] = (unsigned char) ((unsigned int) asked >> 8 & 0xFF);
			out[where + 5] = (unsigned char) ((unsigned int) asked & 0xFF);
		}

		memcpy(out + entry, slots[index].tag, 4);

		unsigned long sum = 0;

		for (size_t step = 0; step < ((length + 3) & ~(size_t) 3); step += 4) {
			sum += longAt(out + where + step);
			sum &= 0xFFFFFFFFul;
		}

		out[entry + 4] = (unsigned char) (sum >> 24 & 0xFF);
		out[entry + 5] = (unsigned char) (sum >> 16 & 0xFF);
		out[entry + 6] = (unsigned char) (sum >> 8 & 0xFF);
		out[entry + 7] = (unsigned char) (sum & 0xFF);

		out[entry + 8] = (unsigned char) (where >> 24 & 0xFF);
		out[entry + 9] = (unsigned char) (where >> 16 & 0xFF);
		out[entry + 10] = (unsigned char) (where >> 8 & 0xFF);
		out[entry + 11] = (unsigned char) (where & 0xFF);

		out[entry + 12] = (unsigned char) (length >> 24 & 0xFF);
		out[entry + 13] = (unsigned char) (length >> 16 & 0xFF);
		out[entry + 14] = (unsigned char) (length >> 8 & 0xFF);
		out[entry + 15] = (unsigned char) (length & 0xFF);

		entry += 16;
		where += (length + 3) & ~(size_t) 3;
	}

	if (headAt != 0) {
		unsigned long sum = 0;

		for (size_t step = 0; step + 4 <= total; step += 4) {
			sum += longAt(out + step);
			sum &= 0xFFFFFFFFul;
		}

		const unsigned long adjust = (0xB1B0AFBAul - sum) & 0xFFFFFFFFul;

		out[headAt + 8] = (unsigned char) (adjust >> 24 & 0xFF);
		out[headAt + 9] = (unsigned char) (adjust >> 16 & 0xFF);
		out[headAt + 10] = (unsigned char) (adjust >> 8 & 0xFF);
		out[headAt + 11] = (unsigned char) (adjust & 0xFF);
	}

	free(newGlyf.data);
	free(newLoca.data);
	free(newHmtx.data);
	free(slots);

	if (made != nullptr) *made = (long) total;
	return out;
}
