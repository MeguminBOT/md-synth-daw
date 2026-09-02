package mdd.view;

import mdd.song.edit.AddNote;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.edit.RemoveNote;
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

	public static final DIVISIONS:Array<Int> = [4, 8, 16, 32];

	public final session:Session;

	public var octave:Int = 4;
	public var row(default, null):Int = 0;
	public var column(default, null):Int = 0;
	public var offsetY:Float = 0;
	public var offsetX:Float = 0;

	public var division:Int = 16;
	public var advance:Int = 1;

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
		return root == null ? 18 : root.metrics.whole(18);
	}

	public function numbers():Float {
		final root = root();
		return root == null ? 52 : root.metrics.whole(52);
	}

	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.whole(26);
	}

	public function columnWide():Float {
		final root = root();
		final want = root == null ? 96.0 : root.metrics.whole(96);
		final room = (width - numbers()) / Part.COUNT;

		return room > want ? room : want;
	}

	public function reach():Float {
		return columnWide() * Part.COUNT;
	}

	public function step():Int {
		final ppqn = session.song.tempo.ppqn;
		final held = Math.round(ppqn * 4 / division);

		return held < 1 ? 1 : held;
	}

	public function rows():Int {
		final pattern = session.current();
		if (pattern == null) return 0;

		final many = Math.ceil(pattern.length / step());
		return many < 1 ? 1 : many;
	}

	public inline function tickOf(row:Int):Int {
		return row * step();
	}

	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head() + offsetY) / rowTall());
		return at < 0 || at >= rows() ? -1 : at;
	}

	public function columnAt(px:Float):Int {
		final at = Std.int((px - x - numbers() + offsetX) / columnWide());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	public inline function atColumn(which:Int):Float {
		return x + numbers() + which * columnWide() - offsetX;
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

	public function holding(row:Int, column:Int):Bool {
		final pattern = session.current();
		if (pattern == null || row < 0 || column < 0) return false;

		final at = tickOf(row);
		final part:Part = column;

		for (note in pattern.lane(part).notes) {
			if (note.at >= at) break;
			if (at < note.ends()) return true;
		}

		return false;
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

		final wide = columnWide();
		final left = column * wide;
		final span = width - numbers();

		if (left < offsetX) offsetX = left;
		else if (left + wide > offsetX + span) offsetX = left + wide - span;

		final far = reach() - span;
		if (offsetX > far) offsetX = far < 0 ? 0 : far;
		if (offsetX < 0) offsetX = 0;

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

	function forward():Void {
		final many = rows();

		row += advance < 1 ? 1 : advance;
		if (row >= many) row = many - 1;

		reveal();
	}

	public function place(pitch:Int):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final part:Part = column;
		final held = noteAt(row, column);

		if (held != null) session.does(new RemoveNote(session.pattern, part, held));

		final note = new Note(tickOf(row), step(), pitch, 100,
			session.song.rack[part.index()]);

		session.does(new AddNote(session.pattern, part, note));

		if (onAudition != null) onAudition(part, pitch);

		forward();
	}

	public function cut():Void {
		final pattern = session.current();
		if (pattern == null) return;

		final part:Part = column;
		final at = tickOf(row);
		final lane = pattern.lane(part);

		var held:Null<Note> = null;

		for (note in lane.notes) {
			if (note.at >= at) break;
			held = note;
		}

		if (held != null && held.ends() > at) {
			held.length = at - held.at;
			session.changed();
		}

		forward();
	}

	public function erase():Void {
		final held = noteAt(row, column);
		if (held == null) {
			forward();
			return;
		}

		final part:Part = column;
		session.does(new RemoveNote(session.pattern, part, held));

		forward();
	}

	public function pitchFor(code:Key):Int {
		for (i in 0...LOWER.length) if (LOWER[i] == code) return (octave + 1) * 12 + i;
		for (i in 0...UPPER.length) if (UPPER[i] == code) return (octave + 2) * 12 + i;

		return -1;
	}

	function divides(by:Int):Void {
		final at = DIVISIONS.indexOf(division) + by;
		if (at < 0 || at >= DIVISIONS.length) return;

		division = DIVISIONS[at];
		session.say(said(Locale.TRACKER_DIVISION) + " 1/" + division);
		reveal();
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				if (event.shift()) {
					offsetX -= event.dy * columnWide() * 0.5;

					final far = reach() - (width - numbers());
					if (offsetX > far) offsetX = far < 0 ? 0 : far;
					if (offsetX < 0) offsetX = 0;

					invalidate();
					return true;
				}

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

				if (event.button == Pointer.Right) erase();

				invalidate();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	function steered(event:Input):Bool {
		if (event.ctrl()) return chorded(event);

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
				reveal();
				return true;

			case Key.Right:
				if (column + 1 < Part.COUNT) column++;
				session.choose(column);
				reveal();
				return true;

			case Key.Home:
				row = 0;
				reveal();
				return true;

			case Key.End:
				row = rows() - 1;
				reveal();
				return true;

			case Key.PageUp:
				row = row > 16 ? row - 16 : 0;
				reveal();
				return true;

			case Key.PageDown:
				row = row + 16 < rows() ? row + 16 : rows() - 1;
				reveal();
				return true;

			case Key.Delete, Key.Backspace:
				erase();
				return true;

			case Key.One:
				cut();
				return true;

			case _:
		}

		if (!event.plain()) return false;

		final pitch = pitchFor(event.code);
		if (pitch < 0 || pitch > 127) return false;

		place(pitch);
		return true;
	}

	function chorded(event:Input):Bool {
		switch (event.code) {
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

			case Key.Left:
				divides(-1);
				return true;

			case Key.Right:
				divides(1);
				return true;

			case Key.Up:
				louder(8);
				return true;

			case Key.Down:
				louder(-8);
				return true;

			case _:
		}

		return false;
	}

	function louder(by:Int):Void {
		final held = noteAt(row, column);
		if (held == null) return;

		final want = held.velocity + by;
		held.velocity = want < 1 ? 1 : (want > 127 ? 127 : want);

		session.changed();
		invalidate();
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
		final hair = metrics.whole(1);

		heading(paint, theme, metrics, wide);

		paint.pushClip(x, top, width, height - head());
		paint.reface(font);

		var first = Std.int(offsetY / tall);
		if (first < 0) first = 0;

		var last = Std.int((offsetY + height - head()) / tall) + 1;
		if (last > rows()) last = rows();

		painted = last - first;

		final beat = Math.round(division / 4);
		final bar = beat * 4;

		for (at in first...last) {
			final line = top + at * tall - offsetY;

			if (bar > 0 && at % bar == 0) paint.rect(x, line, width, tall, theme.raise1, 0.55);
			else if (beat > 0 && at % beat == 0) {
				paint.rect(x, line, width, tall, theme.raise1, 0.28);
			}

			if (at == row) paint.rect(x, line, width, tall, theme.accent, Theme.SELECT);

			final baseline = line + (tall - font.height) * 0.5 + font.ascent;

			paint.text(hex(at), x + metrics.unit * 2, baseline, theme.dim, 0.8);

			for (index in 0...Part.COUNT) {
				final left = atColumn(index);
				if (left + wide < x + numbers() || left > x + width) continue;

				final held = noteAt(at, index);
				final loud = session.song.audible(index) ? 1.0 : 0.4;

				if (held == null) {
					if (!holding(at, index)) continue;

					paint.text("|", left + metrics.gap, baseline, theme.part(index), loud * 0.4);
					continue;
				}

				final said = spelt(held.pitch) + " " + hex(held.velocity >> 1);

				paint.text(said, left + metrics.gap, baseline, theme.part(index), loud);
			}
		}

		if (row >= first && row < last) {
			final line = top + row * tall - offsetY;
			final left = atColumn(column);

			paint.outline(left, line, wide, tall, theme.accent, metrics.whole(1));
		}

		for (index in 1...Part.COUNT) {
			final left = atColumn(index);
			if (left < x + numbers() || left > x + width) continue;

			paint.rect(left, top, hair, height - head(), theme.frame, 0.5);
		}

		paint.popClip();

		paint.rect(x + numbers() - hair, top, hair, height - head(), theme.frame);
		paint.outline(x, y, width, height, theme.frame, hair);
	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics, wide:Float):Void {
		final small = metrics.small == null ? metrics.body : metrics.small;
		final tall = head();
		final hair = metrics.whole(1);

		paint.rect(x, y, width, tall, theme.bar);
		paint.reface(small);

		paint.pushClip(x + numbers(), y, width - numbers(), tall);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final left = atColumn(index);
			if (left + wide < x + numbers() || left > x + width) continue;

			final quiet = !session.song.audible(index);

			paint.rect(left + metrics.gap, y + tall - metrics.whole(4), wide - metrics.gap * 2,
				metrics.whole(2), theme.part(index), quiet ? 0.25 : 0.9);

			paint.text(part.name(), left + metrics.gap,
				y + (tall - small.height) * 0.5 + small.ascent,
				index == column ? theme.ink : theme.dim, quiet ? 0.5 : 1);
		}

		paint.popClip();

		paint.textRight("1/" + division + "   oct " + octave, x + numbers() - metrics.unit,
			y + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.85);

		paint.rect(x, y + tall - hair, width, hair, theme.frame);
	}
}
