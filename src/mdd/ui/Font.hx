package mdd.ui;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Text;
import mdd.host.Texture;

@:unreflective

/**
	One face at one size: an atlas of glyphs on the card, and where each one sits in
	it.

	The Latin range is baked in one pass at load, and anything outside it is drawn into
	a free corner of the atlas the first time it is asked for. A glyph the face does
	not have is looked for in the fallback faces, which are not read until the first
	miss.
**/
final class Font {
	/**
		The first codepoint baked at load.
	**/
	public static inline final FIRST = 32;

	/**
		The last.
	**/
	public static inline final LAST = 255;
	static inline final GLYPHS = LAST - FIRST + 1;
	static inline final WIDEST = 2048;
	static inline final PAIRED = 0x10000;

	static inline final CACHE = 1024;
	static inline final BUCKETS = 256;

	static inline final SCRATCH = 192;

	/**
		What `slotOf` answers for a glyph nobody has.
	**/
	public static inline final NONE = -1;

	static inline final FLOATS = 9;
	static inline final SOLID = 8;

	/**
		The size the face was baked at.
	**/
	public var pixels(default, null):Float;

	/**
		How far above the baseline it reaches.
	**/
	public var ascent(default, null):Float;

	/**
		How far below.
	**/
	public var descent(default, null):Float;

	/**
		How far apart two lines sit.
	**/
	public var line(default, null):Float;

	/**
		Ascent plus descent.
	**/
	public var height(default, null):Float;

	/**
		How wide the atlas is.
	**/
	public var atlasWidth(default, null):Int;

	/**
		How tall it is.
	**/
	public var atlasHeight(default, null):Int;

	/**
		Where the one opaque pixel sits in the atlas, across. Every filled shape samples it,
		so a rectangle and a run of glyphs are the same draw call.
	**/
	public var solidU(default, null):Float;

	/**
		Where it sits, down.
	**/
	public var solidV(default, null):Float;

	/**
		How many glyphs are in the atlas.
	**/
	public var kept(default, null):Int = 0;

	/**
		How many were asked for that nobody had.
	**/
	public var missed(default, null):Int = 0;

	/**
		The atlas on the card.
	**/
	public var texture(default, null):cpp.Star<Texture>;

	final metrics:Vector<Single> = new Vector<Single>((GLYPHS + CACHE) * FLOATS);
	var codes:Vector<Int> = new Vector<Int>(BUCKETS);
	var slots:Vector<Int> = new Vector<Int>(BUCKETS);
	var stored:Int = 0;

	final asked:Vector<Int> = new Vector<Int>(2);
	final scratch:Vector<cpp.UInt8> = new Vector<cpp.UInt8>(SCRATCH * SCRATCH * 4);

	var face:Int = -1;
	var beside:Null<Fallback> = null;

	var shelfX:Int = 0;
	var shelfY:Int = 0;
	var shelfTall:Int = 0;

	/**
		Private: use `bake`.
	**/
	function new() {
		for (at in 0...BUCKETS) codes[at] = 0;
	}

	/**
		Reads a face, bakes the Latin range into an atlas, and uploads it.

		@param renderer The renderer to upload to.
		@param path The font file.
		@param pixels The size to bake at.
		@return The face, or null where it would not read.
	**/
	public static function bake(renderer:cpp.Star<Canvas>, path:String, pixels:Float):Null<Font> {
		final face = Text.load(path);
		if (face < 0) return null;

		final font = new Font();
		font.face = face;
		font.pixels = pixels;
		font.ascent = Text.ascent(face, pixels);
		font.descent = Text.descent(face, pixels);
		font.line = Text.line(face, pixels);
		font.height = Math.ceil(font.ascent + font.descent);

		var side = 128;
		while (side * side < Std.int(pixels * pixels * GLYPHS * 2.2)) side <<= 1;
		if (side > WIDEST) side = WIDEST;

		var rgba = new Vector<cpp.UInt8>(side * side * 4);
		var done = 0;

		while (true) {
			done = Text.bake(face, pixels, FIRST, GLYPHS,
				cpp.Pointer.arrayElem(rgba.toData(), 0).raw, side, side,
				cpp.Pointer.arrayElem(font.metrics.toData(), 0).raw);

			if (done != 0 || side >= WIDEST) break;

			side <<= 1;
			rgba = new Vector<cpp.UInt8>(side * side * 4);
		}

		if (done == 0) {
			Text.free(face);
			return null;
		}

		font.atlasWidth = side;
		font.atlasHeight = side * 2;

		font.halves();

		font.texture = Draw.createTexture(renderer, font.atlasWidth, font.atlasHeight);
		Draw.patchTexture(font.texture, cpp.Pointer.arrayElem(rgba.toData(), 0).constRaw,
			0, 0, side, side);

		font.solid();

		font.shelfX = 0;
		font.shelfY = side + SOLID;
		font.shelfTall = 0;

		return font;
	}

	/**
		Halves the atlas where the baked range left most of it empty, so a small face does
		not hold a large texture.
	**/
	function halves():Void {
		for (index in 0...GLYPHS) {
			final base = index * FLOATS;

			metrics[base + 1] = metrics[base + 1] * 0.5;
			metrics[base + 3] = metrics[base + 3] * 0.5;
		}
	}

	/**
		Puts one opaque pixel in the atlas, which every filled shape samples.
	**/
	function solid():Void {
		for (index in 0...SOLID * SOLID) {
			scratch[index * 4] = 255;
			scratch[index * 4 + 1] = 255;
			scratch[index * 4 + 2] = 255;
			scratch[index * 4 + 3] = 255;
		}

		final top = atlasHeight - SOLID;

		Draw.patchTexture(texture, cpp.Pointer.arrayElem(scratch.toData(), 0).constRaw,
			0, top, SOLID, SOLID);

		solidU = (SOLID * 0.5) / atlasWidth;
		solidV = (top + SOLID * 0.5) / atlasHeight;
	}

	/**
		Gives this face the list to look in when it does not have a glyph.

		@param next The fallback faces, or null for none.
	**/
	public function chains(next:Null<Fallback>):Void {
		beside = next;
		rehashes(codes.length, true);
		missed = 0;
	}

	/**
		@param code A codepoint outside the baked range.
		@return The bucket holding it, or the empty one where it would go.
	**/
	inline function bucketOf(code:Int):Int {
		final mask = codes.length - 1;
		var at = code & mask;

		while (codes[at] != 0 && codes[at] != code) at = (at + 1) & mask;

		return at;
	}

	/**
		Keeps a lookup, doubling the table first where it would be more than half full.

		@param code A codepoint outside the baked range.
		@param slot Its slot, or `NONE`.
	**/
	function stores(code:Int, slot:Int):Void {
		if ((stored + 1) * 2 > codes.length) rehashes(codes.length * 2, false);

		final at = bucketOf(code);

		codes[at] = code;
		slots[at] = slot;
		stored++;
	}

	/**
		Moves every kept lookup into a table of a new size.

		@param size How many buckets, a power of two.
		@param found Whether to keep only the glyphs that were found, forgetting the misses so
			they are asked for again.
	**/
	function rehashes(size:Int, found:Bool):Void {
		final wereCodes = codes;
		final wereSlots = slots;

		codes = new Vector<Int>(size);
		slots = new Vector<Int>(size);
		stored = 0;

		for (at in 0...size) codes[at] = 0;

		for (at in 0...wereCodes.length) {
			final code = wereCodes[at];
			if (code == 0 || (found && wereSlots[at] == NONE)) continue;

			final into = bucketOf(code);

			codes[into] = code;
			slots[into] = wereSlots[at];
			stored++;
		}
	}

	/**
		Finds a glyph, drawing it into the atlas if it is not there yet.

		@param code A codepoint.
		@return Its slot, or `NONE` where nobody has it.
	**/
	public inline function slotOf(code:Int):Int {
		return code >= FIRST && code <= LAST ? (code - FIRST) * FLOATS : extra(code);
	}

	/**
		Finds a glyph outside the baked range.

		@param code A codepoint.
		@return Its slot, or `NONE`.
	**/
	function extra(code:Int):Int {
		if (code < FIRST) return NONE;

		final at = bucketOf(code);
		if (codes[at] == code) return slots[at];

		final slot = takes(code);
		stores(code, slot);

		if (slot == NONE) missed++;
		else kept++;

		return slot;
	}

	/**
		Draws a glyph from this face into the atlas.

		@param code A codepoint.
		@return Its slot, or `NONE` where this face does not have it.
	**/
	function takes(code:Int):Int {
		if (kept >= CACHE) return NONE;

		if (Text.extent(face, pixels, code, cpp.Pointer.arrayElem(asked.toData(), 0).raw,
				cpp.Pointer.arrayElem(asked.toData(), 1).raw) == 0) {
			return borrows(code);
		}

		return cuts(face, code);
	}

	/**
		Draws a glyph from a fallback face into the atlas.

		@param from The fallback face.
		@param code A codepoint.
		@return Its slot, or `NONE`.
	**/
	function cuts(from:Int, code:Int):Int {
		final wide = asked[0];
		final tall = asked[1];

		if (wide > SCRATCH || tall > SCRATCH) return NONE;
		if (!room(wide, tall)) return NONE;

		final base = (GLYPHS + kept) * FLOATS;

		if (Text.glyph(from, pixels, code, cpp.Pointer.arrayElem(scratch.toData(), 0).raw,
				atlasWidth, atlasHeight, shelfX, shelfY,
				cpp.Pointer.arrayElem(metrics.toData(), base).raw) == 0) {
			return NONE;
		}

		if (wide > 0 && tall > 0) {
			Draw.patchTexture(texture, cpp.Pointer.arrayElem(scratch.toData(), 0).constRaw,
				shelfX, shelfY, wide, tall);
		}

		shelfX += wide + 1;
		if (tall > shelfTall) shelfTall = tall;

		return base;
	}

	/**
		Looks for a glyph in every fallback face in turn.

		@param code A codepoint.
		@return Its slot, or `NONE` where nobody has it.
	**/
	function borrows(code:Int):Int {
		final spare = beside;
		if (spare == null) return NONE;

		for (next in spare.held()) {
			if (next < 0) continue;

			if (Text.extent(next, pixels, code, cpp.Pointer.arrayElem(asked.toData(), 0).raw,
					cpp.Pointer.arrayElem(asked.toData(), 1).raw) == 0) {
				continue;
			}

			return cuts(next, code);
		}

		return NONE;
	}

	/**
		Finds room in the atlas for a glyph, growing it where there is none.

		@param wide How wide the glyph is.
		@param tall How tall.
		@return False where the atlas is full and cannot grow.
	**/
	function room(wide:Int, tall:Int):Bool {
		if (shelfX + wide > atlasWidth) {
			shelfX = 0;
			shelfY += shelfTall + 1;
			shelfTall = 0;
		}

		return shelfY + tall <= atlasHeight - SOLID;
	}

	/**
		@param text Some text.
		@param index A position in it.
		@return The codepoint there, joining a surrogate pair into one.
	**/
	public static inline function codeAt(text:String, index:Int):Int {
		final one = StringTools.fastCodeAt(text, index);
		if (one < 0xD800 || one > 0xDBFF || index + 1 >= text.length) return one;

		final two = StringTools.fastCodeAt(text, index + 1);
		if (two < 0xDC00 || two > 0xDFFF) return one;

		return PAIRED + ((one - 0xD800) << 10) + (two - 0xDC00);
	}

	/**
		@param code A codepoint.
		@return How far to move along the string past it, which is two for anything above the basic
			plane.
	**/
	public static inline function step(code:Int):Int {
		return code < PAIRED ? 1 : 2;
	}

	public inline function u0(slot:Int):Float return metrics[slot];
	public inline function v0(slot:Int):Float return metrics[slot + 1];
	public inline function u1(slot:Int):Float return metrics[slot + 2];
	public inline function v1(slot:Int):Float return metrics[slot + 3];
	public inline function offsetX(slot:Int):Float return metrics[slot + 4];
	public inline function offsetY(slot:Int):Float return metrics[slot + 5];
	public inline function advance(slot:Int):Float return metrics[slot + 6];

	public inline function wide(slot:Int):Float return metrics[slot + 7];

	public inline function tall(slot:Int):Float return metrics[slot + 8];

	/**
		@param text Some text.
		@return How wide it draws, kerning included.
	**/
	public function measure(text:String):Float {
		var pen = 0.0;
		var index = 0;

		while (index < text.length) {
			final code = codeAt(text, index);
			index += step(code);

			final slot = slotOf(code);
			if (slot == NONE) continue;

			pen += advance(slot);
		}

		return pen;
	}

	/**
		@param text Some text.
		@param room How much room there is.
		@return How many characters fit, for cutting a label that is too long.
	**/
	public function fits(text:String, room:Float):Int {
		var pen = 0.0;
		var index = 0;

		while (index < text.length) {
			final code = codeAt(text, index);
			final next = index + step(code);
			final slot = slotOf(code);

			if (slot != NONE) {
				if (pen + advance(slot) > room) return index;
				pen += advance(slot);
			}

			index = next;
		}

		return text.length;
	}

	/**
		Breaks a line into lines no wider than the room there is, between words where
		the writing has spaces in it and between characters where it does not, which
		is what the scripts written without spaces need. Beside a kana or an ideograph
		it breaks where the room runs out even with a space further back, and a closing
		mark such as a full stop is kept on the line it closes rather than starting the
		next one.

		A character this face has no glyph for measures nothing, so a line made only
		of them comes back whole however narrow the room is.

		@param said The line.
		@param room How much room there is, across.
		@return The lines to draw, in order, with the spaces they were broken at
			dropped. None at all where there is nothing to say or no room to say it
			in.
	**/
	public function wrapped(said:String, room:Float):Array<String> {
		final held:Array<String> = [];
		if (said == "" || room <= 0) return held;

		var from = 0;

		while (from < said.length) {
			final rest = said.substring(from);
			final many = fits(rest, room);

			if (many >= rest.length) {
				held.push(rest);
				break;
			}

			var cut = breaks(rest, many);
			if (cut <= 0) cut = many > 0 ? many : step(codeAt(rest, 0));

			held.push(StringTools.rtrim(rest.substring(0, cut)));

			from += cut;
			while (from < said.length && said.charCodeAt(from) == " ".code) from++;
		}

		return held;
	}

	/**
		Finds where a line that does not fit is broken, which is `wrapped`'s rule on its own so
		it can be checked without a face.

		@param line The line.
		@param many How many characters of it fit.
		@return Where the first line ends: the last space before what fits, or where the room
			runs out when that is beside a kana or an ideograph, one sooner where a closing mark
			would otherwise start the next line. Nought or less where there is no place to break.
	**/
	public static function breaks(line:String, many:Int):Int {
		if (many <= 0 || many >= line.length) return line.lastIndexOf(" ", many);

		final at = StringTools.fastCodeAt(line, many);
		final before = StringTools.fastCodeAt(line, many - 1);

		if (!ideographic(at) && !ideographic(before)) return line.lastIndexOf(" ", many);

		return many > 1 && closing(at) && (before < 0xD800 || before > 0xDFFF) ? many - 1 : many;
	}

	/**
		@param code A code unit.
		@return Whether it is a kana, an ideograph or a full width form, which a line may be
			broken beside without a space. Hangul is not, because Korean is written with
			spaces.
	**/
	static inline function ideographic(code:Int):Bool {
		return (code >= 0x3000 && code <= 0x9FFF) || (code >= 0xF900 && code <= 0xFAFF)
			|| (code >= 0xFF00 && code <= 0xFFEF);
	}

	/**
		@param code A code unit.
		@return Whether it closes what comes before it, and so may not start a line.
	**/
	static inline function closing(code:Int):Bool {
		return switch (code) {
			case 0x3001 | 0x3002 | 0xFF0C | 0xFF0E | 0xFF09 | 0x300D | 0x300F | 0xFF01 | 0xFF1F
				| 0xFF1A | 0xFF1B | ",".code | ".".code | ")".code | ":".code | ";".code
				| "!".code | "?".code: true;
			case _: false;
		}
	}

	/**
		Gives the atlas back.
	**/
	public function shut():Void {
		if (texture != null) Draw.destroyTexture(texture);
		if (face >= 0) Text.free(face);
		face = -1;
	}
}
