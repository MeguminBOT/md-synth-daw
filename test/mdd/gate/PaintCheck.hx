package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.host.Texture;
import mdd.host.Window;
import mdd.ui.Font;
import mdd.ui.Paint;
import mdd.ui.Theme;

@:unreflective
class PaintCheck {
	static inline final SIDE = 512;

	static var window:cpp.Star<Window>;
	static var renderer:cpp.Star<Canvas>;
	static var target:cpp.Star<Texture>;
	static var pixels:Vector<cpp.UInt8>;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		Native.ready();
		Sys.println("  paint");

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return 1;
		}

		window = Sdl.createWindow("mdd gate paint", SIDE, SIDE, 0, 0);
		if (window == null) {
			Sys.println("    no window: " + Sdl.error());
			Sdl.quit();
			return 1;
		}

		renderer = Sdl.createRenderer(window, 0);
		if (renderer == null) {
			Sys.println("    no renderer: " + Sdl.error());
			Sdl.destroyWindow(window);
			Sdl.quit();
			return 1;
		}

		target = Draw.createTarget(renderer, SIDE, SIDE);
		pixels = new Vector<cpp.UInt8>(SIDE * SIDE * 4);

		final root = args.length > 0 ? args[0] : Gate.root;
		final face = root + "/vendor/fonts/Go-Regular.ttf";

		if (!sys.FileSystem.exists(face)) {
			Sys.println("    no font at " + face);
			Sys.println("    run: mdd setup");
			shut();
			return 1;
		}

		final font = Font.bake(renderer, face, 26);
		if (font == null) {
			Sys.println("    the font would not bake");
			shut();
			return 1;
		}

		Sys.println("    atlas         " + font.atlasWidth + "x" + font.atlasHeight
			+ ", ascent " + round(font.ascent) + ", descent " + round(font.descent));

		final paint = Paint.on(renderer, font);

		shapes(paint);
		batching(paint, font);
		measured(paint, font, root);
		scales(root);
		clipping(paint);
		opacities(paint);

		font.shut();
		shut();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function shut():Void {
		if (target != null) Draw.destroyTexture(target);
		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();
	}

	static function begin():Void {
		Draw.setTarget(renderer, target);
		Sdl.renderClear(renderer, 0, 0, 0, 1);
	}

	static function read():Int {
		Draw.readPixels(renderer, 0, 0, SIDE, SIDE,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);
		Draw.setTarget(renderer, null);

		var lit = 0;
		for (i in 0...SIDE * SIDE) {
			if (pixels[i * 4 + 3] > 8 && (pixels[i * 4] > 8 || pixels[i * 4 + 1] > 8
				|| pixels[i * 4 + 2] > 8)) lit++;
		}
		return lit;
	}

	static function within(name:String, got:Float, want:Float, slack:Float):Void {
		ran++;
		final off = got - want;
		final wide = off < 0 ? -off : off;
		final ok = wide <= slack;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 14)
			+ StringTools.lpad(round(got) + "", " ", 9)
			+ "   want " + round(want) + " +/- " + round(slack)
			+ (ok ? "" : "   FAILED"));
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 14) + said + (ok ? "" : "   FAILED"));
	}

	static function shapes(paint:Paint):Void {
		begin();
		paint.rect(20, 20, 100, 60, Theme.FM1);
		paint.flush();
		within("rect", read(), 100 * 60, 4);

		begin();
		paint.circle(160, 160, 60, Theme.FM5);
		paint.flush();
		within("circle", read(), Math.PI * 60 * 60, Math.PI * 60 * 60 * 0.03);

		begin();
		paint.ring(160, 160, 60, 10, Theme.PSG1);
		paint.flush();
		within("ring", read(), Math.PI * (60 * 60 - 50 * 50), Math.PI * 60 * 60 * 0.05);

		begin();
		paint.outline(40, 40, 120, 90, Theme.DAC, 2);
		paint.flush();
		within("outline", read(), (120 * 90) - (116 * 86), 8);

		begin();
		paint.line(30, 30, 230, 30, 6, Theme.FM3);
		paint.flush();
		within("line", read(), 200 * 6, 24);

		begin();
		paint.roundedRect(30, 30, 160, 120, 20, Theme.FM6);
		paint.flush();
		within("roundedRect", read(), 160 * 120 - 20 * 20 * (4 - Math.PI), 60);

		final tri = Vector.fromArrayCopy([40.0, 40.0, 240.0, 40.0, 240.0, 200.0]);
		begin();
		paint.polygon(tri, 3, Theme.PSG3);
		paint.flush();
		within("polygon", read(), 200 * 160 / 2, 400);

		final wave = new Vector<Float>(4096);
		for (i in 0...4096) wave[i] = (i % 2) == 0 ? 1.0 : -1.0;
		begin();
		paint.waveform(wave, 0, 4096, 20, 60, 200, 100, Theme.DAC);
		paint.flush();
		within("waveform", read(), 200 * 100, 800);
	}

	static function batching(paint:Paint, font:Font):Void {
		begin();
		Draw.resetCalls();

		paint.rect(10, 10, 40, 40, Theme.FM1);
		paint.circle(120, 60, 24, Theme.FM3);
		paint.roundedRect(160, 20, 90, 60, 10, Theme.FM5);
		paint.line(10, 200, 300, 240, 3, Theme.PSG1);
		paint.ring(80, 200, 30, 6, Theme.PSG2);
		paint.text("mixed", 20, 120, Theme.PARTS[10]);
		paint.flush();

		final calls = Draw.calls();
		Draw.setTarget(renderer, null);
		says("one draw call", calls == 1, calls + " call" + (calls == 1 ? "" : "s"));
	}

	static function measured(paint:Paint, font:Font, root:String):Void {
		final sample = "Chemical Plant Zone 0123456789";

		begin();
		paint.text(sample, 10, 60, Theme.PARTS[8]);
		paint.flush();

		Draw.readPixels(renderer, 0, 0, SIDE, SIDE,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);
		Draw.setTarget(renderer, null);

		var rightmost = 0;
		for (y in 0...SIDE) {
			for (x in 0...SIDE) {
				final lit = pixels[(y * SIDE + x) * 4] > 8 || pixels[(y * SIDE + x) * 4 + 1] > 8
					|| pixels[(y * SIDE + x) * 4 + 2] > 8;
				if (lit && x > rightmost) rightmost = x;
			}
		}

		final said = 10 + font.measure(sample);
		within("measure", rightmost + 1, said, 2);

		ran++;
		final empty = font.measure("");
		if (empty != 0) failed++;
		Sys.println("    " + StringTools.rpad("measure empty", " ", 14)
			+ StringTools.lpad(round(empty) + "", " ", 9) + "   want 0"
			+ (empty == 0 ? "" : "   FAILED"));
	}

	static function scales(root:String):Void {
		final face = root + "/vendor/fonts/Go-Regular.ttf";

		for (scale in [1.0, 1.25, 1.5, 2.0]) {
			final size = 13 * scale;
			final font = Font.bake(renderer, face, size);

			if (font == null) {
				says("scale " + scale, false, "would not bake");
				continue;
			}

			var overlapping = false;
			for (a in Font.FIRST...Font.LAST) {
				if (font.wide(a) <= 0) continue;
				if (font.u1(a) > 1.0001 || font.v1(a) > 1.0001 || font.u0(a) < 0) {
					overlapping = true;
					break;
				}
			}

			final grew = font.measure("MMMM") > 0 && font.height > 0;
			says("scale " + scale, grew && !overlapping,
				"atlas " + font.atlasWidth + ", line " + round(font.height)
				+ ", MMMM " + round(font.measure("MMMM")));

			font.shut();
		}
	}

	static function clipping(paint:Paint):Void {
		begin();
		paint.pushClip(0, 0, 100, 100);
		paint.rect(0, 0, SIDE, SIDE, Theme.FM2);
		paint.flush();
		paint.popClip();
		within("clip", read(), 100 * 100, 4);

		begin();
		paint.pushClip(0, 0, 150, 150);
		paint.pushClip(50, 50, 300, 300);
		paint.rect(0, 0, SIDE, SIDE, Theme.FM4);
		paint.flush();
		paint.popClip();
		paint.popClip();
		within("clip nested", read(), 100 * 100, 4);

		begin();
		paint.pushTransform(40, 40, 2, 2);
		paint.rect(0, 0, 50, 30, Theme.PSG1);
		paint.flush();
		paint.popTransform();
		within("transform", read(), 100 * 60, 8);
	}

	static function round(value:Float):Float {
		return Math.round(value * 100) / 100;
	}

	static function channel(px:Int, py:Int):Int {
		Draw.readPixels(renderer, 0, 0, SIDE, SIDE,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);
		Draw.setTarget(renderer, null);
		return pixels[(py * SIDE + px) * 4];
	}

	static function opacities(paint:Paint):Void {
		begin();
		paint.rect(20, 20, 40, 40, 0xFFFFFF);
		paint.flush();
		final full = channel(30, 30);

		begin();
		paint.pushOpacity(0.5);
		paint.rect(20, 20, 40, 40, 0xFFFFFF);
		paint.flush();
		paint.popOpacity();
		final half = channel(30, 30);

		begin();
		paint.pushOpacity(0.5);
		paint.pushOpacity(0.5);
		paint.rect(20, 20, 40, 40, 0xFFFFFF);
		paint.flush();
		paint.popOpacity();
		paint.popOpacity();
		final quarter = channel(30, 30);

		begin();
		paint.pushOpacity(0.5);
		paint.popOpacity();
		paint.rect(20, 20, 40, 40, 0xFFFFFF);
		paint.flush();
		final back = channel(30, 30);

		says("opacity", full == 255 && Math.abs(half - 128) <= 2 && Math.abs(quarter - 64) <= 2
			&& back == 255,
			"white at " + full + ", halved to " + half + ", nested to " + quarter
			+ ", back to " + back);
	}
}
