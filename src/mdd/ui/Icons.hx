package mdd.ui;

import haxe.ds.Vector;
import haxe.io.Bytes;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Texture;

@:unreflective
final class Icons {
	public static inline final HEADER = 14;
	public static inline final ENTRY = 8;

	public var pixels(default, null):Int = 0;
	public var count(default, null):Int = 0;
	public var atlasWidth(default, null):Int = 0;
	public var atlasHeight(default, null):Int = 0;

	public var texture(default, null):cpp.Star<Texture> = null;

	final bounds:Vector<Single>;

	function new(count:Int) {
		this.count = count;
		bounds = new Vector<Single>(count * 6);
	}

	public static function read(renderer:cpp.Star<Canvas>, where:String):Null<Icons> {
		if (!sys.FileSystem.exists(where)) return null;

		final held = sys.io.File.getBytes(where);
		if (held.length < HEADER) return null;

		if (held.get(0) != 0x4D || held.get(1) != 0x44 || held.get(2) != 0x44
			|| held.get(3) != 0x49) return null;

		final count = held.getUInt16(8);
		final across = held.getUInt16(10);
		final down = held.getUInt16(12);
		if (count <= 0 || across <= 0 || down <= 0) return null;

		final want = HEADER + count * ENTRY + across * down;
		if (held.length < want) return null;

		final out = new Icons(count);
		out.pixels = held.getUInt16(6);
		out.atlasWidth = across;
		out.atlasHeight = down;

		for (index in 0...count) {
			final at = HEADER + index * ENTRY;

			final left = held.getUInt16(at);
			final top = held.getUInt16(at + 2);
			final wide = held.getUInt16(at + 4);
			final tall = held.getUInt16(at + 6);

			out.bounds[index * 6] = left / across;
			out.bounds[index * 6 + 1] = top / down;
			out.bounds[index * 6 + 2] = (left + wide) / across;
			out.bounds[index * 6 + 3] = (top + tall) / down;
			out.bounds[index * 6 + 4] = wide;
			out.bounds[index * 6 + 5] = tall;
		}

		out.upload(renderer, held, HEADER + count * ENTRY, across, down);
		return out;
	}

	function upload(renderer:cpp.Star<Canvas>, held:Bytes, from:Int, across:Int, down:Int):Void {
		final rgba = new Vector<cpp.UInt8>(across * down * 4);

		for (index in 0...across * down) {
			final coverage = held.get(from + index);
			final at = index * 4;

			rgba[at] = 255;
			rgba[at + 1] = 255;
			rgba[at + 2] = 255;
			rgba[at + 3] = coverage;
		}

		texture = Draw.createTexture(renderer, across, down);
		Draw.updateTexture(texture, cpp.Pointer.arrayElem(rgba.toData(), 0).constRaw, across, down);
	}

	public inline function has(which:Int):Bool {
		return which >= 0 && which < count;
	}

	public inline function u0(which:Int):Float return bounds[which * 6];
	public inline function v0(which:Int):Float return bounds[which * 6 + 1];
	public inline function u1(which:Int):Float return bounds[which * 6 + 2];
	public inline function v1(which:Int):Float return bounds[which * 6 + 3];
	public inline function wide(which:Int):Float return bounds[which * 6 + 4];
	public inline function tall(which:Int):Float return bounds[which * 6 + 5];

	public function shut():Void {
		if (texture == null) return;

		Draw.destroyTexture(texture);
		texture = null;
	}
}
