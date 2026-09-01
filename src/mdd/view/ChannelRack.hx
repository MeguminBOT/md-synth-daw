package mdd.view;

import haxe.ds.Vector;
import mdd.song.Part;
import mdd.ui.control.Choice;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.control.Menu;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class ChannelRack extends Widget {
	public final session:Session;

	public final levels:Vector<Float> = new Vector<Float>(Part.COUNT);

	var hoverAt:Int = -1;
	var menu:Null<Menu> = null;
	var menuFor:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		for (i in 0...Part.COUNT) levels[i] = 0;
	}

	public function rowHeight():Float {
		final root = root();
		return root == null ? 30 : root.metrics.row;
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - header()) / rowHeight());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	function header():Float {
		final root = root();
		return root == null ? 26 : root.metrics.whole(26);
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		switch (event.kind) {
			case Kind.PointerDown:
				final at = rowAt(event.y);
				if (at < 0) return false;

				final metrics = root.metrics;
				final part:Part = at;

				if (event.button == Pointer.Right) {
					session.choose(part);
					popped(at, event.x, event.y);
					return true;
				}

				if (event.x >= x + width - metrics.whole(96)
						&& event.x < x + width - metrics.whole(72)) {
					session.song.muted[at] = !session.song.muted[at];
					session.changed();
					invalidate();
					return true;
				}

				if (event.x >= x + width - metrics.whole(72)
						&& event.x < x + width - metrics.whole(48)) {
					session.song.soloed[at] = !session.song.soloed[at];
					session.changed();
					invalidate();
					return true;
				}

				session.choose(part);
				invalidate();
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				described(at, event.x, root.metrics);

				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	function popped(at:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final part:Part = at;
		final song = session.song;

		menu = new Menu();
		menuFor = at;

		fires(menu.offer(new Choice(translate(song.muted[at] ? Locale.RACK_UNMUTE : Locale.RACK_MUTE))), function():Void {
			song.muted[at] = !song.muted[at];
			session.say((song.muted[at] ? "muted " : "unmuted ") + part.name());
			session.changed();
		});

		fires(menu.offer(new Choice(translate(song.soloed[at] ? Locale.RACK_UNSOLO : Locale.RACK_SOLO))), function():Void {
			song.soloed[at] = !song.soloed[at];
			session.say((song.soloed[at] ? "soloed " : "unsoloed ") + part.name());
			session.changed();
		});

		fires(menu.offer(new Choice(translate(Locale.RACK_SOLO_ONLY))), function():Void {
			for (i in 0...Part.COUNT) song.soloed[i] = i == at;
			session.say("soloed " + part.name() + " alone");
			session.changed();
		});

		menu.divide();

		final copy = menu.offer(new Choice(translate(Locale.RACK_COPY_PATCH)));
		final paste = menu.offer(new Choice(translate(Locale.RACK_PASTE_PATCH)));
		final reset = menu.offer(new Choice(translate(Locale.RACK_RESET_PATCH)));

		if (!part.fm()) {
			for (choice in [copy, paste, reset]) {
				choice.enabled = false;
				choice.reason = part.name() + " " + translate(Locale.RACK_NO_PATCH);
			}
		} else {
			fires(copy, function():Void {
				final held = song.instrumentAt(song.rack[at]);
				if (held == null || held.patch == null) return;

				session.copiedPatch = held.patch.copy();
				session.say("copied the patch on " + part.name());
				session.changed();
			});

			paste.enabled = session.copiedPatch != null;
			if (!paste.enabled) paste.reason = translate(Locale.RACK_NONE_COPIED);

			fires(paste, function():Void {
				final held = song.instrumentAt(song.rack[at]);
				if (held == null || session.copiedPatch == null) return;

				held.patch = session.copiedPatch.copy();
				session.say("pasted a patch onto " + part.name());
				session.changed();
			});

			fires(reset, function():Void {
				final held = song.instrumentAt(song.rack[at]);
				if (held == null) return;

				held.patch = new mdd.song.Patch();
				session.say("reset the patch on " + part.name());
				session.changed();
			});
		}

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.RACK_CLEAR))), function():Void {
			final pattern = session.current();
			if (pattern == null) return;

			final lane = pattern.lane(part);
			final many = lane.notes.length;

			while (lane.notes.length > 0) {
				session.does(new mdd.song.edit.RemoveNote(session.pattern, part, lane.notes[0]));
			}

			session.say("cleared " + many + " notes from " + part.name());
			session.changed();
		});

		root.pop(menu, px, py, this);
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}

	function described(at:Int, px:Float, metrics:Metrics):Void {
		if (at < 0) {
			tip = "";
			chord = "";
			detail = "";
			return;
		}

		final part:Part = at;
		final muted = session.song.muted[at];
		final soloed = session.song.soloed[at];

		if (px >= x + width - metrics.whole(96) && px < x + width - metrics.whole(72)) {
			tip = translate(muted ? Locale.RACK_UNMUTE : Locale.RACK_MUTE) + " " + part.name();
			chord = "";
			detail = "";
			return;
		}

		if (px >= x + width - metrics.whole(72) && px < x + width - metrics.whole(48)) {
			tip = translate(soloed ? Locale.RACK_UNSOLO : Locale.RACK_SOLO) + " " + part.name();
			chord = translate(Locale.RACK_SOLO_CHORD);
			detail = "";
			return;
		}

		tip = part.name();
		chord = "";

		if (part.sampled()) detail = translate(Locale.RACK_DAC);
		else if (part.fm()) detail = translate(Locale.RACK_FM);
		else if (part.noise()) detail = translate(Locale.RACK_NOISE);
		else detail = translate(Locale.RACK_SQUARE);
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverAt = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final tall = rowHeight();
		final top = header();

		paint.rect(x, y, width, height, theme.panel);
		paint.reface(small);
		paint.text(translate(Locale.PANEL_RACK), x + metrics.inset, y + top * 0.5 + small.ascent * 0.5,
			theme.dim, 0.8);

		final swatch = metrics.whole(10);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = y + top + index * tall;

			if (session.part.index() == index) {
				paint.roundedRect(x + metrics.unit, row + 1, width - metrics.unit * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.SELECT);
			} else if (index == hoverAt) {
				paint.roundedRect(x + metrics.unit, row + 1, width - metrics.unit * 2, tall - 2,
					metrics.radiusRow, theme.accent, Theme.HOVER);
			}

			final quiet = !session.song.audible(part);

			paint.roundedRect(x + metrics.inset, row + (tall - swatch) * 0.5, swatch, swatch,
				metrics.radiusSmall, theme.part(index), quiet ? 0.25 : 1);

			mark(paint, theme, metrics, x + width - metrics.whole(96), row, tall,
				session.song.muted[index]);
			mark(paint, theme, metrics, x + width - metrics.whole(72), row, tall,
				session.song.soloed[index]);

			meter(paint, theme, metrics, x + width - metrics.whole(44), row, tall, index,
				theme.part(index));
		}

		paint.reface(small);

		for (index in 0...Part.COUNT) {
			final row = y + top + index * tall;
			final line = row + (tall - small.height) * 0.5 + small.ascent;
			final size = metrics.whole(18);

			paint.textCentred("M", x + width - metrics.whole(96) + size * 0.5, line,
				session.song.muted[index] ? theme.ink : theme.dim);
			paint.textCentred("S", x + width - metrics.whole(72) + size * 0.5, line,
				session.song.soloed[index] ? theme.ink : theme.dim);

			final instrument = session.song.instrumentAt(session.song.rack[index]);
			if (instrument == null) continue;

			paint.text(instrument.name, x + metrics.inset + swatch + metrics.gap
				+ metrics.whole(48), line, theme.dim, 0.7);
		}

		paint.reface(font);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = y + top + index * tall;
			final quiet = !session.song.audible(part);

			paint.text(part.name(), x + metrics.inset + swatch + metrics.gap,
				row + (tall - font.height) * 0.5 + font.ascent,
				quiet ? theme.dim : theme.ink, quiet ? 0.5 : 1);
		}
	}

	function mark(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			on:Bool):Void {
		final size = metrics.whole(18);
		final top = row + (tall - size) * 0.5;

		paint.roundedRect(at, top, size, size, metrics.radiusSmall,
			on ? theme.accent : theme.raise1, on ? 0.8 : 1);
	}

	function meter(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			index:Int, colour:Colour):Void {
		final wide = metrics.whole(32);
		final high = metrics.whole(6);
		final top = row + (tall - high) * 0.5;

		paint.roundedRect(at, top, wide, high, high * 0.5, theme.sink);

		final level = levels[index];
		if (level <= 0.002) return;

		final filled = wide * (level > 1 ? 1 : level);
		paint.roundedRect(at, top, filled, high, high * 0.5, colour);
	}
}
