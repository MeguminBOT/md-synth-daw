package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.edit.AddClip;
import mdd.song.edit.AddTrack;
import mdd.song.Clip;
import mdd.song.edit.MoveClip;
import mdd.song.edit.MoveTrack;
import mdd.song.edit.RemoveClip;
import mdd.song.edit.RemoveTrack;
import mdd.song.edit.RenameTrack;
import mdd.song.edit.SizeClip;
import mdd.song.edit.SliceClip;
import mdd.song.Part;
import mdd.ui.Colour;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.view.Palette;
import mdd.view.Picked;

@:unreflective

/**
	The arrangement: clips over named tracks, in time.

	A clip carries where inside its pattern it starts, so slicing one keeps the music
	where it was. A clip with no colour of its own takes the track colour, and only
	then the theme.
**/
final class Playlist extends Widget {
	/**
		How many empty tracks to keep below the last used one, so there is always somewhere
		to drop a clip.
	**/
	public static inline final SPARE = 4;

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		How many pixels a tick is, which is the zoom.
	**/
	public var perTick:Float = 0.25;

	/**
		How far the view is scrolled, across.
	**/
	public var offsetX:Float = 0;

	/**
		How far it is scrolled, down.
	**/
	public var offsetY:Float = 0;

	/**
		How tall one track row is.
	**/
	public var rowTall:Float = 0;

	/**
		Where the playhead is, or -1 for nowhere.
	**/
	public var playhead:Int = -1;

	/**
		Which clip is chosen.
	**/
	public var chosen(default, null):Null<Clip> = null;

	/**
		Which clips are selected.
	**/
	public final picked:Picked<Clip> = new Picked<Clip>();

	/**
		How many clips the last frame drew.
	**/
	public var painted(default, null):Int = 0;

	/**
		Which chord reaches each tool, for the tooltips.
	**/
	public var bindings:Null<mdd.app.Bindings> = null;

	/**
		Called to rename a track.
	**/
	public var onRename:Null<Int -> Void> = null;

	/**
		Called to open a clip in the roll or the automation editor.
	**/
	public var onOpen:Null<Clip -> Void> = null;

	var chosenTrack:Int = -1;
	var scrubbing:Bool = false;
	var sizingRows:Int = -1;
	var hoverEdge:Int = -1;
	var dragging:Null<Clip> = null;
	var sizing:Bool = false;
	var grabTick:Int = 0;
	var grabWasAt:Int = 0;
	var grabFresh:Bool = false;
	var hoverTrack:Int = -1;
	var railing:Int = -1;
	var railTo:Int = -1;

	var banding:Bool = false;
	var painting:Int = -1;
	var paintAt:Int = 0;
	var paintLong:Int = 0;

	final laid:Array<Clip> = [];
	var bandFromX:Float = 0;
	var bandFromY:Float = 0;
	var bandToX:Float = 0;
	var bandToY:Float = 0;

	final moving:Array<Clip> = [];
	final movingRows:Array<Int> = [];
	final wereAt:Array<Int> = [];
	final wereLong:Array<Int> = [];
	var leastAt:Int = 0;
	var leastRow:Int = 0;
	var mostRow:Int = 0;
	var grabRow:Int = 0;
	var haulRows:Int = 0;

	/**
		Builds the playlist.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	/**
		The shortest a track row may be drawn.
	**/
	public static inline final LEAST_ROW = 16;

	/**
		The tallest.
	**/
	public static inline final MOST_ROW = 180;

	function trackTall():Float {
		final root = root();
		if (rowTall <= 0) return root == null ? 34 : root.metrics.row;

		final least = root == null ? LEAST_ROW : root.metrics.whole(LEAST_ROW);
		final most = root == null ? MOST_ROW : root.metrics.whole(MOST_ROW);

		return rowTall < least ? least : (rowTall > most ? most : rowTall);
	}

	function heighten(to:Float):Void {
		final was = trackTall();

		rowTall = to;
		if (trackTall() == was) return;

		scrollDown(offsetY);
		invalidate();
	}

	function rowEdgeAt(px:Float, py:Float):Int {
		if (px < x || px >= x + names() || py < y + ruler()) return -1;

		final tall = trackTall();
		final which = Math.round((py - y - ruler() + offsetY) / tall) - 1;

		if (which < 0 || which >= rows()) return -1;
		if (Math.abs(atTrack(which) + tall - py) > edge() * 0.7) return -1;

		return which;
	}

	/**
		@return How wide the track headers down the side are.
	**/
	public function names():Float {
		final root = root();
		return root == null ? 148 : root.metrics.whole(148);
	}

	/**
		@return How tall the ruler across the top is.
	**/
	public function ruler():Float {
		final root = root();
		return root == null ? 24 : root.metrics.ruler;
	}

	/**
		@return How many track rows to draw, which is the tracks plus a few spare.
	**/
	public function rows():Int {
		return session.song.tracks.length + SPARE;
	}

	/**
		@param tick A position in the piece, in ticks.
		@param free Whether to ignore the snap, which holding alt does.
		@return The tick snapped, or left alone.
	**/
	public inline function freely(tick:Int, free:Bool):Int {
		return free ? tick : session.snapped(tick);
	}

	/**
		@param px A point, across.
		@return Which tick is there.
	**/
	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - names() + offsetX) / perTick);
	}

	/**
		@param tick A position in the piece, in ticks.
		@return Where it draws, across.
	**/
	public inline function atTick(tick:Int):Float {
		return x + names() + tick * perTick - offsetX;
	}

	/**
		@param which A track.
		@return Where its row draws, down.
	**/
	public inline function atTrack(which:Int):Float {
		return y + ruler() + which * trackTall() - offsetY;
	}

	function trackAt(py:Float):Int {
		final at = Std.int((py - y - ruler() + offsetY) / trackTall());
		return at < 0 || at >= rows() ? -1 : at;
	}

	function muteAt(px:Float):Bool {
		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;
		final left = x + names() - metrics.whole(26);

		return px >= left && px < left + metrics.whole(18);
	}

	/**
		@return How near the end of a clip counts as its edge, for resizing.
	**/
	public function edge():Float {
		final root = root();
		return root == null ? 6 : root.metrics.whole(6);
	}

	/**
		@param clip A clip.
		@param px A point, across.
		@return Whether the point is on its edge rather than its body.
	**/
	public function onEdge(clip:Clip, px:Float):Bool {
		final right = atTick(clip.ends());
		final reach = edge();

		return px >= right - reach && px <= right + reach;
	}

	/**
		Changes how long a clip is.

		@param clip The clip.
		@param to The tick it should end on.
		@param free Whether to ignore the snap, which holding alt does.
	**/
	public function resized(clip:Clip, to:Int, free:Bool = false):Void {
		final least = free || session.snap < 1 ? 1 : session.snap;
		var want = freely(to, free) - clip.at;

		if (want < least) want = least;
		if (want == clip.length) return;

		clip.length = want;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return The clip there, or null.
	**/
	public function clipAt(px:Float, py:Float):Null<Clip> {
		final which = trackAt(py);
		if (which < 0 || which >= session.song.tracks.length) return null;

		final tick = tickAt(px);
		final track = session.song.tracks[which];

		for (clip in track.clips) {
			if (tick >= clip.at && tick < clip.ends()) return clip;
		}

		return null;
	}

	var framedFor:Int = -1;

	/**
		Zooms and scrolls so the whole piece fits.
	**/
	public function framed():Void {
		if (width <= 0) return;

		final beat = session.song.tempo.ppqn;
		if (beat < 1 || framedFor == beat) return;

		framedFor = beat;
		perTick = widest();

		scrollTo(0);
	}

	/**
		@return The tick the last clip on any track finishes on.
	**/
	public function reach():Int {
		final bar = session.song.tempo.ppqn * 4;
		final length = session.song.ends();

		return (length < bar ? bar : length) + bar * SPARE;
	}

	/**
		@return The zoom at which the piece exactly fills the view.
	**/
	public function widest():Float {
		final fits = (width - names()) / reach();
		return fits > 0.01 ? 0.01 : fits;
	}

	/**
		Zooms in or out, keeping a point where it was.

		@param by What to multiply the zoom by.
		@param around The point to keep still, across.
	**/
	public function zoom(by:Float, around:Float):Void {
		final tick = tickAt(around);
		final want = perTick * by;
		final least = widest();

		perTick = want < least ? least : (want > 1 ? 1 : want);
		scrollTo(tick * perTick - (around - x - names()));
	}

	/**
		Makes the track rows as tall as they can be while every one still fits.
	**/
	public function fit():Void {
		perTick = widest();
		scrollTo(0);
	}

	/**
		Scrolls across, clamped to the piece.

		@param px How far across.
	**/
	public function scrollTo(px:Float):Void {
		final most = reach() * perTick - (width - names());
		offsetX = px < 0 ? 0 : (px > most ? (most < 0 ? 0 : most) : px);
		invalidate();
	}

	/**
		Scrolls down, clamped to the tracks.

		@param py How far down.
	**/
	public function scrollDown(py:Float):Void {
		final most = rows() * trackTall() - (height - ruler());
		offsetY = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		invalidate();
	}

	/**
		The end of a note resizes it and the pan tool drags the view, and neither
		of those shows on the screen.

		@param px A point, across.
		@param py A point, down.
		@return Which cursor shape belongs there.
	**/
	override function cursorAt(px:Float, py:Float):Int {
		if (session.tool == Session.PAN) return mdd.host.Sdl.CURSOR_MOVE;

		if (sizing && dragging != null) return mdd.host.Sdl.CURSOR_ACROSS;

		final under = clipAt(px, py);
		if (under != null && onEdge(under, px)) return mdd.host.Sdl.CURSOR_ACROSS;

		return mdd.host.Sdl.CURSOR_ARROW;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				if ((event.ctrl() || event.alt()) && event.x < x + names()) {
					heighten(trackTall() * (event.dy > 0 ? 1.15 : 0.87));
					return true;
				}

				if (event.ctrl() || event.alt()) {
					zoom(event.dy > 0 ? 1.25 : 0.8, event.x);
					return true;
				}

				if (event.shift()) {
					scrollTo(offsetX - event.dy * trackTall() * 3);
					return true;
				}

				scrollDown(offsetY - event.dy * trackTall() * 2);
				return true;

			case Kind.PointerDown:
				if (painting >= 0) paintDropped();

				final rein = reinAt(event.x, event.y);

				if (rein != 0) {
					reining = rein;
					reined(event.x, event.y);
					return true;
				}

				if (event.y < y + ruler() && event.x >= x + names()) {
					scrubbing = true;
					scrubbed(event.x);
					return true;
				}

				final held = rowEdgeAt(event.x, event.y);

				if (held >= 0 && event.button == Pointer.Left) {
					sizingRows = held;
					return true;
				}

				if (event.clicks > 1 && event.button == Pointer.Left) {
					final under = clipAt(event.x, event.y);

					if (under != null && under.automates() && onOpen != null) {
						chosen = under;
						chosenTrack = trackAt(event.y);

						onOpen(under);
						return true;
					}
				}

				return pressed(event);

			case Kind.PointerMove:
				if (reining != 0) {
					reined(event.x, event.y);
					return true;
				}

				if (sizingRows >= 0) {
					heighten((event.y - y - ruler() + offsetY) / (sizingRows + 1));
					return true;
				}

				if (scrubbing) {
					scrubbed(event.x);
					return true;
				}

				if (railing >= 0) {
					reorders(trackAt(event.y));
					return true;
				}

				final edging = rowEdgeAt(event.x, event.y);

				if (edging != hoverEdge) {
					hoverEdge = edging;
					invalidate();
				}

				final which = trackAt(event.y);

				if (which != hoverTrack) {
					hoverTrack = which;
					invalidate();
				}

				if (banding) {
					bandToX = event.x;
					bandToY = event.y;
					invalidate();
					return true;
				}

				if (painting >= 0) {
					paints(event.x);
					return true;
				}

				if (dragging == null) return false;

				if (sizing) {
					resized(dragging, tickAt(event.x), event.alt());
					stretches(dragging, event.alt());
					invalidate();
					return true;
				}

				hauled(freely(tickAt(event.x) - grabTick, event.alt()), trackAt(event.y));

				invalidate();
				return true;

			case Kind.PointerUp:
				if (reining != 0) {
					reining = 0;
					return true;
				}

				if (sizingRows >= 0) {
					sizingRows = -1;
					return true;
				}

				if (scrubbing) {
					scrubbing = false;
					return true;
				}

				if (railing >= 0) {
					reordered();
					return true;
				}

				if (banding) {
					banded();
					return true;
				}

				if (painting >= 0) {
					paintDropped();
					return true;
				}

				if (dragging == null) return false;

				settled();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	/**
		Moves the playhead to a point on the ruler.

		@param px A point, across.
	**/
	public function scrubbed(px:Float):Void {
		final tick = session.snapped(tickAt(px));
		final want = tick < 0 ? 0 : tick;

		session.transport.seek(session.song.tempo.samplesAt(want));
		playhead = want;

		invalidate();
	}

	function pressed(event:Input):Bool {
		final which = trackAt(event.y);
		if (which < 0) return false;

		if (event.x < x + names()) return railed(which, event);

		final under = clipAt(event.x, event.y);

		if (under != null && event.button == Pointer.Left
			&& onCorner(under, which, event.x, event.y)) {
			alters(under, which, false, false);
			clipped(under, which, event.x, event.y);

			invalidate();
			return true;
		}

		if (event.button == Pointer.Right) {
			if (under != null) {
				picked.drops(under);
				if (chosen == under) chosen = picked.lead();

				session.does(new RemoveClip(which, under));
				invalidate();
			}
			return true;
		}

		if (under != null) {
			if (session.tool == Session.SLICE && event.button == Pointer.Left) {
				sliced(which, under, freely(tickAt(event.x), event.alt()));
				return true;
			}

			final adding = event.shift() || event.ctrl();
			alters(under, which, event.shift(), event.ctrl());

			if (adding) {
				invalidate();
				return true;
			}

			dragging = under;
			sizing = onEdge(under, event.x);
			grabTick = sizing ? 0 : tickAt(event.x) - under.at;
			grabWasAt = under.at;
			grabFresh = false;
			grabRow = which;
			grabs(under);
			invalidate();
			return true;
		}

		if (session.tool != Session.DRAW || event.shift() || event.ctrl()) {
			bands(event);
			return true;
		}

		final pattern = session.current();
		if (pattern == null) return true;

		if (which >= session.song.tracks.length) session.does(new AddTrack(which));

		final at = freely(tickAt(event.x), event.alt());
		final clip = new Clip(session.pattern, at < 0 ? 0 : at, pattern.length);

		painting = which;
		paintAt = clip.at;
		paintLong = clip.length;

		laid.resize(0);
		lays(clip);

		picked.only(clip);
		chosen = clip;
		chosenTrack = which;

		invalidate();
		return true;
	}

	/**
		Puts a clip on the track being painted without writing to the undo stack, which is
		what leaves a drag across four bars one step there rather than four.

		@param clip The clip.
	**/
	function lays(clip:Clip):Void {
		final tracks = session.song.tracks;
		if (painting < 0 || painting >= tracks.length) return;

		session.holds();
		tracks[painting].add(clip);
		session.frees();

		laid.push(clip);
	}

	/**
		Lays or takes back copies so the run reaches wherever the pointer is.

		The run only ever grows to the right, because a clip is laid where the press was and
		dragging back over it would otherwise take away the one asked for.

		@param px A point, across.
	**/
	function paints(px:Float):Void {
		final pattern = session.current();
		if (pattern == null || paintLong < 1) return;

		final reach = tickAt(px) - paintAt;
		var want = reach < 0 ? 1 : Std.int(reach / paintLong) + 1;

		if (want < 1) want = 1;
		if (want == laid.length) return;

		final tracks = session.song.tracks;
		if (painting < 0 || painting >= tracks.length) return;

		session.holds();

		while (laid.length > want) {
			tracks[painting].remove(laid.pop());
		}

		while (laid.length < want) {
			laid.push(tracks[painting].add(new Clip(session.pattern,
				paintAt + laid.length * paintLong, paintLong)));
		}

		session.frees();

		chosen = laid[laid.length - 1];
		picked.only(chosen);

		invalidate();
	}

	/**
		Takes the painted run back off and lays it again as one step on the undo stack.
	**/
	function paintDropped():Void {
		final track = painting;

		painting = -1;
		if (laid.length == 0) return;

		final tracks = session.song.tracks;

		if (track >= 0 && track < tracks.length) {
			session.holds();
			for (clip in laid) tracks[track].remove(clip);
			session.frees();
		}

		if (laid.length == 1) {
			session.does(new AddClip(track, laid[0]));
		} else {
			final group = new mdd.song.edit.Together("add " + counted(laid.length));

			for (clip in laid) group.also(new AddClip(track, clip));

			session.does(group);
		}

		chosen = laid[laid.length - 1];
		picked.only(chosen);
		chosenTrack = track;

		laid.resize(0);

		session.changed();
		invalidate();
	}

	function sliced(which:Int, clip:Clip, at:Int):Void {
		if (!SliceClip.splits(clip, at)) return;

		final was = clip.length;

		session.does(new SliceClip(which, clip, at));

		picked.only(clip);
		chosen = clip;
		chosenTrack = which;

		session.says(Locale.SAID_SLICED, "" + clip.length, "" + (was - clip.length));
		invalidate();
	}

	function trackOf(clip:Clip):Int {
		final tracks = session.song.tracks;

		for (index in 0...tracks.length) {
			if (tracks[index].clips.indexOf(clip) >= 0) return index;
		}

		return -1;
	}

	/**
		@param many How many there are.
		@return What to call them in an undo entry. Those name a step for the gate to
			recognise rather than for a reader, and nothing puts one on screen, so this
			stays in one language.
	**/
	static function counted(many:Int):String {
		return many + (many == 1 ? " clip" : " clips");
	}

	/**
		@return The selected clips, or the chosen one where nothing is selected.
	**/
	public function held():Array<Clip> {
		final out:Array<Clip> = [];

		for (track in session.song.tracks) {
			for (clip in track.clips) if (picked.holds(clip)) out.push(clip);
		}

		return out;
	}

	function alters(lead:Clip, which:Int, shift:Bool, ctrl:Bool):Void {
		picked.alters(everything(), chosen, lead, shift, ctrl);

		final on = picked.holds(lead);

		chosen = on ? lead : picked.lead();
		chosenTrack = chosen == null ? -1 : (on ? which : trackOf(chosen));
	}

	function everything():Array<Clip> {
		final out:Array<Clip> = [];

		for (track in session.song.tracks) {
			for (clip in track.clips) out.push(clip);
		}

		return out;
	}

	/**
		Selects every clip.

		@return Whether anything was selected.
	**/
	public function picksAll():Bool {
		final all = everything();
		final many = all.length;

		if (many == 0) return false;

		picked.clear();
		for (clip in all) picked.adds(clip);

		chosen = picked.lead();
		chosenTrack = chosen == null ? -1 : trackOf(chosen);

		session.says(Locale.SAID_CLIPS_SELECTED, "" + many);
		session.changed();

		invalidate();
		return true;
	}

	override function edited(what:Int):Bool {
		switch (what) {
			case mdd.ui.Edit.ALL:
				return picksAll();

			case mdd.ui.Edit.COPY:
				return copies();

			case mdd.ui.Edit.CUT:
				if (!copies()) return false;
				erased();
				return true;

			case mdd.ui.Edit.PASTE:
				if (session.copiedClips.length == 0) return false;

				pasted(session.snapped(playhead < 0 ? 0 : playhead),
					chosenTrack < 0 ? 0 : chosenTrack);
				return true;

			case _:
		}

		return false;
	}

	function copies():Bool {
		final held = held();
		if (held.length == 0) return false;

		var least = held[0].at;
		var top = trackOf(held[0]);

		for (clip in held) {
			final row = trackOf(clip);

			if (clip.at < least) least = clip.at;
			if (row >= 0 && row < top) top = row;
		}

		session.copiedClips.resize(0);
		session.copiedRows.resize(0);

		for (clip in held) {
			final row = trackOf(clip);
			final made = clip.copy();

			made.at -= least;

			session.copiedClips.push(made);
			session.copiedRows.push(row < 0 ? 0 : row - top);
		}

		session.says(Locale.SAID_CLIPS_COPIED, "" + held.length);
		session.changed();

		return true;
	}

	function pasted(at:Int, onto:Int):Void {
		final copied = session.copiedClips;
		if (copied.length == 0) return;

		final where = at < 0 ? 0 : at;
		final made:Array<Clip> = [];
		final rows:Array<Int> = [];

		for (index in 0...copied.length) {
			final clip = copied[index].copy();
			clip.at = where + clip.at;

			made.push(clip);
			rows.push(onto + session.copiedRows[index]);
		}

		final group = new mdd.song.edit.Together("paste " + counted(made.length));

		for (index in 0...made.length) {
			var row = rows[index];
			if (row < 0) row = 0;

			if (row >= session.song.tracks.length) group.also(new AddTrack(row));
			group.also(new AddClip(row, made[index]));
		}

		session.does(group);

		picked.clear();
		for (clip in made) picked.adds(clip);

		chosen = picked.lead();
		chosenTrack = chosen == null ? -1 : trackOf(chosen);

		session.says(Locale.SAID_CLIPS_PASTED, "" + made.length);
		invalidate();
	}

	function erased():Void {
		final held = held();
		if (held.length == 0) return;

		final group = new mdd.song.edit.Together("remove " + counted(held.length));
		var many = 0;

		for (clip in held) {
			final row = trackOf(clip);
			if (row < 0) continue;

			group.also(new RemoveClip(row, clip));
			many++;
		}

		if (many == 0) return;
		session.does(group);

		picked.clear();
		chosen = null;

		invalidate();
	}

	/**
		Gives every other clip being resized the change of length the dragged one has taken, so a
		selection resizes together. None goes shorter than a snap step.

		@param lead The clip being dragged.
		@param free Whether the snap is ignored, which holding alt does.
	**/
	function stretches(lead:Clip, free:Bool):Void {
		if (moving.length < 2) return;

		final at = moving.indexOf(lead);
		if (at < 0) return;

		final change = lead.length - wereLong[at];
		final least = free || session.snap < 1 ? 1 : session.snap;

		for (index in 0...moving.length) {
			if (index == at) continue;

			final want = wereLong[index] + change;
			moving[index].length = want < least ? least : want;
		}
	}

	function grabs(lead:Clip):Void {
		moving.resize(0);
		movingRows.resize(0);
		wereAt.resize(0);
		wereLong.resize(0);

		if (picked.count > 1 && picked.holds(lead)) {
			for (index in 0...picked.count) moving.push(picked.at(index));
		} else {
			moving.push(lead);
		}

		leastAt = moving[0].at;

		haulRows = 0;
		leastRow = -1;
		mostRow = -1;

		for (clip in moving) {
			final row = trackOf(clip);

			movingRows.push(row);
			wereAt.push(clip.at);
			wereLong.push(clip.length);

			if (clip.at < leastAt) leastAt = clip.at;
			if (row < 0) continue;

			if (leastRow < 0 || row < leastRow) leastRow = row;
			if (row > mostRow) mostRow = row;
		}

		if (leastRow < 0) {
			leastRow = grabRow;
			mostRow = grabRow;
		}
	}

	function hauled(at:Int, row:Int):Void {
		var by = at - grabWasAt;
		if (leastAt + by < 0) by = -leastAt;

		for (index in 0...moving.length) moving[index].at = wereAt[index] + by;

		final most = session.song.tracks.length - 1;
		var down = (row < 0 ? grabRow : row) - grabRow;

		if (leastRow + down < 0) down = -leastRow;
		if (mostRow + down > most) down = most - mostRow;

		haulRows = down;
	}

	inline function hauling(clip:Clip):Bool {
		return moving.indexOf(clip) >= 0;
	}

	function bands(event:Input):Void {
		banding = true;
		bandFromX = event.x;
		bandFromY = event.y;
		bandToX = event.x;
		bandToY = event.y;

		if (!event.ctrl()) {
			picked.clear();
			chosen = null;
		}

		invalidate();
	}

	function banded():Void {
		banding = false;

		final left = bandFromX < bandToX ? bandFromX : bandToX;
		final right = bandFromX < bandToX ? bandToX : bandFromX;
		final top = bandFromY < bandToY ? bandFromY : bandToY;
		final floor = bandFromY < bandToY ? bandToY : bandFromY;

		if (right - left < 2 && floor - top < 2) {
			invalidate();
			return;
		}

		final from = tickAt(left);
		final to = tickAt(right);
		final first = trackAt(top);
		final last = trackAt(floor);

		final tracks = session.song.tracks;
		final head = first < 0 ? 0 : first;
		final tail = last < 0 ? tracks.length - 1 : last;

		for (which in head...tail + 1) {
			if (which >= tracks.length) break;

			for (clip in tracks[which].clips) {
				if (clip.ends() <= from || clip.at >= to) continue;
				picked.adds(clip);
			}
		}

		chosen = picked.lead();
		chosenTrack = chosen == null ? -1 : trackOf(chosen);

		if (picked.count > 0) session.says(Locale.SAID_CLIPS_SELECTED, "" + picked.count);
		session.changed();

		invalidate();
	}

	function settled():Void {
		final held = dragging;

		dragging = null;

		if (held == null || grabFresh) {
			sizing = false;
			grabFresh = false;
			haulRows = 0;
			session.changed();
			return;
		}

		if (sizing) sized();
		else hauledDone();

		sizing = false;
		haulRows = 0;
		session.changed();
	}

	function sized():Void {
		var many = 0;
		for (index in 0...moving.length) if (moving[index].length != wereLong[index]) many++;
		if (many == 0) return;

		final wants:Array<Int> = [];
		for (clip in moving) wants.push(clip.length);

		for (index in 0...moving.length) moving[index].length = wereLong[index];

		if (moving.length == 1) {
			session.does(new SizeClip(rowOf(0), moving[0], wants[0]));
			return;
		}

		final group = new mdd.song.edit.Together("resize " + counted(moving.length));
		for (index in 0...moving.length) {
			group.also(new SizeClip(rowOf(index), moving[index], wants[index]));
		}

		session.does(group);
	}

	function hauledDone():Void {
		final down = haulRows;

		var many = 0;
		for (index in 0...moving.length) if (moving[index].at != wereAt[index]) many++;
		if (many == 0 && down == 0) return;

		final wants:Array<Int> = [];
		for (clip in moving) wants.push(clip.at);

		for (index in 0...moving.length) moving[index].at = wereAt[index];

		if (moving.length == 1) {
			final row = rowOf(0);
			session.does(new MoveClip(row, moving[0], wants[0], moving[0].transpose, row + down));
		} else {
			final group = new mdd.song.edit.Together("move " + counted(moving.length));

			for (index in 0...moving.length) {
				final row = rowOf(index);
				group.also(new MoveClip(row, moving[index], wants[index],
					moving[index].transpose, row + down));
			}

			session.does(group);
		}

		if (down != 0) chosenTrack = chosen == null ? -1 : trackOf(chosen);
	}

	inline function rowOf(index:Int):Int {
		final held = movingRows[index];
		return held < 0 ? chosenTrack : held;
	}

	function railed(which:Int, event:Input):Bool {
		if (event.button == Pointer.Right) {
			popped(which, event.x, event.y);
			return true;
		}

		if (which >= session.song.tracks.length) {
			session.does(new AddTrack(which));
			chosenTrack = which;
			invalidate();
			return true;
		}

		if (muteAt(event.x)) {
			final track = session.song.tracks[which];

			session.does(new mdd.song.edit.MuteTrack(which, !track.muted));
			session.says(track.muted ? Locale.SAID_MUTED : Locale.SAID_UNMUTED, track.name);
			invalidate();
			return true;
		}

		chosenTrack = which;
		railing = which;
		railTo = which;

		invalidate();
		return true;
	}

	function reorders(want:Int):Void {
		final most = session.song.tracks.length - 1;
		final onto = want < 0 ? railTo : (want > most ? most : want);

		if (onto == railTo) return;

		railTo = onto;
		invalidate();
	}

	function reordered():Void {
		final from = railing;
		final to = railTo;

		railing = -1;
		railTo = -1;

		if (from >= 0 && to >= 0 && from != to) {
			session.does(new MoveTrack(from, to));

			chosenTrack = to;
			session.says(Locale.SAID_TRACK_MOVED, session.song.tracks[to].name);
		}

		invalidate();
	}

	/**
		@return How large the corner triangle on a clip is.
	**/
	public function cornerSize():Float {
		final root = root();
		return root == null ? 12 : root.metrics.whole(12);
	}

	/**
		@param clip A clip.
		@param track Which track it is on.
		@param px A point, across.
		@param py A point, down.
		@return Whether the point is on its corner, which is what opens its menu.
	**/
	public function onCorner(clip:Clip, track:Int, px:Float, py:Float):Bool {
		final size = cornerSize();
		final wide = clip.length * perTick;

		if (wide < size * 2 || trackTall() < size * 1.6) return false;

		final at = atTick(clip.at);
		final row = atTrack(track) + 2;

		return px >= at && px < at + size && py >= row && py < row + size;
	}

	function clipped(clip:Clip, track:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final menu = new Menu();

		final open = menu.offer(new Choice(translate(Locale.CLIP_OPEN)));

		open.enabled = onOpen != null;
		fires(open, function():Void if (onOpen != null) onOpen(clip));

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.ROLL_COPY),
			mdd.app.Bindings.of(bindings, mdd.app.Bindings.COPY))), function():Void copies());

		fires(menu.offer(new Choice(translate(Locale.ROLL_CUT),
			mdd.app.Bindings.of(bindings, mdd.app.Bindings.CUT))), function():Void {
			copies();
			erased();
		});

		final paste = menu.offer(new Choice(translate(Locale.ROLL_PASTE),
			mdd.app.Bindings.of(bindings, mdd.app.Bindings.PASTE)));

		paste.enabled = session.copiedClips.length > 0;
		fires(paste, function():Void pasted(clip.ends(), track));

		fires(menu.offer(new Choice(translate(Locale.ROLL_DELETE), "Del")),
			function():Void erased());

		menu.divide();

		fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_UP))),
			function():Void transposed(12));
		fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_DOWN))),
			function():Void transposed(-12));

		root.pop(menu, px, py, this);
	}

	function corner(paint:Paint, theme:Theme, metrics:Metrics, clip:Clip, at:Float,
			row:Float, wide:Float, colour:Colour, alpha:Float):Void {
		final size = cornerSize();
		if (wide < size * 2 || trackTall() < size * 1.6) return;

		final inset = metrics.whole(3);
		final reach = size - inset * 2;

		final points = arrow;

		points[0] = at + inset;
		points[1] = row + inset;
		points[2] = at + inset + reach;
		points[3] = row + inset;
		points[4] = at + inset;
		points[5] = row + inset + reach;

		paint.polygon(points, 3, colour, alpha);
	}

	final arrow:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(6);

	function popped(which:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final song = session.song;
		final menu = new Menu();
		final held = which < song.tracks.length ? song.tracks[which] : null;

		fires(menu.offer(new Choice(translate(Locale.TRACK_ADD))), function():Void {
			session.does(new AddTrack(song.tracks.length));
		});

		if (held != null) {
			final drives = new Menu();

			for (one in mdd.view.Parameter.of(session.part)) {
				if (!one.operators) {
					driven(drives, held, one, one.target, 0, px);
					continue;
				}

				final slots = new Menu();
				for (slot in 0...4) driven(slots, held, one, one.target, slot, px);

				drives.offer(new Choice(one.name)).submenu = slots;
			}

			menu.offer(new Choice(translate(Locale.TRACK_AUTOMATE)
				+ "  " + session.part.name())).submenu = drives;

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.TRACK_RENAME))), function():Void {
				if (onRename != null) onRename(which);
			});

			menu.offer(new Choice(translate(Locale.COLOUR_PICK))).submenu = coloured(which);
			menu.offer(new Choice(translate(Locale.ICON_PICK))).submenu = icons(which);

			fires(menu.offer(new Choice(translate(held.muted
					? Locale.TRACK_UNMUTE : Locale.TRACK_MUTE))), function():Void {
				session.does(new mdd.song.edit.MuteTrack(which, !held.muted));
			});

			menu.divide();

			final names = menu.offer(new Choice(translate(Locale.TRACK_AUTO_NAME)));

			names.enabled = held.clips.length > 0;
			if (!names.enabled) names.reason = translate(Locale.TRACK_NOTHING_TO_NAME);

			fires(names, function():Void {
				final want = named(held);
				if (want != "") session.does(new RenameTrack(which, want));
			});

			final dressed = menu.offer(new Choice(translate(Locale.TRACK_AUTO_NAME_CLIPS)));

			dressed.enabled = held.clips.length > 0;
			if (!dressed.enabled) dressed.reason = translate(Locale.TRACK_NOTHING_TO_NAME);

			fires(dressed, function():Void dresses(which, held));

			final folds = menu.offer(new Choice(translate(Locale.TRACK_MERGE_CLIPS)));

			folds.enabled = mdd.song.edit.MergeClips.merges(held);
			if (!folds.enabled) folds.reason = translate(Locale.TRACK_NOTHING_TO_MERGE);

			fires(folds, function():Void {
				session.does(new mdd.song.edit.MergeClips(which,
					held.name == "" ? "merged" : held.name));

				picked.clear();
				chosen = null;
			});

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.TRACK_INSERT))), function():Void {
				session.does(new mdd.song.edit.InsertTrack(which,
					"track " + (song.tracks.length + 1)));
			});

			fires(menu.offer(new Choice(translate(Locale.TRACK_CLONE))), function():Void {
				session.does(new mdd.song.edit.CloneTrack(which));
			});

			fires(menu.offer(new Choice(translate(Locale.TRACK_RESET))), function():Void {
				session.does(new mdd.song.edit.ResetTrack(which,
					"track " + (which + 1)));
			});

			menu.divide();

			final drop = menu.offer(new Choice(translate(Locale.TRACK_DELETE)));

			drop.enabled = song.tracks.length > 1;
			if (!drop.enabled) drop.reason = translate(Locale.TRACK_LAST);

			fires(drop, function():Void {
				session.does(new RemoveTrack(which));

				picked.clear();
				chosen = null;
				chosenTrack = -1;
			});
		}

		root.pop(menu, px, py, this);
	}

	function named(track:mdd.song.Track):String {
		final song = session.song;

		for (clip in track.clips) {
			final pattern = song.patternAt(clip.pattern);
			if (pattern != null && pattern.name != "") return pattern.name;
		}

		return "";
	}

	function dresses(which:Int, track:mdd.song.Track):Void {
		final song = session.song;
		final all = new mdd.song.edit.Together(translate(Locale.TRACK_AUTO_NAME_CLIPS));
		final done:Array<Int> = [];

		for (clip in track.clips) {
			if (clip.kind != mdd.song.Clip.PATTERN) continue;
			if (done.indexOf(clip.pattern) >= 0) continue;

			final pattern = song.patternAt(clip.pattern);
			if (pattern == null) continue;

			done.push(clip.pattern);

			final want = track.name + " " + (done.length);

			if (pattern.name != want) {
				all.also(new mdd.song.edit.RenamePattern(clip.pattern, want));
			}

			if (track.colour >= 0 && pattern.colour != track.colour) {
				all.also(new mdd.song.edit.ColourPattern(clip.pattern, track.colour));
			}
		}

		if (all.count() > 0) session.does(all);
	}

	function coloured(which:Int):Menu {
		final out = new Menu();

		fires(out.offer(new Choice(translate(Locale.COLOUR_NONE))), function():Void {
			session.does(new mdd.song.edit.ColourTrack(which, -1));
		});

		out.divide();

		for (index in 0...Palette.COLOURS.length) {
			final want = Palette.COLOURS[index];

			fires(out.offer(new Choice(translate(Palette.NAMES[index]))), function():Void {
				session.does(new mdd.song.edit.ColourTrack(which, want));
			});
		}

		return out;
	}

	function icons(which:Int):Menu {
		final out = new Menu();

		fires(out.offer(new Choice(translate(Locale.ICON_NONE))), function():Void {
			session.does(new mdd.song.edit.IconTrack(which, -1));
		});

		out.divide();

		final seen:Array<String> = [];
		for (group in mdd.Icon.GROUPS) if (seen.indexOf(group) < 0) seen.push(group);

		for (group in seen) out.offer(new Choice(grouped(group))).submenu = drawn(which, group);

		return out;
	}

	function grouped(group:String):String {
		return switch (group) {
			case "shape": translate(Locale.ICON_SHAPES);
			case "audio": translate(Locale.ICON_AUDIO);
			case "instrument": translate(Locale.ICON_INSTRUMENTS);
			case _: group;
		}
	}

	function drawn(which:Int, group:String):Menu {
		final out = new Menu();

		for (index in 0...mdd.Icon.COUNT) {
			if (mdd.Icon.GROUPS[index] != group) continue;

			final want = index;

			fires(out.offer(new Choice(mdd.Icon.NAMES[want])), function():Void {
				session.does(new mdd.song.edit.IconTrack(which, want));
			});
		}

		return out;
	}

	function driven(into:Menu, track:mdd.song.Track, held:mdd.view.Parameter, target:Int,
			slot:Int, px:Float):Void {
		final one = into.offer(new Choice(held.titled(slot)));
		one.reason = translate(held.about);

		fires(one, function():Void {
			final bar = session.song.tempo.ppqn * 4;

			var at = session.snapped(tickAt(px));
			if (at < 0) at = 0;

			final made = mdd.song.Clip.drives(session.part, target, slot, at, bar * 2);
			final line = made.line;

			if (line != null) {
				line.add(new mdd.song.Point(0, 0));

				final tail = new mdd.song.Point(bar * 2, 0);
				line.points[0].shape = held.smooth ? mdd.song.Automation.LINEAR
					: mdd.song.Automation.HOLD;

				line.add(tail);
			}

			session.does(new mdd.song.edit.AddClip(session.song.tracks.indexOf(track), made));

			picked.only(made);
			chosen = made;
			chosenTrack = session.song.tracks.indexOf(track);

			session.say(held.titled(slot) + "  " + session.part.name());
		});
	}

	function steered(event:Input):Bool {
		if (event.code == Key.Escape && picked.count > 0) {
			picked.clear();
			chosen = null;
			invalidate();
			return true;
		}

		if (picked.count == 0) return false;

		switch (event.code) {
			case Key.Delete, Key.Backspace:
				erased();
				return true;

			case Key.Up:
				transposed(1);
				return true;

			case Key.Down:
				transposed(-1);
				return true;

			case _:
		}

		return false;
	}

	function transposed(by:Int):Void {
		final held = held();
		if (held.length == 0) return;

		if (held.length == 1) {
			final row = trackOf(held[0]);
			if (row < 0) return;

			session.does(new MoveClip(row, held[0], held[0].at, held[0].transpose + by));
			invalidate();
			return;
		}

		final group = new mdd.song.edit.Together((by > 0 ? "raise " : "lower ")
			+ counted(held.length));

		for (clip in held) {
			final row = trackOf(clip);
			if (row < 0) continue;

			group.also(new MoveClip(row, clip, clip.at, clip.transpose + by));
		}

		session.does(group);
		invalidate();
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverTrack = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;

		framed();

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		final left = x + names();
		final top = y + ruler();

		paint.pushClip(left, top, width - names(), height - ruler());

		bars(paint, theme, metrics, left, top);
		clips(paint, theme, metrics);

		if (playhead >= 0) {
			final at = atTick(playhead);
			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(2), height - ruler(), theme.warn, 0.9);
			}
		}

		paint.popClip();

		rails(paint, theme, metrics, top);
		heading(paint, theme, metrics, left);
		reins(paint, theme, metrics, left, top);
	}

	var reining:Int = 0;

	function reinAt(px:Float, py:Float):Int {
		final thick = reinTall();

		if (py >= y + height - thick && px >= x + names()
			&& acrossReach() > width - names() + 0.5) return 1;

		if (px >= x + width - thick && py >= y + ruler()
			&& downReach() > height - ruler() + 0.5) return 2;

		return 0;
	}

	function reined(px:Float, py:Float):Void {
		if (reining == 1) {
			final wide = width - names();
			final held = span(wide, acrossReach());
			final room = wide - held;

			if (room <= 0) return;

			final want = (px - x - names() - held * 0.5) / room;
			scrollTo(want * (acrossReach() - wide));
			return;
		}

		final tall = height - ruler();
		final held = span(tall, downReach());
		final room = tall - held;

		if (room <= 0) return;

		final want = (py - y - ruler() - held * 0.5) / room;
		scrollDown(want * (downReach() - tall));
	}

	function span(across:Float, reach:Float):Float {
		final root = root();
		final least = root == null ? 24.0 : root.metrics.whole(24);
		final held = across * across / reach;

		return held < least ? least : held;
	}

	/**
		@return How tall the strip along the bottom is.
	**/
	public function reinTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	function acrossReach():Float {
		return session.song.ends() * perTick;
	}

	function downReach():Float {
		return rows() * trackTall();
	}

	function reins(paint:Paint, theme:Theme, metrics:Metrics, left:Float,
			top:Float):Void {
		final thick = reinTall();
		final wide = width - names();
		final tall = height - ruler();

		if (acrossReach() > wide + 0.5) {
			final held = span(wide, acrossReach());
			final room = wide - held;
			final most = acrossReach() - wide;
			final at = most <= 0 ? 0 : offsetX / most * room;

			paint.rect(left, y + height - thick, wide, thick, theme.sink, 0.7);
			paint.roundedRect(left + at, y + height - thick + metrics.whole(2), held,
				thick - metrics.whole(4), metrics.whole(2), theme.frame);
		}

		if (downReach() > tall + 0.5) {
			final held = span(tall, downReach());
			final room = tall - held;
			final most = downReach() - tall;
			final at = most <= 0 ? 0 : offsetY / most * room;

			paint.rect(x + width - thick, top, thick, tall, theme.sink, 0.7);
			paint.roundedRect(x + width - thick + metrics.whole(2), top + at,
				thick - metrics.whole(4), held, metrics.whole(2), theme.frame);
		}
	}

	function bars(paint:Paint, theme:Theme, metrics:Metrics, left:Float, top:Float):Void {
		final bar = session.song.tempo.ppqn * 4;
		final hair = metrics.whole(1);
		final tall = trackTall();
		final length = reach();

		final beat = session.song.tempo.ppqn;
		final step = session.snap < 1 ? beat : session.snap;

		var fine = step;
		while (fine * perTick < metrics.whole(7) && fine < bar) fine *= 2;

		var tick = Std.int(tickAt(left) / fine) * fine;
		if (tick < 0) tick = 0;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at > left) {
				final much = tick % (bar * 4) == 0 ? 0.8
					: (tick % bar == 0 ? 0.45 : (tick % beat == 0 ? 0.22 : 0.11));

				paint.rect(at, top, hair, height - ruler(), theme.frame, much);
			}

			tick += fine;
		}

		for (which in 0...rows()) {
			final row = atTrack(which);
			if (row + tall < top) continue;
			if (row > y + height) break;

			if (which >= session.song.tracks.length) {
				paint.rect(left, row, width - names(), tall, theme.sink, 0.35);
			} else if (which == hoverTrack) {
				paint.rect(left, row, width - names(), tall, theme.ink, 0.03);
			}

			paint.rect(left, row + tall - hair, width - names(), hair, theme.frame, 0.5);
		}
	}

	function clips(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		final tall = trackTall();
		final top = y + ruler();

		paint.reface(font);

		final hauls = haulRows != 0;

		for (which in 0...session.song.tracks.length) {
			final track = session.song.tracks[which];
			final seat = atTrack(which);

			if (!hauls) {
				if (seat + tall < top) continue;
				if (seat > y + height) break;
			}

			for (clip in track.clips) {
				final at = atTick(clip.at);
				final wide = clip.length * perTick;

				if (at + wide < x + names() || at > x + width) continue;

				final row = hauls && hauling(clip) ? atTrack(which + haulRows) : seat;

				if (row + tall < top || row > y + height) continue;

				painted++;

				if (clip.automates()) {
					curved(paint, theme, metrics, clip, at, row, wide, tall, track.muted);
					continue;
				}

				final pattern = session.song.patternAt(clip.pattern);
				final colour = pattern != null && pattern.colour >= 0
					? new Colour(pattern.colour)
					: (track.colour >= 0 ? new Colour(track.colour) : theme.dim);

				final deep = tall - 5;
				final quiet = track.muted;

				var strip = Math.ffloor(deep * 0.28);
				if (strip < metrics.whole(6)) strip = metrics.whole(6);
				if (strip > deep) strip = deep;

				paint.roundedRect(at, row + 2, wide, deep, metrics.radiusSmall, colour,
					quiet ? 0.10 : 0.20);

				paint.pushClip(at, row + 2, wide, strip);
				paint.roundedGradient(at, row + 2, wide, deep, metrics.radiusSmall,
					colour.lift(0.22), colour.sink(0.18), quiet ? 0.35 : 0.95);
				paint.popClip();

				paint.outline(at, row + 2, wide, deep, colour, metrics.whole(1),
					quiet ? 0.3 : 0.55, metrics.radiusSmall);

				if (picked.holds(clip)) {
					paint.outline(at, row + 2, wide, deep, theme.ink, metrics.whole(1),
						clip == chosen ? 1 : 0.65, metrics.radiusSmall);
				}

				corner(paint, theme, metrics, clip, at, row + 2, wide, colour.sink(0.74),
					quiet ? 0.35 : 0.9);

				final said = pattern == null ? "?" : pattern.name;
				final tail = clip.transpose == 0 ? ""
					: (clip.transpose > 0 ? "  +" + clip.transpose : "  " + clip.transpose);

				if (wide < metrics.whole(24)) continue;

				final inset = metrics.whole(1);
				final body = deep - strip - inset * 2;

				paint.pushClip(at, row + 2, wide - metrics.unit, deep);

				if (pattern != null && body >= metrics.whole(4)) {
					inked(paint, metrics, pattern, clip, quiet ? colour.sink(0.4) : colour, at,
						row + 2 + strip + inset, wide, body);
				}

				if (strip >= font.height * 0.9) {
					paint.text(said + tail, at + metrics.unit,
						row + 2 + (strip - font.height) * 0.5 + font.ascent,
						colour.sink(0.74));
				}

				paint.popClip();
			}
		}
	}

	static inline final CURVE = 256;

	final curve:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(CURVE * 2);

	function curved(paint:Paint, theme:Theme, metrics:Metrics, clip:Clip, at:Float,
			row:Float, wide:Float, tall:Float, quiet:Bool):Void {
		final line = clip.line;
		if (line == null) return;

		final part:mdd.song.Part = clip.part;
		final held = mdd.view.Parameter.found(part, line.target, line.slot);
		final colour = theme.part(clip.part);
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.roundedRect(at, row + 2, wide, tall - 5, metrics.radiusSmall, theme.raise1,
			quiet ? 0.4 : 0.9);

		paint.outline(at, row + 2, wide, tall - 5, colour, metrics.whole(1),
			clip == chosen ? 1 : 0.6, metrics.radiusSmall);

		if (picked.holds(clip)) {
			paint.outline(at, row + 2, wide, tall - 5, theme.ink, metrics.whole(1),
				clip == chosen ? 1 : 0.65, metrics.radiusSmall);
		}

		if (wide < metrics.whole(24) || held == null) return;

		final inset = metrics.whole(3);
		final top = row + 2 + inset;
		final room = tall - 5 - inset * 2;
		final span = held.high - held.low;

		if (room > metrics.whole(4) && span > 0 && line.points.length > 0) {
			paint.pushClip(at, row + 2, wide, tall - 5);

			var many = Std.int(wide / metrics.whole(3)) + 2;
			if (many > CURVE) many = CURVE;
			if (many < 2) many = 2;

			for (step in 0...many) {
				final tick = Std.int(clip.length * step / (many - 1));
				final value = line.valueAt(tick);
				final much = (value - held.low) / span;

				curve[step * 2] = at + wide * step / (many - 1);
				curve[step * 2 + 1] = top + room * (1 - (much < 0 ? 0 : (much > 1 ? 1 : much)));
			}

			paint.polyline(curve, many, metrics.whole(2), colour, quiet ? 0.4 : 0.95);
			paint.popClip();
		}

		paint.pushClip(at, row + 2, wide - metrics.unit, tall - 5);

		paint.text(part.name() + "  " + held.titled(line.slot), at + metrics.unit,
			row + 2 + metrics.unit + font.ascent, colour, quiet ? 0.4 : 0.85);

		paint.popClip();
	}

	static inline final MOST_NOTES = 2048;

	function inked(paint:Paint, metrics:Metrics, pattern:mdd.song.Pattern, clip:Clip,
			ink:Colour, left:Float, top:Float, wide:Float, tall:Float):Void {
		var low = 128;
		var high = -1;
		var counted = 0;

		for (index in 0...Part.COUNT) {
			for (note in pattern.lanes[index].notes) {
				if (note.at < clip.offset || note.at >= clip.offset + clip.length) continue;

				if (note.pitch < low) low = note.pitch;
				if (note.pitch > high) high = note.pitch;
				counted++;
			}
		}

		if (counted == 0 || high < low) return;

		if (high - low < 6) {
			final middle = (high + low) >> 1;
			low = middle - 3;
			high = middle + 3;
		}

		final span = high - low + 1;
		final hair = tall / span;
		final thick = hair < 1 ? 1 : (hair > metrics.whole(3) ? metrics.whole(3) : hair);
		final least = metrics.whole(1);

		var drawn = 0;

		for (index in 0...Part.COUNT) {
			for (note in pattern.lanes[index].notes) {
				if (note.at < clip.offset || note.at >= clip.offset + clip.length) continue;
				if (drawn >= MOST_NOTES) return;

				final seen = note.at - clip.offset;
				var length = note.length;
				if (seen + length > clip.length) length = clip.length - seen;

				final from = left + seen * perTick;
				var run = length * perTick;
				if (run < least) run = least;

				if (from > left + wide) continue;

				final seat = top + (high - note.pitch) * hair;

				paint.rect(from, seat, run, thick, ink, 0.85);
				drawn++;
			}
		}
	}

	function rails(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final tree = root();
		final wide = names();
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final tall = trackTall();
		final hair = metrics.whole(1);

		paint.rect(x, top, wide, height - ruler(), theme.panel);
		paint.pushClip(x, top, wide, height - ruler());

		for (which in 0...rows()) {
			final row = atTrack(which);
			if (row + tall < top) continue;
			if (row > y + height) break;

			final held = which < session.song.tracks.length
				? session.song.tracks[which] : null;

			if (which == chosenTrack) {
				paint.rect(x, row, wide, tall - hair, theme.accent, Theme.SELECT);
			} else if (which == hoverTrack) {
				paint.rect(x, row, wide, tall - hair, theme.accent, Theme.HOVER);
			}

			if (which == hoverEdge || which == sizingRows) {
				paint.rect(x, row + tall - hair * 2, wide, hair * 3, theme.accent, 0.9);
			} else {
				paint.rect(x, row + tall - hair, wide, hair, theme.frame, 0.5);
			}

			if (railing >= 0 && railTo != railing && which == railTo) {
				paint.rect(x, railTo > railing ? row + tall - hair * 3 : row, wide, hair * 3,
					theme.accent, 0.9);
			}

			if (held == null) {
				paint.reface(small);
				paint.textCentred("+", x + wide * 0.5,
					row + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.5);
				continue;
			}

			paint.rect(x, row + metrics.unit, metrics.whole(3), tall - metrics.unit * 2 - hair,
				held.colour >= 0 ? new Colour(held.colour) : theme.frame,
				held.muted ? 0.25 : 0.9);

			final box = metrics.whole(18);
			final at = x + wide - metrics.whole(26);

			if (held.muted) {
				paint.roundedGradient(at, row + (tall - box) * 0.5, box, box,
					metrics.radiusSmall, theme.accent.lift(0.20), theme.accent.sink(0.16),
					0.8);
			} else {
				paint.roundedRect(at, row + (tall - box) * 0.5, box, box,
					metrics.radiusSmall, theme.raise1);
			}

			var pen = x + metrics.inset + metrics.gap;

			if (held.icon >= 0 && tree != null) {
				final box = metrics.whole(14);

				paint.icon(tree.icons, held.icon, pen, row + (tall - box) * 0.5, box,
					held.muted ? theme.dim : theme.ink, held.muted ? 0.4 : 0.9);

				pen += box + metrics.gap;
			}

			paint.reface(font);
			paint.text(held.name, pen, row + (tall - font.height) * 0.5 + font.ascent,
				held.muted ? theme.dim : theme.ink);

			paint.reface(small);
			paint.textCentred("M", at + box * 0.5,
				row + (tall - small.height) * 0.5 + small.ascent,
				held.muted ? theme.ink : theme.dim);
		}

		paint.popClip();
		paint.rect(x + wide - hair, top, hair, height - ruler(), theme.frame);
	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics, left:Float):Void {
		final tall = ruler();

		paint.rect(x, y, width, tall, theme.bar);
		paint.pushClip(left, y, width - names(), tall);

		final font = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(font);

		final bar = session.song.tempo.ppqn * 4;
		final length = session.song.ends() + bar * 4;

		var tick = Std.int(tickAt(left) / (bar * 4)) * bar * 4;
		if (tick < 0) tick = 0;

		var written = left - metrics.gap;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left && at >= written) {
				final said = Std.string(Std.int(tick / bar) + 1);

				paint.text(said, at + metrics.unit,
					y + (tall - font.height) * 0.5 + font.ascent, theme.dim);

				written = at + metrics.unit + paint.measure(said) + metrics.gap;
			}

			tick += bar * 4;
		}

		paint.popClip();
		paint.rect(x, y + tall - metrics.whole(1), width, metrics.whole(1), theme.frame, 0.7);
	}
}
