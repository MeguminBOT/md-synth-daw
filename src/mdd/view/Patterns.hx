package mdd.view;

import mdd.song.Pattern;
import mdd.song.Part;
import mdd.song.edit.AddPattern;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.Scroll;
import mdd.ui.Theme;

@:unreflective
final class Patterns extends Scroll {
	public final session:Session;

	public var painted(default, null):Int = 0;

	var hoverAt:Int = -1;
	var settledOn:Int = -1;
	var menu:Null<Menu> = null;

	public function new(session:Session) {
		super();
		this.session = session;
		focusable = true;
	}

	function revealed(tall:Float):Void {
		if (settledOn == session.pattern) return;

		settledOn = session.pattern;

		final top = session.pattern * tall;

		if (top < offsetY) offsetY = top;
		else if (top + tall > offsetY + height) offsetY = top + tall - height;

		final most = contentHeight - height;
		if (offsetY > most) offsetY = most < 0 ? 0 : most;
		if (offsetY < 0) offsetY = 0;
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 30 : root.metrics.whole(30);
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y + offsetY) / rowTall());
		return at < 0 || at >= session.song.patterns.length ? -1 : at;
	}

	public function choose(index:Int):Void {
		session.chooses(index);
	}

	function popped(at:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		fires(menu.offer(new Choice(translate(Locale.PATTERN_DUPLICATE))), function():Void
			duplicated(at));
		fires(menu.offer(new Choice(translate(Locale.PATTERN_RENAME))), function():Void
			renamed(at));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.PATTERN_INSERT))), function():Void
			inserted(at));

		menu.divide();

		final drop = menu.offer(new Choice(translate(Locale.PATTERN_DELETE)));

		if (session.song.patterns.length <= 1) {
			drop.enabled = false;
			drop.reason = translate(Locale.PATTERN_LAST);
		} else {
			fires(drop, function():Void dropped(at));
		}

		root.pop(menu, px, py, this);
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(from:Choice):Void what();
	}

	public function duplicated(at:Int):Void {
		final from = session.song.patternAt(at);
		if (from == null) return;

		final made = new Pattern(from.name + " 2", from.length, from.colour);

		session.holds();

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			for (note in from.lane(part).notes) made.lane(part).add(note.copy());
		}

		session.frees();

		session.does(new AddPattern(made));
		session.chooses(session.song.patterns.length - 1);
	}

	public function renamed(at:Int):Void {
		final held = session.song.patternAt(at);
		if (held == null) return;

		session.does(new mdd.song.edit.RenamePattern(at, held.name + " " + (at + 1)));
	}

	public function inserted(at:Int):Void {
		final held = session.song.patternAt(at);
		final track = session.song.tracks[0];
		if (held == null || track == null) return;

		var ends = 0;
		for (clip in track.clips) if (clip.ends() > ends) ends = clip.ends();

		session.does(new mdd.song.edit.AddClip(0, new mdd.song.Clip(at, ends,
			held.length)));
	}

	public function dropped(at:Int):Void {
		if (session.song.patterns.length <= 1) return;

		session.does(new mdd.song.edit.RemovePattern(at));

		if (session.pattern >= session.song.patterns.length) {
			session.pattern = session.song.patterns.length - 1;
		}

		session.follows();
		session.changed();
	}

	public function added():Void {
		final held = session.current();
		final length = held == null ? session.song.tempo.ppqn * 4 : held.length;

		session.does(new AddPattern(new Pattern(named(), length)));
		session.chooses(session.song.patterns.length - 1);
	}

	function named():String {
		return translate(Locale.PATTERN) + " " + (session.song.patterns.length + 1);
	}

	override function took(event:Input):Bool {
		if (super.took(event)) return true;

		switch (event.kind) {
			case Kind.PointerDown:
				final at = rowAt(event.y);
				if (at < 0) return false;

				if (event.button == Pointer.Right) {
					choose(at);
					popped(at, event.x, event.y);
					return true;
				}

				choose(at);
				return true;

			case Kind.PointerMove:
				final at = rowAt(event.y);
				if (at == hoverAt) return false;

				hoverAt = at;
				invalidate();
				return true;

			case Kind.KeyDown:
				if (event.code == Key.Down) {
					choose(session.pattern + 1);
					return true;
				}

				if (event.code == Key.Up) {
					choose(session.pattern - 1);
					return true;
				}

			case _:
		}

		return false;
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
		final tall = rowTall();

		contentHeight = session.song.patterns.length * tall;
		revealed(tall);

		paint.rect(x, y, width, height, theme.panel);
		paint.pushClip(x, y, width, height);
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height) / tall) + 1;
		if (last > session.song.patterns.length) last = session.song.patterns.length;

		painted = last - first;

		for (at in first...last) {
			final held = session.song.patterns[at];
			final top = y + at * tall - offsetY;
			final line = top + (tall - font.height) * 0.5 + font.ascent;

			if (at == session.pattern) paint.rect(x, top, width, tall, theme.accent, Theme.SELECT);
			else if (at == hoverAt) paint.rect(x, top, width, tall, theme.accent, Theme.HOVER);

			paint.rect(x, top + 2, metrics.whole(3), tall - 4, colour(held, at));
			paint.text(held.name, x + metrics.inset, line, theme.ink);

			paint.reface(small);
			paint.textRight(bars(held) + "   " + held.notes(), x + width - metrics.inset,
				line, theme.dim, 0.75);
			paint.reface(font);
		}

		paint.popClip();
	}

	function colour(held:Pattern, at:Int):Int {
		if (held.colour >= 0) return held.colour;
		return Theme.PARTS[at % Theme.PARTS.length];
	}

	function bars(held:Pattern):String {
		final bar = session.song.tempo.ppqn * 4;
		final whole = bar <= 0 ? 0 : Math.round(held.length / bar * 100) / 100;

		return whole + " " + translate(whole == 1 ? Locale.PATTERN_BAR : Locale.PATTERN_BARS);
	}
}
