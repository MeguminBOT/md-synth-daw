package mdd.ui;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Text;
import mdd.host.Texture;

@:unreflective
final class Font {
	public static inline final FIRST = 32;
	public static inline final LAST = 255;
	static inline final GLYPHS = LAST - FIRST + 1;
	static inline final WIDEST = 2048;
	static inline final PAIRED = 0x10000;

	static inline final CACHE = 1024;
	static inline final SCRATCH = 192;
	public static inline final NONE = -1;

	static inline final FLOATS = 9;
	static inline final SOLID = 8;

	public var pixels(default, null):Float;
	public var ascent(default, null):Float;
	public var descent(default, null):Float;
	public var line(default, null):Float;
	public var height(default, null):Float;

	public var atlasWidth(default, null):Int;
	public var atlasHeight(default, null):Int;

	public var solidU(default, null):Float;
	public var solidV(default, null):Float;

	public var kept(default, null):Int = 0;
	public var missed(default, null):Int = 0;

	public var texture(default, null):cpp.Star<Texture>;

	final metrics:Vector<Single> = new Vector<Single>((GLYPHS + CACHE) * FLOATS);
	final cached:haxe.ds.IntMap<Int> = new haxe.ds.IntMap<Int>();

	final asked:Vector<Int> = new Vector<Int>(2);
	final scratch:Vector<cpp.UInt8> = new Vector<cpp.UInt8>(SCRATCH * SCRATCH * 4);

	var face:Int = -1;
	var beside:Null<Fallback> = null;

	var shelfX:Int = 0;
	var shelfY:Int = 0;
	var shelfTall:Int = 0;

	function new() {}

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

	function halves():Void {
		for (index in 0...GLYPHS) {
			final base = index * FLOATS;

			metrics[base + 1] = metrics[base + 1] * 0.5;
			metrics[base + 3] = metrics[base + 3] * 0.5;
		}
	}

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

	public function chains(next:Null<Fallback>):Void {
		beside = next;

		final lost:Array<Int> = [];

		for (code in cached.keys()) {
			if (cached.get(code) == NONE) lost.push(code);
		}

		for (code in lost) cached.remove(code);

		missed = 0;
	}

	public inline function slotOf(code:Int):Int {
		return code >= FIRST && code <= LAST ? (code - FIRST) * FLOATS : extra(code);
	}

	function extra(code:Int):Int {
		if (code < FIRST) return NONE;

		final held = cached.get(code);
		if (held != null) return held;

		final slot = takes(code);
		cached.set(code, slot);

		if (slot == NONE) missed++;
		else kept++;

		return slot;
	}

	function takes(code:Int):Int {
		if (kept >= CACHE) return NONE;

		if (Text.extent(face, pixels, code, cpp.Pointer.arrayElem(asked.toData(), 0).raw,
				cpp.Pointer.arrayElem(asked.toData(), 1).raw) == 0) {
			return borrows(code);
		}

		return cuts(face, code);
	}

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

	function room(wide:Int, tall:Int):Bool {
		if (shelfX + wide > atlasWidth) {
			shelfX = 0;
			shelfY += shelfTall + 1;
			shelfTall = 0;
		}

		return shelfY + tall <= atlasHeight - SOLID;
	}

	public static inline function codeAt(text:String, index:Int):Int {
		final one = StringTools.fastCodeAt(text, index);
		if (one < 0xD800 || one > 0xDBFF || index + 1 >= text.length) return one;

		final two = StringTools.fastCodeAt(text, index + 1);
		if (two < 0xDC00 || two > 0xDFFF) return one;

		return PAIRED + ((one - 0xD800) << 10) + (two - 0xDC00);
	}

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

	public function shut():Void {
		if (texture != null) Draw.destroyTexture(texture);
		if (face >= 0) Text.free(face);
		face = -1;
	}
}
