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
		paired(font);
		caching(paint, font);
		scales(root);
		clipping(paint);
		opacities(paint);
		speckled(paint);
		joined(paint);
		poured(paint);

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

	static function poured(paint:Paint):Void {
		final many = 200000;
		var best = 1000.0;

		for (pass in 0...5) {
			begin();

			final began = Sdl.ticks();

			for (index in 0...many) {
				final at = index & 255;
				paint.rect(at, (index >> 8) & 255, 6, 4, Theme.PARTS[index % 11], 0.8);

				if ((index & 1023) == 1023) paint.flush();
			}

			paint.flush();

			final took = Sdl.ticks() - began;
			if (took < best) best = took;

			Draw.setTarget(renderer, null);
		}

		final each = best * 1000000000 / many;

		says("throughput", each < 400, Math.round(each) + " ns a rectangle, "
			+ round(best * 1000) + " ms for " + many + ", best of 5");

		final said = "The quick brown fox";
		final runs = 20000;
		final glyphs = runs * said.length;

		var quickest = 1000.0;

		for (pass in 0...5) {
			begin();

			final began = Sdl.ticks();

			for (index in 0...runs) {
				paint.text(said, 4, index & 255, Theme.PARTS[index % 11], 0.9);
				if ((index & 63) == 63) paint.flush();
			}

			paint.flush();

			final took = Sdl.ticks() - began;
			if (took < quickest) quickest = took;

			Draw.setTarget(renderer, null);
		}

		final perGlyph = quickest * 1000000000 / glyphs;

		says("text throughput", perGlyph < 200, Math.round(perGlyph) + " ns a glyph, "
			+ round(quickest * 1000) + " ms for " + glyphs + ", best of 5");
	}

	static function joined(paint:Paint):Void {
		final held = new Vector<Float>(6);
		final weight = 8.0;
		final middle = SIDE * 0.5;
		final arm = 120.0;

		var worst = 0;
		var worstAt = 0;

		for (step in 0...17) {
			final turn = (10 + step * 10) * Math.PI / 180;

			held[0] = middle - arm;
			held[1] = middle;
			held[2] = middle;
			held[3] = middle;
			held[4] = middle + Math.cos(turn) * arm;
			held[5] = middle - Math.sin(turn) * arm;

			begin();
			paint.polyline(held, 3, weight, Theme.FM1);
			paint.flush();

			final bare = read();

			begin();
			paint.polyline(held, 3, weight, Theme.FM1);
			paint.circle(middle, middle, weight * 0.5, Theme.FM1);
			paint.flush();

			final capped = read();
			final missing = capped - bare;

			if (missing > worst) {
				worst = missing;
				worstAt = 10 + step * 10;
			}
		}

		says("joins", worst <= 4, "across 17 turns from 10 to 170 degrees a corner is at"
			+ " most " + worst + " pixels short of the same corner with a join drawn over it"
			+ (worst == 0 ? "" : ", at " + worstAt + " degrees"));
	}

	static function speckled(paint:Paint):Void {
		var worst = 0;
		var worstAt = "";
		var many = 0;
		var drawn = 0;

		for (step in 0...9) {
			final wide = 24 + step * 34;
			final tall = 15 + step * 19;
			final radius = 2 + step * 2;

			final colour = Theme.PARTS[step % Theme.PARTS.length];

			begin();
			paint.roundedGradient(11, 9, wide, tall, radius, colour.lift(0.22),
				colour.sink(0.18), 1);
			paint.flush();

			drawn++;

			final found = specks(11, 9, wide, tall);
			many += found;

			if (found > worst) {
				worst = found;
				worstAt = wide + "x" + tall + " at a radius of " + radius;
			}

			begin();
			paint.roundedRect(11, 9, wide, tall, radius, colour, 1);
			paint.flush();

			drawn++;

			final held = specks(11, 9, wide, tall);
			many += held;

			if (held > worst) {
				worst = held;
				worstAt = wide + "x" + tall + " at a radius of " + radius + ", flat";
			}
		}

		says("no specks", many == 0, many + " pixels darker than every neighbour across "
			+ drawn + " filled shapes" + (worst == 0 ? "" : ", worst " + worst + " on "
			+ worstAt));
	}

	static function specks(left:Float, top:Float, wide:Float, tall:Float):Int {
		Draw.readPixels(renderer, 0, 0, SIDE, SIDE,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);
		Draw.setTarget(renderer, null);

		final from = Std.int(left) + 1;
		final until = Std.int(left + wide) - 1;
		final head = Std.int(top) + 1;
		final floor = Std.int(top + tall) - 1;

		var found = 0;

		for (py in head...floor) {
			for (px in from...until) {
				final here = light(px, py);
				if (here > 40) {
					var darkest = 255;

					for (dy in -1...2) {
						for (dx in -1...2) {
							if (dx == 0 && dy == 0) continue;

							final near = light(px + dx, py + dy);
							if (near < darkest) darkest = near;
						}
					}

					if (darkest - here >= 24) found++;
				}
			}
		}

		return found;
	}

	static function light(px:Int, py:Int):Int {
		final at = (py * SIDE + px) * 4;

		return Std.int((pixels[at] * 299 + pixels[at + 1] * 587 + pixels[at + 2] * 114)
			/ 1000);
	}

	static function within(name:String, got:Float, want:Float, slack:Float):Void {
		ran++;
		final off = got - want;
		final wide = off < 0 ? -off : off;
		final ok = wide <= slack;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 46)
			+ StringTools.lpad(round(got) + "", " ", 9)
			+ "   want " + round(want) + " +/- " + round(slack)
			+ (ok ? "" : "   FAILED"));
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 46) + said + (ok ? "" : "   FAILED"));
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

	static function caching(paint:Paint, font:Font):Void {
		final alpha = 0x03B1;
		final was = font.kept;

		final slot = font.slotOf(alpha);

		says("a codepoint past the atlas is baked on demand",
			slot != Font.NONE && font.kept == was + 1,
			"greek alpha at slot " + slot + ", " + font.kept + " cached");

		says("and it lands in the shelf below the packed range",
			slot != Font.NONE && font.v0(slot) > 0.5 && font.v1(slot) <= 1.0001,
			slot == Font.NONE ? "no slot"
				: "v " + round(font.v0(slot)) + " to " + round(font.v1(slot)));

		says("and asking twice bakes once",
			font.slotOf(alpha) == slot && font.kept == was + 1,
			font.kept + " cached after two asks");

		final missing = font.missed;

		says("and a codepoint the face has not is remembered as missing",
			font.slotOf(0x4E2D) == Font.NONE && font.missed == missing + 1,
			font.missed + " missing");

		says("and it costs one lookup, not a bake, the second time",
			font.slotOf(0x4E2D) == Font.NONE && font.missed == missing + 1,
			font.missed + " missing after two asks");

		begin();
		paint.text(String.fromCharCode(alpha), 10, 60, Theme.PARTS[8]);
		paint.flush();

		Draw.readPixels(renderer, 0, 0, SIDE, SIDE,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);
		Draw.setTarget(renderer, null);

		var lit = 0;
		for (y in 0...SIDE) {
			for (x in 0...SIDE) {
				if (pixels[(y * SIDE + x) * 4 + 1] > 8) lit++;
			}
		}

		says("and a cached glyph draws pixels", lit > 20, lit + " pixels lit");

		says("and it measures wider than nothing", font.measure(String.fromCharCode(alpha)) > 0,
			round(font.measure(String.fromCharCode(alpha))) + " wide");
	}

	static function paired(font:Font):Void {
		final treble = String.fromCharCode(0xD834) + String.fromCharCode(0xDD1E);
		final code = Font.codeAt(treble, 0);

		says("a surrogate pair is one codepoint", code == 0x1D11E && Font.step(code) == 2,
			"U+" + StringTools.hex(code, 5) + " over " + Font.step(code) + " units");

		final lone = String.fromCharCode(0xD834);

		says("and a lone surrogate is left as it is",
			Font.codeAt(lone, 0) == 0xD834 && Font.step(Font.codeAt(lone, 0)) == 1,
			"U+" + StringTools.hex(Font.codeAt(lone, 0), 4));

		final held = "AB" + treble + "CD";

		var lands = true;
		var at = 0;

		while (at <= 400) {
			final cut = font.fits(held, at * 0.5);
			if (cut == 3) lands = false;

			at++;
		}

		says("and no cut lands inside a pair", lands, "401 widths, none cut at index 3");

		says("and an unknown codepoint costs one advance, not two",
			font.measure(held) == font.measure("ABCD"),
			round(font.measure(held)) + " against " + round(font.measure("ABCD")));
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
				final slot = font.slotOf(a);
				if (slot == Font.NONE || font.wide(slot) <= 0) continue;

				if (font.u1(slot) > 1.0001 || font.v1(slot) > 1.0001 || font.u0(slot) < 0) {
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
