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
	public static inline final GLYPHS = LAST - FIRST + 1;
	public static inline final WIDEST = 2048;

	static inline final FLOATS = 9;

	public var pixels(default, null):Float;
	public var ascent(default, null):Float;
	public var descent(default, null):Float;
	public var line(default, null):Float;
	public var height(default, null):Float;

	public var atlasWidth(default, null):Int;
	public var atlasHeight(default, null):Int;

	public var solidU(default, null):Float;
	public var solidV(default, null):Float;

	public var texture(default, null):cpp.Star<Texture>;

	final metrics:Vector<Single> = new Vector<Single>(GLYPHS * FLOATS);

	var face:Int = -1;

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
		font.atlasHeight = side;

		font.solid(rgba, side);
		font.texture = Draw.createTexture(renderer, side, side);
		Draw.updateTexture(font.texture, cpp.Pointer.arrayElem(rgba.toData(), 0).constRaw,
			side, side);

		return font;
	}

	function solid(rgba:Vector<cpp.UInt8>, side:Int):Void {
		final at = side - 4;
		for (y in at...side) {
			for (x in at...side) {
				final index = (y * side + x) * 4;
				rgba[index] = 255;
				rgba[index + 1] = 255;
				rgba[index + 2] = 255;
				rgba[index + 3] = 255;
			}
		}

		solidU = (at + 2) / side;
		solidV = (at + 2) / side;
	}

	public static inline function holds(code:Int):Bool {
		return code >= FIRST && code <= LAST;
	}

	public inline function has(code:Int):Bool {
		return holds(code);
	}

	inline function at(code:Int):Int {
		return (code - FIRST) * FLOATS;
	}

	public inline function u0(code:Int):Float return metrics[at(code)];
	public inline function v0(code:Int):Float return metrics[at(code) + 1];
	public inline function u1(code:Int):Float return metrics[at(code) + 2];
	public inline function v1(code:Int):Float return metrics[at(code) + 3];
	public inline function offsetX(code:Int):Float return metrics[at(code) + 4];
	public inline function offsetY(code:Int):Float return metrics[at(code) + 5];
	public inline function advance(code:Int):Float return metrics[at(code) + 6];

	public inline function wide(code:Int):Float return metrics[at(code) + 7];

	public inline function tall(code:Int):Float return metrics[at(code) + 8];

	public function measure(text:String):Float {
		var pen = 0.0;
		for (i in 0...text.length) {
			final code = StringTools.fastCodeAt(text, i);
			if (!has(code)) continue;
			pen += advance(code);
		}
		return pen;
	}

	public function fits(text:String, room:Float):Int {
		var pen = 0.0;
		for (i in 0...text.length) {
			final code = StringTools.fastCodeAt(text, i);
			if (!has(code)) continue;
			if (pen + advance(code) > room) return i;
			pen += advance(code);
		}
		return text.length;
	}

	public function shut():Void {
		if (texture != null) Draw.destroyTexture(texture);
		if (face >= 0) Text.free(face);
		face = -1;
	}
}
