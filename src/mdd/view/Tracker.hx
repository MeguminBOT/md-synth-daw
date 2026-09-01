package mdd.view;

import mdd.song.AddNote;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.RemoveNote;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Tracker extends Widget {
	static final NAMES:Array<String> = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#",
		"A-", "A#", "B-"];

	static final LOWER:Array<Key> = [Key.Z, Key.S, Key.X, Key.D, Key.C, Key.V, Key.G, Key.B,
		Key.H, Key.N, Key.J, Key.M];

	static final UPPER:Array<Key> = [Key.Q, Key.Two, Key.W, Key.Three, Key.E, Key.R, Key.Five,
		Key.T, Key.Six, Key.Y, Key.Seven, Key.U];

	public final session:Session;

	public var octave:Int = 4;
	public var row(default, null):Int = 0;
	public var column(default, null):Int = 0;
	public var offsetY:Float = 0;

	public var painted(default, null):Int = 0;

	public var onAudition:Null<(Part, Int) -> Void> = null;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 16 : root.metrics.whole(16);
	}

	public function numbers():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	public function head():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	public function columnWide():Float {
		return (width - numbers()) / Part.COUNT;
	}

	public function step():Int {
		return session.snap < 1 ? 1 : session.snap;
	}

	public function rows():Int {
		final pattern = session.current();
		if (pattern == null) return 0;

		return Std.int(pattern.length / step());
	}

	public inline function tickOf(row:Int):Int {
		return row * step();
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head() + offsetY) / rowTall());
		return at < 0 || at >= rows() ? -1 : at;
	}

	public function columnAt(px:Float):Int {
		final at = Std.int((px - x - numbers()) / columnWide());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	public function noteAt(row:Int, column:Int):Null<Note> {
		final pattern = session.current();
		if (pattern == null || row < 0 || column < 0) return null;

		final from = tickOf(row);
		final until = from + step();
		final part:Part = column;

		for (note in pattern.lane(part).notes) {
			if (note.at >= from && note.at < until) return note;
		}

		return null;
	}

	public function reveal():Void {
		final tall = rowTall();
		final top = row * tall;
		final room = height - head();

		if (top < offsetY) offsetY = top;
		else if (top + tall > offsetY + room) offsetY = top + tall - room;

		final most = rows() * tall - room;
		if (offsetY > most) offsetY = most < 0 ? 0 : most;
		if (offsetY < 0) offsetY = 0;

		invalidate();
	}

	public function at(row:Int, column:Int):Void {
		this.row = row < 0 ? 0 : row;
		this.column = column < 0 ? 0 : (column >= Part.COUNT ? Part.COUNT - 1 : column);

		reveal();
	}

	public function follow(at:Int):Void {
		if (at < 0 || at >= rows() || at == row) return;

		row = at;
		reveal();
	}

	public function place(pitch:Int):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final part:Part = column;
		final held = noteAt(row, column);

		if (held != null) session.does(new RemoveNote(session.pattern, part, held));

		final note = new Note(tickOf(row), step(), pitch, 100);
		session.does(new AddNote(session.pattern, part, note));

		if (onAudition != null) onAudition(part, pitch);

		row++;
		if (row >= rows()) row = rows() - 1;

		reveal();
	}

	public function erase():Void {
		final held = noteAt(row, column);
		if (held == null) return;

		final part:Part = column;
		session.does(new RemoveNote(session.pattern, part, held));

		row++;
		if (row >= rows()) row = rows() - 1;

		reveal();
	}

	public function pitchFor(code:Key):Int {
		for (i in 0...LOWER.length) if (LOWER[i] == code) return (octave + 1) * 12 + i;
		for (i in 0...UPPER.length) if (UPPER[i] == code) return (octave + 2) * 12 + i;

		return -1;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				offsetY -= event.dy * rowTall() * 3;

				final most = rows() * rowTall() - (height - head());
				if (offsetY > most) offsetY = most < 0 ? 0 : most;
				if (offsetY < 0) offsetY = 0;

				invalidate();
				return true;

			case Kind.PointerDown:
				final at = rowAt(event.y);
				final which = columnAt(event.x);

				if (at < 0 || which < 0) return false;

				row = at;
				column = which;

				session.choose(which);
				invalidate();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	function steered(event:Input):Bool {
		switch (event.code) {
			case Key.Up:
				if (row > 0) row--;
				reveal();
				return true;

			case Key.Down:
				if (row + 1 < rows()) row++;
				reveal();
				return true;

			case Key.Left:
				if (column > 0) column--;
				session.choose(column);
				invalidate();
				return true;

			case Key.Right:
				if (column + 1 < Part.COUNT) column++;
				session.choose(column);
				invalidate();
				return true;

			case Key.Delete, Key.Backspace:
				erase();
				return true;

			case Key.PageUp:
				if (octave < 8) octave++;
				session.say(said(Locale.SAID_OCTAVE) + " " + octave);
				invalidate();
				return true;

			case Key.PageDown:
				if (octave > 0) octave--;
				session.say(said(Locale.SAID_OCTAVE) + " " + octave);
				invalidate();
				return true;

			case _:
		}

		if (!event.plain()) return false;

		final pitch = pitchFor(event.code);
		if (pitch < 0 || pitch > 127) return false;

		place(pitch);
		return true;
	}

	function said(key:String):String {
		final root = root();
		return root == null ? key : translate(key);
	}

	public static function spelt(pitch:Int):String {
		if (pitch < 0 || pitch > 127) return "---";
		return NAMES[pitch % 12] + (Std.int(pitch / 12) - 1);
	}

	static function hex(value:Int):String {
		return StringTools.hex(value, 2);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.mono == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final font = metrics.mono;
		final small = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		final pattern = session.current();
		if (pattern == null) return;

		final tall = rowTall();
		final wide = columnWide();
		final top = y + head();

		paint.rect(x, y, width, head(), theme.bar);
		paint.reface(small);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = x + numbers() + index * wide;

			paint.textCentred(part.name(), left + wide * 0.5,
				y + (head() - small.height) * 0.5 + small.ascent,
				index == column ? theme.ink : theme.dim);
		}

		paint.textRight("oct " + octave, x + numbers() - metrics.unit,
			y + (head() - small.height) * 0.5 + small.ascent, theme.dim, 0.8);

		paint.pushClip(x, top, width, height - head());
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height - head()) / tall) + 1;
		if (last > rows()) last = rows();

		painted = last - first;

		for (at in first...last) {
			final line = top + at * tall - offsetY;

			if ((at & 15) == 0) paint.rect(x, line, width, tall, theme.raise1, 0.55);
			else if ((at & 3) == 0) paint.rect(x, line, width, tall, theme.raise1, 0.28);

			if (at == row) paint.rect(x, line, width, tall, theme.accent, Theme.SELECT);

			final baseline = line + (tall - font.height) * 0.5 + font.ascent;

			paint.text(hex(at), x + metrics.unit * 2, baseline, theme.dim, 0.7);

			for (index in 0...Part.COUNT) {
				final held = noteAt(at, index);
				if (held == null) continue;

				final left = x + numbers() + index * wide;
				final said = spelt(held.pitch) + " " + hex(held.velocity >> 3);

				paint.text(said, left + metrics.unit, baseline, theme.part(index),
					session.song.audible(index) ? 1 : 0.4);
			}
		}

		if (row >= first && row < last) {
			final line = top + row * tall - offsetY;
			final left = x + numbers() + column * wide;

			paint.outline(left, line, wide, tall, theme.accent, metrics.whole(1));
		}

		paint.popClip();

		paint.rect(x + numbers() - metrics.whole(1), top, metrics.whole(1), height - head(),
			theme.frame);
	}
}
