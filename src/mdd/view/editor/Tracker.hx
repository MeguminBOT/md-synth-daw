package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
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

/**
	The same pattern as hexadecimal rows, one column per part.

	It is a view of the same notes the roll draws, not a second model, so an edit in
	either shows up in the other at once.
**/
final class Tracker extends Widget {
	static final LOWER:Array<Key> = [Key.Z, Key.S, Key.X, Key.D, Key.C, Key.V, Key.G, Key.B,
		Key.H, Key.N, Key.J, Key.M];

	static final UPPER:Array<Key> = [Key.Q, Key.Two, Key.W, Key.Three, Key.E, Key.R, Key.Five,
		Key.T, Key.Six, Key.Y, Key.Seven, Key.U];

	static final DIVISIONS:Array<Int> = [4, 8, 16, 32];

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		Which octave a typed note lands in.
	**/
	public var octave:Int = 4;

	/**
		Which chord runs each of the tracker's own actions. The defaults until the application
		hands over the reader's.
	**/
	public var bindings:mdd.app.Bindings = new mdd.app.Bindings();

	/**
		Where the cursor is, down.
	**/
	public var row(default, null):Int = 0;

	/**
		Where it is, across.
	**/
	public var column(default, null):Int = 0;

	/**
		How far the view is scrolled, down.
	**/
	public var offsetY:Float = 0;

	/**
		How far it is scrolled, across.
	**/
	public var offsetX:Float = 0;

	/**
		How many rows one bar is cut into.
	**/
	public var division:Int = 16;

	/**
		How many rows the cursor moves after a note is typed.
	**/
	public var advance:Int = 1;

	/**
		How many rows the last frame drew.
	**/
	public var painted(default, null):Int = 0;

	/**
		Whether a value is being typed into a cell.
	**/
	public var entering(default, null):Bool = false;

	/**
		What has been typed so far.
	**/
	public var entered(default, null):String = "";

	/**
		Called to sound a note as it is typed.
	**/
	public var onAudition:Null<(Part, Int) -> Void> = null;

	static inline final MOST_TYPED = 7;

	/**
		Builds the tracker.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	/**
		@return How tall one row is.
	**/
	public function rowTall():Float {
		final root = root();
		return root == null ? 18 : root.metrics.whole(18);
	}

	/**
		@return How wide the row numbers down the side are.
	**/
	public function numbers():Float {
		final root = root();
		return root == null ? 84 : root.metrics.whole(84);
	}

	/**
		@return How tall the column headers are.
	**/
	public function head():Float {
		final root = root();
		return root == null ? 26 : root.metrics.head;
	}

	/**
		@return How wide one column is.
	**/
	public function columnWide():Float {
		final root = root();
		final want = root == null ? 96.0 : root.metrics.whole(96);
		final room = (width - numbers()) / Part.COUNT;

		return room > want ? room : want;
	}

	/**
		@return How wide every column draws together.
	**/
	public function reach():Float {
		return columnWide() * Part.COUNT;
	}

	/**
		@return How many ticks one row is.
	**/
	public function step():Int {
		final ppqn = session.song.tempo.ppqn;
		final held = Math.round(ppqn * 4 / division);

		return held < 1 ? 1 : held;
	}

	inline function songly():Bool {
		return !session.alone && session.song.tracks.length > 0;
	}

	/**
		@return How many rows the pattern has.
	**/
	public function rows():Int {
		final span = songly() ? session.song.ends() : lengthOf();
		final many = Math.ceil(span / step());

		return many < 1 ? 1 : many;
	}

	function lengthOf():Int {
		final pattern = session.current();
		return pattern == null ? 0 : pattern.length;
	}

	/**
		@param tick A position in the piece, in ticks.
		@param part Which part.
		@return The clip playing there, or null.
	**/
	public function clipAt(tick:Int, part:Part):Null<mdd.song.Clip> {
		for (track in session.song.tracks) {
			if (!session.song.heard(track)) continue;

			for (clip in track.clips) {
				if (tick < clip.at || tick >= clip.ends()) continue;

				final pattern = session.song.patternAt(clip.pattern);
				if (pattern == null || pattern.lane(part).notes.length == 0) continue;

				return clip;
			}
		}

		return null;
	}

	function clipFor(tick:Int):Null<mdd.song.Clip> {
		for (track in session.song.tracks) {
			if (!session.song.heard(track)) continue;

			for (clip in track.clips) {
				if (tick < clip.at || tick >= clip.ends()) continue;
				if (session.song.patternAt(clip.pattern) == null) continue;

				return clip;
			}
		}

		return null;
	}

	/**
		@param tick A position in the piece, in ticks.
		@param part Which part.
		@return The lane the notes there live in, or null.
	**/
	public function laneAt(tick:Int, part:Part):Null<mdd.song.Lane> {
		if (!songly()) {
			final pattern = session.current();
			return pattern == null ? null : pattern.lane(part);
		}

		final clip = clipAt(tick, part);
		if (clip == null) return null;

		final pattern = session.song.patternAt(clip.pattern);
		return pattern == null ? null : pattern.lane(part);
	}

	function originAt(tick:Int, part:Part):Int {
		if (!songly()) return 0;

		final clip = clipAt(tick, part);
		return clip == null ? 0 : clip.at;
	}

	inline function tickOf(row:Int):Int {
		return row * step();
	}

	/**
		@param py A point, down.
		@return Which row is there.
	**/
	public function rowAt(py:Float):Int {
		final at = Std.int((py - y - head() + offsetY) / rowTall());
		return at < 0 || at >= rows() ? -1 : at;
	}

	function columnAt(px:Float):Int {
		final at = Std.int((px - x - numbers() + offsetX) / columnWide());
		return at < 0 || at >= Part.COUNT ? -1 : at;
	}

	/**
		@param which A column.
		@return Where it draws, across.
	**/
	public inline function atColumn(which:Int):Float {
		return x + numbers() + which * columnWide() - offsetX;
	}

	/**
		Whether the cell under the cursor is a held note rather than a new one.
	**/
	public var carried(default, null):Bool = false;

	/**
		@param row A row.
		@param column A column.
		@return The note that starts in that cell, or null.
	**/
	public function noteOf(row:Int, column:Int):Null<Note> {
		carried = false;

		if (row < 0 || column < 0) return null;

		final part:Part = column;
		final tick = tickOf(row);

		var lane:Null<mdd.song.Lane> = null;
		var origin = 0;

		if (songly()) {
			final clip = clipAt(tick, part);
			if (clip == null) return null;

			final pattern = session.song.patternAt(clip.pattern);
			if (pattern == null) return null;

			lane = pattern.lane(part);
			origin = clip.at;
		} else {
			final pattern = session.current();
			if (pattern == null) return null;

			lane = pattern.lane(part);
		}

		final at = tick - origin;
		final until = at + step();

		for (note in lane.notes) {
			if (note.at >= until) break;

			if (note.at >= at) return note;
			if (at < note.ends()) carried = true;
		}

		return null;
	}

	/**
		@param row A row.
		@param column A column.
		@return The note sounding in that cell, which may have started higher up.
	**/
	public function noteAt(row:Int, column:Int):Null<Note> {
		if (row < 0 || column < 0) return null;

		final part:Part = column;
		final tick = tickOf(row);
		final lane = laneAt(tick, part);
		if (lane == null) return null;

		final from = tick - originAt(tick, part);
		final until = from + step();

		for (note in lane.notes) {
			if (note.at >= from && note.at < until) return note;
		}

		return null;
	}

	/**
		@param row A row.
		@param column A column.
		@return Whether a note is being held through that cell rather than starting in it.
	**/
	public function holding(row:Int, column:Int):Bool {
		if (row < 0 || column < 0) return false;

		final part:Part = column;
		final tick = tickOf(row);
		final lane = laneAt(tick, part);
		if (lane == null) return false;

		final at = tick - originAt(tick, part);

		for (note in lane.notes) {
			if (note.at >= at) break;
			if (at < note.ends()) return true;
		}

		return false;
	}

	/**
		@return How thick a scrollbar is.
	**/
	public function reinTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	/**
		@return How wide the rows are, which is every column end to end.
	**/
	public function contentWidth():Float {
		return reach();
	}

	/**
		@return How deep they run.
	**/
	public function contentHeight():Float {
		return rows() * rowTall();
	}

	/**
		@return How much of the width shows the columns.
	**/
	public function acrossRoom():Float {
		final room = width - numbers();
		return room < 0 ? 0 : room;
	}

	/**
		@return How much of the height shows the rows.
	**/
	public function downRoom():Float {
		final room = height - head();
		return room < 0 ? 0 : room;
	}

	/**
		Scrolls to a place, clamped to the rows and the columns.

		@param px How far across.
		@param py How far down.
	**/
	public function scrollTo(px:Float, py:Float):Void {
		final far = contentWidth() - acrossRoom();
		final most = contentHeight() - downRoom();

		final across = px < 0 ? 0 : (px > far ? (far < 0 ? 0 : far) : px);
		final down = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);

		if (across == offsetX && down == offsetY) return;

		offsetX = across;
		offsetY = down;

		invalidate();
	}

	/**
		@param across How long the bar is.
		@param reach How much it stands for.
		@return How long its thumb is, never shorter than it can be grabbed by.
	**/
	function span(across:Float, reach:Float):Float {
		final root = root();
		final least = root == null ? 24.0 : root.metrics.whole(24);
		final held = reach <= 0 ? across : across * across / reach;

		return held < least ? least : held;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return 1 where the bar along the bottom is there, 2 where the one down the side is, and
			nought where neither is.
	**/
	function reinAt(px:Float, py:Float):Int {
		final thick = reinTall();
		final top = y + head();

		if (py >= top + downRoom() - thick && py < top + downRoom() && px >= x + numbers()
			&& contentWidth() > acrossRoom() + 0.5) return 1;

		if (px >= x + width - thick && py >= top && py < top + downRoom()
			&& contentHeight() > downRoom() + 0.5) return 2;

		return 0;
	}

	/**
		Scrolls to where a bar was dragged, with the thumb taken by its middle.

		@param px Where the pointer is, across.
		@param py Where it is, down.
	**/
	function reined(px:Float, py:Float):Void {
		if (reining == 1) {
			final across = acrossRoom();
			final held = span(across, contentWidth());
			final room = across - held;

			if (room <= 0) return;

			final want = (px - x - numbers() - held * 0.5) / room;
			scrollTo(want * (contentWidth() - across), offsetY);
			return;
		}

		final down = downRoom();
		final held = span(down, contentHeight());
		final room = down - held;

		if (room <= 0) return;

		final want = (py - y - head() - held * 0.5) / room;
		scrollTo(offsetX, want * (contentHeight() - down));
	}

	/**
		Draws the bar along the bottom and the one down the side, each only where its rows or its
		columns run past what is shown.
	**/
	function reins(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final thick = reinTall();
		final left = x + numbers();
		final top = y + head();
		final across = acrossRoom();
		final down = downRoom();

		if (contentWidth() > across + 0.5) {
			final held = span(across, contentWidth());
			final most = contentWidth() - across;
			final at = most <= 0 ? 0 : offsetX / most * (across - held);

			paint.rect(left, top + down - thick, across, thick, theme.sink, 0.7);
			paint.roundedRect(left + at, top + down - thick + metrics.whole(2), held,
				thick - metrics.whole(4), metrics.whole(2), theme.frame);
		}

		if (contentHeight() > down + 0.5) {
			final held = span(down, contentHeight());
			final most = contentHeight() - down;
			final at = most <= 0 ? 0 : offsetY / most * (down - held);

			paint.rect(x + width - thick, top, thick, down, theme.sink, 0.7);
			paint.roundedRect(x + width - thick + metrics.whole(2), top + at,
				thick - metrics.whole(4), held, metrics.whole(2), theme.frame);
		}
	}

	/**
		Which bar is being dragged: 1 along the bottom, 2 down the side, nought for neither.
	**/
	var reining:Int = 0;

	/**
		Scrolls the cursor into view.
	**/
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

	/**
		Moves the cursor.

		@param row A row.
		@param column A column.
	**/
	public function at(row:Int, column:Int):Void {
		this.row = row < 0 ? 0 : row;
		this.column = column < 0 ? 0 : (column >= Part.COUNT ? Part.COUNT - 1 : column);

		reveal();
	}

	/**
		Moves the cursor to follow the playhead.

		@param at A position in the piece, in ticks.
	**/
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

	/**
		Writes a note in the cell under the cursor and steps on.

		@param pitch A MIDI note number.
		@return The note, or null where it would not go there.
	**/
	public function place(pitch:Int):Null<Note> {
		final part:Part = column;
		final tick = tickOf(row);
		final which = writing(tick, part);
		if (which < 0) return null;

		final held = noteAt(row, column);
		if (held != null) session.does(new RemoveNote(which, part, held));

		final note = new Note(tick - writingAt(tick, part), step(), pitch, 100,
			session.song.rack[part.index()]);

		session.does(new AddNote(which, part, note));

		if (onAudition != null) onAudition(part, pitch);

		forward();
		return note;
	}

	override function edited(what:Int):Bool {
		switch (what) {
			case mdd.ui.Edit.COPY:
				return copies();

			case mdd.ui.Edit.CUT:
				if (!copies()) return false;

				erase();
				return true;

			case mdd.ui.Edit.PASTE:
				return pasted();

			case _:
		}

		return false;
	}

	function copies():Bool {
		final held = noteAt(row, column);
		if (held == null) return false;

		final made = held.copy();
		made.at = 0;

		session.copiedNotes.resize(0);
		session.copiedNotes.push(made);

		session.says(Locale.SAID_PITCH_COPIED, spelt(held.pitch, session.notation));
		session.changed();

		return true;
	}

	function pasted():Bool {
		if (session.copiedNotes.length == 0) return false;

		final one = session.copiedNotes[0];
		final made = place(one.pitch);

		if (made == null) return false;

		made.velocity = one.velocity;
		session.changed();

		return true;
	}

	/**
		Starts typing a value into the cell.
	**/
	public function opens():Void {
		if (entering) return;

		final held = noteAt(row, column);

		entered = held == null ? "" : spelt(held.pitch, session.notation) + " "
			+ hex(held.velocity >> 1);
		entering = true;
		typing = true;

		reveal();
	}

	/**
		Stops typing.

		@param keep Whether to apply what was typed.
	**/
	public function shuts(keep:Bool):Void {
		if (!entering) return;

		final said = entered;

		entering = false;
		typing = false;
		entered = "";

		if (keep) takes(said);

		invalidate();
	}

	function takes(said:String):Void {
		final held = StringTools.trim(said);
		if (held == "") return;

		if (held == "-" || held == "--" || held == "---"
			|| held.toLowerCase() == "off") {
			erase();
			return;
		}

		final pitch = pitched(held, session.notation);
		if (pitch < 0) {
			session.say(translate(Locale.TRACKER_UNREAD) + "  " + held);
			session.changed();
			return;
		}

		final note = place(pitch);
		final loud = louded(held);

		if (note != null && loud > 0) {
			note.velocity = loud;
			session.changed();
		}
	}

	/**
		@param said A typed note, such as C-4, C#4 or Db4.
		@param style How notes are written, English with sharps unless given.
		@return The MIDI note number, or -1 where it reads as no note.
	**/
	public static function pitched(said:String, style:Int = 0):Int {
		return mdd.song.Notation.read(said, style);
	}

	public static function louded(said:String):Int {
		final at = said.indexOf(" ");
		if (at < 0) return -1;

		final held = StringTools.trim(said.substr(at + 1));
		if (held == "") return -1;

		final value = Std.parseInt("0x" + held);
		if (value == null) return -1;

		final want = value << 1;
		return want < 1 ? 1 : (want > 127 ? 127 : want);
	}

	/**
		@param tick A position in the piece, in ticks.
		@param part Which part.
		@return Which pattern a note written there would go into.
	**/
	public function writing(tick:Int, part:Part):Int {
		if (!songly()) return session.pattern;

		final held = clipAt(tick, part);
		if (held != null) return held.pattern;

		final clip = clipFor(tick);
		return clip == null ? -1 : clip.pattern;
	}

	function writingAt(tick:Int, part:Part):Int {
		if (!songly()) return 0;

		final held = clipAt(tick, part);
		if (held != null) return held.at;

		final clip = clipFor(tick);
		return clip == null ? 0 : clip.at;
	}

	/**
		Removes the note under the cursor.
	**/
	public function cut():Void {
		final part:Part = column;
		final tick = tickOf(row);
		final lane = laneAt(tick, part);
		if (lane == null) return;

		final at = tick - originAt(tick, part);

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

	function erase():Void {
		final held = noteAt(row, column);
		if (held == null) {
			forward();
			return;
		}

		final part:Part = column;
		session.does(new RemoveNote(writing(tickOf(row), part), part, held));

		forward();
	}

	function pitchFor(code:Key):Int {
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
				final rein = reinAt(event.x, event.y);

				if (rein != 0) {
					reining = rein;
					reined(event.x, event.y);
					return true;
				}

				final at = rowAt(event.y);
				final which = columnAt(event.x);

				if (at < 0 || which < 0) {
					shuts(true);
					return false;
				}

				if (entering && (at != row || which != column)) shuts(true);

				row = at;
				column = which;

				session.choose(which);

				if (event.button == Pointer.Right) erase();
				else if (event.clicks > 1) opens();

				invalidate();
				return true;

			case Kind.PointerMove:
				if (reining == 0) return false;

				reined(event.x, event.y);
				return true;

			case Kind.PointerUp:
				if (reining == 0) return false;

				reining = 0;
				return true;

			case Kind.Text:
				if (!entering) return false;
				if (entered.length < MOST_TYPED) entered += event.said;

				invalidate();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	function steered(event:Input):Bool {
		if (entering) return typed(event);
		if (commanded(event)) return true;
		if (event.ctrl()) return false;

		if (event.code == Key.Return) {
			opens();
			return true;
		}

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

			case _:
		}

		if (!event.plain()) return false;

		final pitch = pitchFor(event.code);
		if (pitch < 0 || pitch > 127) return false;

		place(pitch);
		return true;
	}

	function typed(event:Input):Bool {
		switch (event.code) {
			case Key.Return, Key.Tab:
				shuts(true);
				return true;

			case Key.Escape:
				shuts(false);
				return true;

			case Key.Backspace:
				if (entered.length > 0) entered = entered.substr(0, entered.length - 1);

				invalidate();
				return true;

			case Key.Delete:
				entered = "";

				invalidate();
				return true;

			case _:
		}

		return !event.ctrl();
	}

	/**
		Runs the tracker's own action for a chord, where one has it.

		@param event The key.
		@return Whether an action took it.
	**/
	function commanded(event:Input):Bool {
		switch (bindings.actionIn(mdd.app.Bindings.TRACKER, event.code, event.mods)) {
			case mdd.app.Bindings.TRACKER_OCTAVE_UP:
				if (octave < 8) octave++;
				session.say(said(Locale.SAID_OCTAVE) + " " + octave);
				invalidate();

			case mdd.app.Bindings.TRACKER_OCTAVE_DOWN:
				if (octave > 0) octave--;
				session.say(said(Locale.SAID_OCTAVE) + " " + octave);
				invalidate();

			case mdd.app.Bindings.TRACKER_COARSER: divides(-1);
			case mdd.app.Bindings.TRACKER_FINER: divides(1);
			case mdd.app.Bindings.TRACKER_LOUDER: louder(8);
			case mdd.app.Bindings.TRACKER_QUIETER: louder(-8);
			case mdd.app.Bindings.TRACKER_CUT: cut();
			case _: return false;
		}

		return true;
	}

	function louder(by:Int):Void {
		final held = noteAt(row, column);
		if (held == null) return;

		session.does(new mdd.song.edit.SetVelocity(held, held.velocity + by));
		invalidate();
	}

	function said(key:Locale):String {
		final root = root();
		return root == null ? "" : translate(key);
	}

	/**
		@param pitch A MIDI note number.
		@param style How notes are written, English with sharps unless given.
		@return The note as a cell writes it, or three dashes outside the MIDI range.
	**/
	public static function spelt(pitch:Int, style:Int = 0):String {
		return mdd.song.Notation.cell(pitch, style);
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

		if (rows() < 1) return;

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

		final meter = session.song.meterOf(songly() ? null : session.current());
		final beat = Math.round(division / meter.unit);
		final bar = beat * meter.beats;

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

				final held = noteOf(at, index);
				final loud = session.song.audible(index) ? 1.0 : 0.4;

				if (held == null) {
					if (!carried) continue;

					paint.text("|", left + metrics.gap, baseline, theme.part(index), loud * 0.4);
					continue;
				}

				final said = spelt(held.pitch, session.notation) + " " + hex(held.velocity >> 1);

				paint.text(said, left + metrics.gap, baseline, theme.part(index), loud);
			}
		}

		if (row >= first && row < last) {
			final line = top + row * tall - offsetY;
			final left = atColumn(column);

			if (entering) {
				paint.rect(left, line, wide, tall, theme.raise2);

				final baseline = line + (tall - font.height) * 0.5 + font.ascent;
				final pen = left + metrics.gap;

				paint.text(entered, pen, baseline, theme.ink);
				paint.rect(pen + paint.measure(entered) + metrics.unit,
					line + metrics.whole(2), metrics.whole(2), tall - metrics.whole(4),
					theme.accent);
			}

			paint.outline(left, line, wide, tall, theme.accent,
				metrics.whole(entering ? 2 : 1));
		}

		for (index in 1...Part.COUNT) {
			final left = atColumn(index);
			if (left < x + numbers() || left > x + width) continue;

			paint.rect(left, top, hair, height - head(), theme.frame, 0.5);
		}

		paint.popClip();

		paint.rect(x + numbers() - hair, top, hair, height - head(), theme.frame);

		reins(paint, theme, metrics);
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

		paint.text("1/" + division + "  oct " + octave, x + metrics.gap,
			y + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.85);

		paint.rect(x, y + tall - hair, width, hair, theme.frame, 0.7);
	}
}
