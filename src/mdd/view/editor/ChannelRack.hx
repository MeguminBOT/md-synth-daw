package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.Part;
import mdd.song.Song;
import mdd.ui.Panel;
import mdd.view.Kits;
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

	public var offsetY:Float = 0;

	static inline final PAN = 128;
	static inline final PAN_WIDE = 30;
	static inline final MUTE = 96;
	static inline final SOLO = 72;
	static inline final METER = 44;
	static inline final MARK = 18;

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

	inline function slotAt(metrics:Metrics, from:Int):Float {
		return x + width - metrics.whole(from);
	}

	function slotHolds(metrics:Metrics, from:Int, px:Float):Bool {
		final left = slotAt(metrics, from);
		return px >= left && px < left + metrics.whole(from == PAN ? PAN_WIDE : MARK);
	}

	public function turned(at:Int):Void {
		final part:Part = at;
		if (!part.fm()) return;

		session.song.pan[at] = switch (session.song.pan[at]) {
			case Song.BOTH: Song.LEFT;
			case Song.LEFT: Song.RIGHT;
			case _: Song.BOTH;
		}

		session.say(part.name() + "  " + sided(session.song.pan[at]));
		session.changed();
		invalidate();
	}

	public static function sided(pan:Int):String {
		return switch (pan) {
			case Song.LEFT: "L";
			case Song.RIGHT: "R";
			case _: "L R";
		}
	}

	public function rowHeight():Float {
		final root = root();
		if (root == null) return 34;

		final metrics = root.metrics;
		final room = (height - header()) / Part.COUNT;
		final floor = metrics.whole(22);

		if (room >= metrics.row) return metrics.row;

		return room < floor ? floor : Math.ffloor(room);
	}

	public function rowAt(py:Float):Int {
		if (py < y + header()) return -1;

		final at = Std.int((py - y - header() + offsetY) / rowHeight());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	public inline function atRow(index:Int):Float {
		return y + header() + index * rowHeight() - offsetY;
	}

	function contentTall():Float {
		return Part.COUNT * rowHeight();
	}

	public function scrollTo(py:Float):Void {
		final most = contentTall() - (height - header());

		offsetY = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		invalidate();
	}

	function header():Float {
		final root = root();
		return root == null ? 34 : root.metrics.tab;
	}

	override function took(event:Input):Bool {
		final root = root();
		if (root == null) return false;

		switch (event.kind) {
			case Kind.Wheel:
				scrollTo(offsetY - event.dy * rowHeight());
				return true;

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

				if (event.x >= slotAt(metrics, METER)) {
					session.choose(part);
					sliding = at;
					leaned(at, metrics, event.x);
					return true;
				}

				if (slotHolds(metrics, PAN, event.x)) {
					session.choose(part);
					turned(at);
					return true;
				}

				if (slotHolds(metrics, MUTE, event.x)) {
					session.song.muted[at] = !session.song.muted[at];
					session.changed();
					invalidate();
					return true;
				}

				if (slotHolds(metrics, SOLO, event.x)) {
					session.song.soloed[at] = !session.song.soloed[at];
					session.changed();
					invalidate();
					return true;
				}

				session.choose(part);
				invalidate();
				return true;

			case Kind.PointerMove:
				if (sliding >= 0) {
					leaned(sliding, root.metrics, event.x);
					return true;
				}

				final at = rowAt(event.y);
				described(at, event.x, root.metrics);

				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case Kind.PointerUp:
				if (sliding < 0) return false;

				sliding = -1;
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

		final copy = menu.offer(new Choice(translate(Locale.RACK_COPY_PRESET)));
		final paste = menu.offer(new Choice(translate(Locale.RACK_PASTE_PRESET)));
		final reset = menu.offer(new Choice(translate(Locale.RACK_RESET_PRESET)));

		if (!part.fm()) {
			for (choice in [copy, paste, reset]) {
				choice.enabled = false;
				choice.reason = part.name() + " " + translate(Locale.RACK_NO_PRESET);
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

	function described(at:Int, px:Float, metrics:Metrics):Void {
		if (at < 0) {
			tip = "";
			shortcut = "";
			detail = "";
			return;
		}

		final part:Part = at;
		final muted = session.song.muted[at];
		final soloed = session.song.soloed[at];

		if (part.fm() && slotHolds(metrics, PAN, px)) {
			tip = translate(Locale.RACK_PAN) + " " + part.name();
			shortcut = "";
			detail = sided(session.song.pan[at]);
			return;
		}

		if (slotHolds(metrics, MUTE, px)) {
			tip = translate(muted ? Locale.RACK_UNMUTE : Locale.RACK_MUTE) + " " + part.name();
			shortcut = "";
			detail = "";
			return;
		}

		if (slotHolds(metrics, SOLO, px)) {
			tip = translate(soloed ? Locale.RACK_UNSOLO : Locale.RACK_SOLO) + " " + part.name();
			shortcut = translate(Locale.RACK_SOLO_SHORTCUT);
			detail = "";
			return;
		}

		tip = part.name();
		shortcut = "";

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
		Panel.titled(paint, theme, metrics, translate(Locale.PANEL_RACK), x, y, width, top);
		paint.reface(small);

		final swatch = metrics.whole(10);

		paint.pushClip(x, y + top, width, height - top);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = atRow(index);

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

			if (part.fm()) {
				sides(paint, theme, metrics, slotAt(metrics, PAN), row, tall,
					session.song.pan[index], theme.part(index), quiet);
			}

			mark(paint, theme, metrics, slotAt(metrics, MUTE), row, tall,
				session.song.muted[index]);
			mark(paint, theme, metrics, slotAt(metrics, SOLO), row, tall,
				session.song.soloed[index]);

			meter(paint, theme, metrics, slotAt(metrics, METER), row, tall, index,
				theme.part(index));
		}

		paint.reface(small);

		final names = x + metrics.inset + swatch + metrics.gap + widest(font);

		for (index in 0...Part.COUNT) {
			final row = atRow(index);
			final line = row + (tall - small.height) * 0.5 + small.ascent;
			final size = metrics.whole(18);

			paint.textCentred("M", slotAt(metrics, MUTE) + size * 0.5, line,
				session.song.muted[index] ? theme.ink : theme.dim);
			paint.textCentred("S", slotAt(metrics, SOLO) + size * 0.5, line,
				session.song.soloed[index] ? theme.ink : theme.dim);

			final part:Part = index;
			final said = Kits.named(session.song, part, session.song.rack[index]);
			if (said == "") continue;

			final left = names + metrics.gap;
			final room = slotAt(metrics, PAN) - metrics.gap - left;

			if (room < metrics.whole(24)) continue;

			paint.text(shortened(paint, said, room), left, line, theme.dim, 0.95);
		}

		paint.reface(font);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final row = atRow(index);
			final quiet = !session.song.audible(part);

			paint.text(part.name(), x + metrics.inset + swatch + metrics.gap,
				row + (tall - font.height) * 0.5 + font.ascent,
				quiet ? theme.dim : theme.ink, quiet ? 0.5 : 1);
		}

		paint.popClip();
	}

	var namesWide:Float = 0;
	var namesFor:mdd.ui.Font = null;

	function widest(font:mdd.ui.Font):Float {
		if (namesFor == font) return namesWide;

		var most = 0.0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final held = font.measure(part.name());

			if (held > most) most = held;
		}

		namesFor = font;
		namesWide = most;

		return most;
	}

	function sides(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			pan:Int, colour:Colour, quiet:Bool):Void {
		final size = metrics.whole(MARK);
		final top = row + (tall - size) * 0.5;

		paint.roundedRect(at, top, metrics.whole(PAN_WIDE), size, metrics.radiusSmall,
			theme.raise1);

		final wide = metrics.whole(9);
		final gap = metrics.whole(9);
		final middle = top + size * 0.5;
		final from = at + (metrics.whole(PAN_WIDE) - wide * 2 - gap) * 0.5;

		speaker(paint, metrics, from, middle, wide, -1,
			(pan & Song.LEFT) != 0 ? colour : theme.frame, quiet ? 0.35 : 1);

		speaker(paint, metrics, from + wide + gap, middle, wide, 1,
			(pan & Song.RIGHT) != 0 ? colour : theme.frame, quiet ? 0.35 : 1);
	}

	function speaker(paint:Paint, metrics:Metrics, at:Float, middle:Float, wide:Float,
			facing:Int, colour:Colour, alpha:Float):Void {
		final reach = wide * 0.62;
		final near = reach * 0.34;

		final back = facing > 0 ? at : at + wide;
		final neck = back + facing * wide * 0.42;
		final mouth = back + facing * wide;

		final shape = new haxe.ds.Vector<Float>(12);

		shape[0] = back;
		shape[1] = middle - near;
		shape[2] = neck;
		shape[3] = middle - near;
		shape[4] = mouth;
		shape[5] = middle - reach;
		shape[6] = mouth;
		shape[7] = middle + reach;
		shape[8] = neck;
		shape[9] = middle + near;
		shape[10] = back;
		shape[11] = middle + near;

		paint.polygon(shape, 6, colour, alpha);
	}

	static function shortened(paint:Paint, said:String, room:Float):String {
		if (paint.measure(said) <= room) return said;

		var held = said;

		while (held.length > 0) {
			held = held.substring(0, held.length - 1);
			if (paint.measure(held + "...") <= room) return held + "...";
		}

		return "";
	}

	function mark(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			on:Bool):Void {
		final size = metrics.whole(18);
		final top = row + (tall - size) * 0.5;

		if (on) {
			paint.roundedGradient(at, top, size, size, metrics.radiusSmall,
				theme.accent.lift(0.20), theme.accent.sink(0.16), 0.8);
		} else paint.roundedRect(at, top, size, size, metrics.radiusSmall, theme.raise1);
	}

	function meter(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, tall:Float,
			index:Int, colour:Colour):Void {
		final wide = faderWide(metrics);
		final high = metrics.whole(10);
		final top = row + (tall - high) * 0.5;

		paint.roundedRect(at, top, wide, high, high * 0.5, theme.sink);

		final want = session.song.volume[index] / Song.LOUDEST;

		paint.roundedRect(at, top, wide, high, high * 0.5, colour,
			session.song.audible(index) ? 0.4 : 0.15, want);

		final level = levels[index];
		final inset = metrics.whole(3);

		if (level > 0.002) {
			paint.roundedRect(at, top + inset, wide, high - inset * 2,
				(high - inset * 2) * 0.5, colour, 1, level > 1 ? 1 : level);
		}

		final grip = metrics.whole(2);
		final line = at + wide * want;

		paint.rect(line - grip * 0.5, top, grip, high, theme.ink,
			sliding == index ? 1 : 0.7);
	}

	inline function faderWide(metrics:Metrics):Float {
		return metrics.whole(METER) - metrics.inset;
	}

	var sliding:Int = -1;

	function leaned(index:Int, metrics:Metrics, px:Float):Void {
		final room = faderWide(metrics);
		if (room <= 0) return;

		var much = (px - slotAt(metrics, METER)) / room;
		if (much < 0) much = 0;
		if (much > 1) much = 1;

		final want = Math.round(much * Song.LOUDEST);
		if (session.song.volume[index] == want) return;

		session.song.volume[index] = want;

		final part:Part = index;
		session.say(part.name() + "  " + Math.round(want * 100 / Song.LOUDEST) + "%");
		session.changed();
		invalidate();
	}
}
