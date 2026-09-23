package mdd.view.editor;

import haxe.ds.Vector;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.check.Budget;
import mdd.song.edit.AddNote;
import mdd.song.Lane;
import mdd.song.Note;
import mdd.song.Pattern;
import mdd.song.Part;
import mdd.song.edit.RemoveNote;
import mdd.ui.Panel;
import mdd.ui.control.Choice;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.control.Menu;
import mdd.ui.Metrics;
import mdd.ui.Mod;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;
import mdd.view.Parameter;
import mdd.view.Picked;

@:unreflective

/**
	The piano roll: notes against pitch and time, with the parameter lanes underneath
	and the velocities between them.

	A note the chip cannot sound is hatched as soon as it is written, from the same
	budget the warnings panel reads, so the limit is seen while the music is being
	written rather than found at export.
**/
final class PianoRoll extends Widget {


	static inline final LOWEST = 12;
	static inline final HIGHEST = 108;

	static final BLACK:Array<Bool> = [false, true, false, true, false, false, true, false, true,
		false, true, false];

	/**
		How solid a key with no drum on it is drawn, which is what tells a reader it
		takes a note and makes no sound.
	**/
	static inline final SILENT = 0.28;

	/**
		How few pixels a bar draws at before the zoom stops going out, and how many
		before it stops coming in. The zoom is bounded in pixels rather than in ticks so
		it reaches the same place whatever a piece counts a beat in.
	**/
	static inline final BAR_LEAST = 4.0;

	static inline final BAR_MOST = 2048.0;

	/**
		How many bars of room the view scrolls into past the end of the pattern, so the
		last bar is not written against a wall.
	**/
	static inline final SPARE = 4;

	/**
		How short a row draws, as a share of the height of the name written on it, and
		how tall.
	**/
	static inline final ROW_LEAST = 1.0;

	static inline final ROW_MOST = 4.0;

	/**
		How far a key leans a note, which is finer than the menu's step because a key is
		pressed again where a menu entry is chosen once.
	**/
	static inline final LEAN = 8;

	/**
		What the grid can divide a bar into, coarsening down the list, with no snap at
		all last. The transport bar offers the same divisions, so the two controls
		never disagree about what is on offer.
	**/
	static final SNAPS:Array<Int> = [64, 32, 16, 8, 4, 2, 1, 0];

	static final SNAP_NAMES:Array<Locale> = [Locale.ROLL_SNAP_SIXTY_FOURTH,
		Locale.ROLL_SNAP_THIRTY_SECOND, Locale.ROLL_SNAP_SIXTEENTH,
		Locale.ROLL_SNAP_EIGHTH, Locale.ROLL_SNAP_BEAT, Locale.ROLL_SNAP_HALF,
		Locale.ROLL_SNAP_BAR, Locale.ROLL_SNAP_NONE];

	/**
		The session to read.
	**/
	public final session:Session;

	/**
		How many pixels a tick is, which is the zoom.
	**/
	public var perTick:Float = 0.25;

	/**
		How tall one semitone row is.
	**/
	public var rowTall:Float = 12;

	/**
		How far the view is scrolled, across.
	**/
	public var offsetX:Float = 0;

	/**
		How far it is scrolled, down.
	**/
	public var offsetY:Float = 0;

	/**
		Where the playhead is in the song, or -1 for nowhere.
	**/
	public var playhead:Int = -1;

	/**
		Where the pattern starts in the song, in ticks, which the ruler, the playhead and scrubbing are
		measured from.
	**/
	public var origin:Int = 0;

	/**
		What says which notes the hardware will not sound, so they can be hatched.
	**/
	public var budget:Null<Budget> = null;

	/**
		How many notes the last frame drew, which is what proves only the visible ones cost
		anything.
	**/
	public var painted(default, null):Int = 0;

	/**
		Which note is chosen.
	**/
	public var chosen(default, null):Null<Note> = null;

	/**
		Which notes are selected.
	**/
	public final picked:Picked<Note> = new Picked<Note>();

	/**
		Called to sound a note, which goes through the transport rather than a chip.
	**/
	public var onAudition:Null<(Part, Int) -> Void> = null;

	/**
		Whether the parameter lanes are shown.
	**/
	public var showLanes:Bool = true;

	/**
		Which lane is shown under the velocities.
	**/
	public var showing:Int = 0;
	var stalking:Null<Note> = null;
	var litNote:Int = -1;
	var litOn:Bool = false;

	/**
		The parameter lanes.
	**/
	public final stack:Lanes;

	/**
		Called to open a lane for a parameter.
	**/
	public var onAutomate:Null<(Int, Int) -> Void> = null;

	var banding:Bool = false;
	var bandFromX:Float = 0;
	var bandFromY:Float = 0;
	var bandToX:Float = 0;
	var bandToY:Float = 0;

	final leaning:Array<Note> = [];
	final wereLoud:Array<Int> = [];
	var leadLoud:Int = 0;

	final moving:Array<Note> = [];
	final wereAt:Array<Int> = [];
	final werePitch:Array<Int> = [];
	final wereSeat:Array<Int> = [];
	final wereHeld:Array<Int> = [];
	final wereLong:Array<Int> = [];

	var dragging:Null<Note> = null;
	var grabTick:Int = 0;
	var grabPitch:Int = 0;
	var grabWasAt:Int = 0;
	var grabWasSeat:Int = 0;
	var leastAt:Int = 0;
	var leastSeat:Int = 0;
	var mostSeat:Int = 0;
	var grabFresh:Bool = false;
	var sizing:Bool = false;
	var sizingStart:Bool = false;
	var drawn:Int = 0;
	var gridded:Int = -1;
	var panning:Bool = false;
	var rubbing:Bool = false;
	var cloning:Null<Note> = null;
	var cloneX:Float = 0;
	var cloneY:Float = 0;
	var leadLean:Int = 0;

	final rubbed:Array<Note> = [];
	var scrubbing:Bool = false;
	var menu:Null<Menu> = null;
	var panX:Float = 0;
	var panY:Float = 0;

	/**
		Which instrument each key sounds, by pitch, or -1 where the kit has nothing
		rooted there. A key with nothing on it is still drawn and still takes a note:
		it just makes no sound, which is what keeps an imported drum track in the
		shape the file wrote it in.
	**/
	final kit:Vector<Int> = new Vector<Int>(HIGHEST + 1);
	var settledOn:Int = -1;
	var settledPart:Int = -1;

	/**
		Builds the roll.

		@param session The session to read.
	**/
	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		stack = new Lanes(session);
		stack.onOffer = function(from:Lanes, row:Int, px:Float, py:Float):Void
			offered(px, py, row);
		stack.onShape = function(from:Lanes, row:Int, point:mdd.song.Point, px:Float,
			py:Float):Void shaped(point, px, py);

		add(stack);
	}

	override function layout():Void {
		stack.adding = false;

		if (showing > 0 && stack.rows() == 0) {
			final held = Parameter.of(session.part);
			if (showing - 1 < held.length) {
				stack.show(held[showing - 1].target, held[showing - 1].slot);
			}
		}

		final tall = showing == 0 ? 0.0 : stack.wants();

		stack.perTick = perTick;
		stack.offsetX = offsetX;
		stack.left = gutter();
		stack.playhead = playhead < 0 ? -1 : playhead - origin;
		stack.visible = showLanes && showing > 0 && tall > 0;

		stack.arrange(x, y + height - tall, width, tall);
	}

	function offered(px:Float, py:Float, row:Int):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		final velocity = menu.offer(new Choice(translate(Locale.LANE_VELOCITY)));

		if (showing == 0) velocity.enabled = false;
		else fires(velocity, function():Void shows(0));

		menu.divide();

		final held = Parameter.of(session.part);

		for (index in 0...held.length) {
			final one = held[index];
			final which = index + 1;

			final many = stack.carries(one.target, one.slot);
			final choice = menu.offer(new Choice(one.titled(one.slot),
				many == 0 ? "" : "" + many));

			choice.reason = translate(one.about);

			if (which == showing) choice.enabled = false;
			else fires(choice, function():Void {
				if (session.automating == Session.CLIPS && onAutomate != null) {
					onAutomate(one.target, one.slot);
					return;
				}

				shows(which);
			});
		}

		if (showing > 0) {
			menu.divide();

			final lift = menu.offer(new Choice(translate(Locale.LANE_LIFT)));

			lift.enabled = stack.rows() > 0
				&& stack.carries(stack.targetOf(0), stack.slotOf(0)) > 0;

			if (!lift.enabled) lift.reason = translate(Locale.LANE_EMPTY);
			fires(lift, function():Void lifted(0));
		}

		root.pop(menu, px, py, this);
	}

	function lifted(row:Int):Void {
		final target = stack.targetOf(row);
		final slot = stack.slotOf(row);

		session.does(new mdd.song.edit.LiftAutomation(session.pattern, session.part,
			target, slot));

		stack.hide(row);

		final held = Parameter.found(session.part, target, slot);
		session.say(translate(Locale.LANE_LIFTED) + "  "
			+ (held == null ? "" : held.titled(slot)));
	}

	function shaped(point:mdd.song.Point, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		for (shape in 0...mdd.song.Automation.SHAPES) {
			final one = menu.offer(new Choice(translate(mdd.view.Shapes.NAMES[shape])));

			if (shape == point.shape) one.enabled = false;
			else fires(one, function():Void {
				session.does(new mdd.song.edit.ShapePoint(point, shape, point.tension,
					point.steps));
				stack.invalidate();
			});
		}

		if (mdd.song.Automation.stepped(point.shape)) {
			menu.divide();

			for (many in [2, 3, 4, 6, 8, 12, 16]) {
				final one = menu.offer(new Choice("" + many));

				if (many == point.repeats()) one.enabled = false;
				else fires(one, function():Void {
					session.does(new mdd.song.edit.ShapePoint(point, point.shape,
						point.tension, many));
					stack.invalidate();
				});
			}
		}

		root.pop(menu, px, py, this);
	}

	/**
		@return Whether the chosen part plays a kit, in which case a key sounds whatever
			drum is rooted at it rather than whatever the rack holds. The rows are the
			same keys either way.
	**/
	public inline function kitting():Bool {
		return session.part.sampled() && session.song.drums;
	}

	/**
		Reads the kit again, which changing the bank needs.
	**/
	public function kitted():Void {
		for (pitch in 0...kit.length) kit[pitch] = -1;

		if (!kitting()) return;

		final song = session.song;
		final at = song.bankOf(song.rack[session.part.index()]);
		final bank = at < 0 ? null : song.banks[at];

		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			if (held.sample < 0) continue;

			final sample = song.sampleAt(held.sample);
			if (sample == null) continue;
			if (bank != null && !bank.holds(index)) continue;
			if (sample.root < 0 || sample.root >= kit.length) continue;

			kit[sample.root] = index;
		}
	}

	/**
		@return The lowest row shown.
	**/
	public function lowest():Int {
		return LOWEST;
	}

	/**
		@return The highest.
	**/
	public function highest():Int {
		return HIGHEST;
	}

	/**
		@param pitch A key.
		@return Which instrument is rooted there, or -1 where the part is not a kit or
			the kit has nothing on that key.
	**/
	public function drumAt(pitch:Int):Int {
		if (!kitting() || pitch < 0 || pitch >= kit.length) return -1;
		return kit[pitch];
	}

	/**
		Moves a note to a key, and with it to whichever drum is rooted there.

		@param note The note.
		@param seat The key it lands on.
	**/
	/**
		Takes one note away, and stops holding onto it.

		The rubber takes a note on a press, and so does the right button while the
		pencil is out, which is how a reader who is drawing takes one back without
		reaching for another tool.

		@param note The note to take away.
	**/
	/**
		Takes a note off the lane while the rubber is sweeping, with nothing written to the
		undo stack yet: a sweep over a dozen notes is one step there rather than twelve.

		@param note The note the pointer went over.
	**/
	function rubs(note:Note):Void {
		if (rubbed.indexOf(note) >= 0) return;

		final pattern = session.current();
		if (pattern == null) return;

		picked.drops(note);
		if (chosen == note) chosen = picked.lead();

		session.holds();
		pattern.lane(session.part).remove(note);
		session.frees();

		rubbed.push(note);
		invalidate();
	}

	/**
		Puts the swept notes back and takes them away again as one step, which is what
		leaves the undo stack holding the sweep rather than its frames.
	**/
	function rubDropped():Void {
		rubbing = false;
		if (rubbed.length == 0) return;

		final pattern = session.current();

		if (pattern != null) {
			final lane = pattern.lane(session.part);

			session.holds();
			for (note in rubbed) lane.add(note);
			session.frees();
		}

		if (rubbed.length == 1) {
			session.does(new RemoveNote(session.pattern, session.part, rubbed[0]));
		} else {
			final group = new mdd.song.edit.Together("remove " + counted(rubbed.length));

			for (note in rubbed) {
				group.also(new RemoveNote(session.pattern, session.part, note));
			}

			session.does(group);
		}

		rubbed.resize(0);
		session.changed();
		invalidate();
	}

	/**
		Copies what is being dragged and hands the copies to the drag, so the notes left
		behind are the originals.

		The whole selection is copied where the note dragged is part of one, and only that
		note where it is not, which is the rule the plain drag already follows.

		@param lead The note the pointer went down on.
		@return The copy of that note, or null where nothing could be copied.
	**/
	function clones(lead:Note):Null<Note> {
		final pattern = session.current();
		if (pattern == null) return null;

		final from = picked.count > 1 && picked.holds(lead) ? held() : [lead];
		final made:Array<Note> = [];
		final group = new mdd.song.edit.Together("add " + counted(from.length));

		var head:Null<Note> = null;

		for (note in from) {
			final copy = note.copy();

			if (note == lead) head = copy;

			made.push(copy);
			group.also(new AddNote(session.pattern, session.part, copy));
		}

		if (head == null) return null;

		session.does(group);

		picked.clear();
		for (note in made) picked.adds(note);

		chosen = head;
		return head;
	}

	function seated(note:Note, seat:Int):Void {
		note.pitch = seat;
		if (kitting()) note.instrument = drumAt(seat);
	}

	/**
		@param seat A key.
		@return What to write beside it: the drum rooted there where one is, and the
			name of the note otherwise.
	**/
	function seatName(seat:Int):String {
		final which = drumAt(seat);
		if (which < 0) return named(seat);

		final held = session.song.instrumentAt(which);
		return held == null ? named(seat) : held.name;
	}

	function records(pitch:Int):Void {
		if (!session.arming || !session.transport.playing) return;

		final pattern = session.current();
		if (pattern == null) return;

		final at = session.snapped(session.transport.tick());
		final length = session.snap < 1 ? session.song.tempo.ppqn : session.snap;

		final note = new mdd.song.Note(at, length, pitch);
		seated(note, pitch);

		session.does(new mdd.song.edit.AddNote(session.pattern, session.part, note));
	}

	/**
		@return How wide the keyboard down the side is.
	**/
	public function gutter():Float {
		final root = root();
		return root == null ? 56 : root.metrics.whole(56);
	}

	/**
		@return How tall the ruler across the top is.
	**/
	public function ruler():Float {
		final root = root();
		return root == null ? 24 : root.metrics.ruler;
	}

	/**
		@return How tall the velocity strip is.
	**/
	public function velocityTall():Float {
		if (!showLanes || showing != 0) return 0;

		final root = root();
		return root == null ? 108 : root.metrics.whole(108);
	}

	/**
		@return How tall the parameter lanes are.
	**/
	public function lanes():Float {
		if (!showLanes) return 0;
		return showing == 0 ? velocityTall() : stack.wants();
	}

	/**
		@return How many lanes the chosen part has to offer.
	**/
	public function choices():Int {
		return Parameter.of(session.part).length + 1;
	}

	/**
		Steps to the next or previous lane.

		@param by One forwards, minus one backwards.
	**/
	public function cycles(by:Int):Void {
		final many = choices();
		var want = (showing + by) % many;

		if (want < 0) want += many;
		shows(want);
	}

	/**
		Shows one lane under the velocities.

		@param want Which lane.
	**/
	public function shows(want:Int):Void {
		if (want == showing || want < 0 || want >= choices()) return;

		showing = want;
		stack.targets.resize(0);

		if (want > 0) {
			final one = Parameter.of(session.part)[want - 1];
			stack.show(one.target, one.slot);
		}

		final said = want == 0 ? translate(Locale.LANE_VELOCITY)
			: Parameter.of(session.part)[want - 1].titled(0);

		session.say(said);
		relayout();
	}

	function onLaneHead(py:Float):Bool {
		if (!showLanes || lanes() <= 0) return false;

		final top = y + height - lanes();
		return py >= top && py < top + stripHead();
	}

	/**
		@return How wide one grid step draws.
	**/
	public inline function grid():Float {
		return height - ruler() - lanes();
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
		Where something placed at a point belongs, which is the step that was
		pointed at rather than whichever line is nearest.

		@param tick A position in the piece, in ticks.
		@param free Whether to ignore the snap, which holding alt does.
		@return Where that step begins, or the tick left alone.
	**/
	public inline function placed(tick:Int, free:Bool):Int {
		return free ? tick : session.begins(tick);
	}

	/**
		@param px A point, across.
		@return Which tick is there.
	**/
	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - gutter() + offsetX) / perTick);
	}

	/**
		@param tick A position in the piece, in ticks.
		@return Where it draws, across.
	**/
	public inline function atTick(tick:Int):Float {
		return x + gutter() + tick * perTick - offsetX;
	}

	/**
		@param py A point, down.
		@return Which pitch is there.
	**/
	public inline function pitchAt(py:Float):Int {
		return highest() - Std.int((py - y - ruler() + offsetY) / rowTall);
	}

	/**
		@param pitch A MIDI note number.
		@return Where it draws, down.
	**/
	public inline function atPitch(pitch:Int):Float {
		return y + ruler() + (highest() - pitch) * rowTall - offsetY;
	}

	/**
		@return The furthest the view scrolls to, which is the pattern with a few bars
			of room after it so the last bar is not written against a wall.
	**/
	public function reach():Int {
		final pattern = session.current();
		final bar = session.song.tempo.ppqn * 4;
		final length = pattern == null ? 0 : pattern.length;

		if (bar < 1) return length;
		return (length < bar ? bar : length) + bar * SPARE;
	}

	/**
		@return How wide the pattern draws, with the room after it.
	**/
	public function contentWidth():Float {
		return reach() * perTick;
	}

	/**
		@return How tall every row draws.
	**/
	public function contentHeight():Float {
		return (highest() - lowest() + 1) * rowTall;
	}

	/**
		@param px A point, across.
		@param py A point, down.
		@return The note there, or null.
	**/
	public function noteAt(px:Float, py:Float):Null<Note> {
		final pattern = session.current();
		if (pattern == null) return null;

		final tick = tickAt(px);
		final pitch = pitchAt(py);
		final lane = pattern.lane(session.part);

		var found:Null<Note> = null;

		for (note in lane.notes) {
			if (note.pitch != pitch) continue;
			if (tick < note.at || tick >= note.ends()) continue;
			found = note;
		}

		return found;
	}

	function centred():Void {
		final part = session.part.index();
		if (settledOn == session.pattern && settledPart == part) return;

		settledOn = session.pattern;
		settledPart = part;

		picked.clear();
		chosen = null;

		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		if (lane.notes.length == 0) return;

		final first = lane.notes[0];
		var low = first.pitch;
		var high = low;

		for (note in lane.notes) {
			if (note.at > first.at + session.song.tempo.ppqn * 16) break;

			final seat = note.pitch;
			if (seat < low) low = seat;
			if (seat > high) high = seat;
		}

		reveal(first.at, Math.round((low + high) * 0.5));
	}

	function grabs(lead:Note):Void {
		moving.resize(0);
		wereAt.resize(0);
		werePitch.resize(0);
		wereSeat.resize(0);
		wereHeld.resize(0);
		wereLong.resize(0);

		if (picked.count > 1 && picked.holds(lead)) {
			for (index in 0...picked.count) moving.push(picked.at(index));
		} else {
			moving.push(lead);
		}

		leastAt = moving[0].at;
		leastSeat = moving[0].pitch;
		mostSeat = leastSeat;

		for (note in moving) {
			final seat = note.pitch;

			wereAt.push(note.at);
			werePitch.push(note.pitch);
			wereSeat.push(seat);
			wereHeld.push(note.instrument);
			wereLong.push(note.length);

			if (note.at < leastAt) leastAt = note.at;
			if (seat < leastSeat) leastSeat = seat;
			if (seat > mostSeat) mostSeat = seat;
		}
	}

	function hauled(at:Int, seat:Int):Void {
		var byTick = at - grabWasAt;
		var bySeat = seat - grabWasSeat;

		if (leastAt + byTick < 0) byTick = -leastAt;
		if (leastSeat + bySeat < lowest()) bySeat = lowest() - leastSeat;
		if (mostSeat + bySeat > highest()) bySeat = highest() - mostSeat;

		for (index in 0...moving.length) {
			final note = moving[index];

			note.at = wereAt[index] + byTick;
			seated(note, wereSeat[index] + bySeat);
		}
	}

	function settled():Void {
		final held = dragging;

		dragging = null;

		if (held == null) {
			sizing = false;
			sizingStart = false;
			return;
		}

		session.holds();
		session.current().lane(session.part).sort();
		session.frees();

		if (grabFresh) {
			sizing = false;
			sizingStart = false;
			grabFresh = false;
			session.changed();
			return;
		}

		if (sizing) {
			if (sizingStart) startedDone();
			else sized();
		} else hauledDone();

		sizing = false;
		sizingStart = false;
		session.changed();
	}

	/**
		Drags where a note begins, leaving where it ends alone, so the note grows
		and shrinks from its left. It never passes its own end, and never reaches
		back past the start of the pattern.

		Only the note under the pointer moves. A selection resizes from the end
		together, and doing the same from the start would have to clamp each note
		against its own end, which is a different thing and is not done here.

		@param note The note being dragged.
		@param to Where its start is being taken, in ticks.
		@param free Whether to ignore the snap, which holding alt does.
	**/
	public function restarted(note:Note, to:Int, free:Bool = false):Void {
		final least = free || session.snap < 1 ? 1 : session.snap;
		final ends = note.at + note.length;

		var want = freely(to, free);

		if (want < 0) want = 0;
		if (want > ends - least) want = ends - least;
		if (want == note.at) return;

		session.holds();
		note.at = want;
		note.length = ends - want;
		session.frees();

		drawn = note.length;
	}

	/**
		Puts a start drag on the undo stack as one step. Both where the note begins
		and how long it is have moved, so it takes two commands held together.
	**/
	function startedDone():Void {
		if (moving.length == 0) return;

		final note = moving[0];
		final wasAt = wereAt[0];
		final wasLong = wereLong[0];

		if (note.at == wasAt && note.length == wasLong) return;

		final wantAt = note.at;
		final wantLong = note.length;

		session.holds();
		note.at = wasAt;
		note.length = wasLong;
		session.frees();

		final group = new mdd.song.edit.Together("resize a note");

		group.also(new mdd.song.edit.MoveNote(session.pattern, session.part, note,
			wantAt, note.pitch, note.instrument));
		group.also(new mdd.song.edit.SizeNote(session.pattern, session.part, note,
			wantLong));

		session.does(group);
	}

	function sized():Void {
		var many = 0;
		for (index in 0...moving.length) if (moving[index].length != wereLong[index]) many++;
		if (many == 0) return;

		final wants:Array<Int> = [];
		for (note in moving) wants.push(note.length);

		for (index in 0...moving.length) moving[index].length = wereLong[index];

		if (moving.length == 1) {
			session.does(new mdd.song.edit.SizeNote(session.pattern, session.part,
				moving[0], wants[0]));
			return;
		}

		final group = new mdd.song.edit.Together("resize " + counted(moving.length));

		for (index in 0...moving.length) {
			group.also(new mdd.song.edit.SizeNote(session.pattern, session.part,
				moving[index], wants[index]));
		}

		session.does(group);
	}

	function hauledDone():Void {
		var many = 0;

		for (index in 0...moving.length) {
			final note = moving[index];
			if (note.at != wereAt[index] || note.pitch != werePitch[index]
				|| note.instrument != wereHeld[index]) many++;
		}

		if (many == 0) return;

		final wantAt:Array<Int> = [];
		final wantPitch:Array<Int> = [];
		final wantHeld:Array<Int> = [];

		for (note in moving) {
			wantAt.push(note.at);
			wantPitch.push(note.pitch);
			wantHeld.push(note.instrument);
		}

		for (index in 0...moving.length) {
			final note = moving[index];

			note.at = wereAt[index];
			note.pitch = werePitch[index];
			note.instrument = wereHeld[index];
		}

		if (moving.length == 1) {
			session.does(new mdd.song.edit.MoveNote(session.pattern, session.part,
				moving[0], wantAt[0], wantPitch[0], wantHeld[0]));
			return;
		}

		final group = new mdd.song.edit.Together("move " + counted(moving.length));

		for (index in 0...moving.length) {
			group.also(new mdd.song.edit.MoveNote(session.pattern, session.part,
				moving[index], wantAt[index], wantPitch[index], wantHeld[index]));
		}

		session.does(group);
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

		final pattern = session.current();
		final left = bandFromX < bandToX ? bandFromX : bandToX;
		final right = bandFromX < bandToX ? bandToX : bandFromX;
		final top = bandFromY < bandToY ? bandFromY : bandToY;
		final floor = bandFromY < bandToY ? bandToY : bandFromY;

		if (pattern == null || (right - left < 2 && floor - top < 2)) {
			invalidate();
			return;
		}

		final from = tickAt(left);
		final to = tickAt(right);
		final high = pitchAt(top);
		final low = pitchAt(floor);

		for (note in pattern.lane(session.part).notes) {
			final seat = note.pitch;

			if (seat < low || seat > high) continue;
			if (note.ends() <= from || note.at >= to) continue;

			picked.adds(note);
		}

		chosen = picked.lead();

		if (picked.count > 0) session.says(Locale.SAID_NOTES_SELECTED, "" + picked.count);
		session.changed();

		invalidate();
	}

	/**
		Moves the playhead to a point on the ruler.

		@param px A point, across.
	**/
	public function scrubbed(px:Float):Void {
		final tick = session.snapped(tickAt(px));
		final want = origin + (tick < 0 ? 0 : tick);

		session.transport.seek(session.song.tempo.samplesAt(want));
		playhead = want;

		invalidate();
	}

	/**
		Scrolls a position into view, which clicking a warning does.

		@param tick A position in the piece, in ticks.
		@param pitch A MIDI note number.
	**/
	public function reveal(tick:Int, pitch:Int):Void {
		final wide = width - gutter();
		final tall = grid();

		scrollTo(tick * perTick - wide * 0.3, (highest() - pitch) * rowTall - tall * 0.5);
	}

	/**
		Chooses a note and shows it in the inspector.

		@param note The note, or null for none.
	**/
	public function choose(note:Null<Note>):Void {
		chosen = note;

		if (note == null) picked.clear();
		else picked.only(note);

		invalidate();
	}

	/**
		Selects every note in the pattern.

		@return Whether anything was selected.
	**/
	public function picksAll():Bool {
		final pattern = session.current();
		if (pattern == null) return false;

		final lane = pattern.lane(session.part);
		if (lane.notes.length == 0) return false;

		picked.clear();
		for (note in lane.notes) picked.adds(note);

		chosen = picked.lead();
		session.says(Locale.SAID_NOTES_SELECTED, "" + picked.count);
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
				if (session.copiedNotes.length == 0) return false;
				pasted(session.snapped(playhead - origin < 0 ? 0 : playhead - origin));
				return true;

			case mdd.ui.Edit.DOUBLE:
				return doubled();

			case _:
		}

		return false;
	}

	/**
		@param many How many there are.
		@return What to call them in an undo entry. Those name a step for the gate to
			recognise rather than for a reader, and nothing puts one on screen, so this
			stays in one language.
	**/
	static function counted(many:Int):String {
		return many + (many == 1 ? " note" : " notes");
	}

	/**
		@return The selected notes, or the chosen one where nothing is selected.
	**/
	public function held():Array<Note> {
		final pattern = session.current();
		final out:Array<Note> = [];

		if (pattern == null) return out;

		for (note in pattern.lane(session.part).notes) {
			if (picked.holds(note)) out.push(note);
		}

		return out;
	}

	/**
		@return What a tool acts on, which is the selection where there is one and the
			whole lane where there is not. The array is the tool's own, so a command may
			take a note out of the lane while it is being walked.
	**/
	function reaching():Array<Note> {
		final some = held();
		if (some.length > 0) return some;

		final pattern = session.current();
		return pattern == null ? [] : pattern.lane(session.part).notes.copy();
	}

	/**
		Copies what a tool reaches and lays the copy straight after it.

		The copy goes a whole span later, the span running from the start of the earliest
		note to the end of the latest and then rounded up to something musical: to a beat,
		or a doubling of one up to a bar, or a whole number of bars past that. A span shorter
		than a beat rounds to the grid instead.

		The rounding is what makes the key worth pressing. A bar of drums whose last hit ends
		before the bar line has a span shorter than a bar, so a copy laid a raw span later
		arrives early and every repeat drifts further forward.

		What lands is what is selected afterwards, so pressing again lays a third.
	**/
	public function doubled():Bool {
		final pattern = session.current();
		if (pattern == null) return false;

		final reach = reaching();
		if (reach.length == 0) return false;

		var least = reach[0].at;
		var until = reach[0].ends();

		for (note in reach) {
			if (note.at < least) least = note.at;
			if (note.ends() > until) until = note.ends();
		}

		final beat = session.song.tempo.ppqn;
		final bar = beat * 4;
		final raw = until - least;

		var apart = raw;

		if (beat < 1) apart = raw;
		else if (raw < beat) {
			final step = session.snap;
			if (step > 0) apart = Math.ceil(raw / step) * step;
		} else if (raw <= bar) {
			apart = beat;
			while (apart < raw) apart *= 2;
		} else {
			apart = Math.ceil(raw / bar) * bar;
		}

		if (apart < 1) return false;

		final made:Array<Note> = [];
		final group = new mdd.song.edit.Together("add " + counted(reach.length));

		for (note in reach) {
			final copy = note.copy();
			copy.at += apart;

			made.push(copy);
			group.also(new AddNote(session.pattern, session.part, copy));
		}

		session.does(group);

		picked.clear();
		for (note in made) picked.adds(note);

		chosen = picked.lead();

		session.says(Locale.SAID_NOTES_DOUBLED, "" + made.length);
		session.changed();

		invalidate();
		return true;
	}

	/**
		Pulls the notes onto the grid.

		A driver writes a key on where its own timer put it, so almost nothing that
		arrives from a register log or a MIDI file sits on a line. The selection is what
		moves where there is one, and the whole lane where there is not.
	**/
	public function quantised():Bool {
		final step = session.snap;

		if (step < 1) {
			session.says(Locale.SAID_SNAP_OFF);
			session.changed();
			return false;
		}

		final reach = reaching();
		final group = new mdd.song.edit.Together("quantise " + counted(reach.length));
		var moved = 0;

		for (note in reach) {
			final want = Math.round(note.at / step) * step;
			if (want == note.at) continue;

			group.also(new mdd.song.edit.MoveNote(session.pattern, session.part, note, want,
				note.pitch));

			moved++;
		}

		if (moved == 0) return false;

		session.does(group);
		session.says(Locale.SAID_NOTES_QUANTISED, "" + moved);
		session.changed();

		invalidate();
		return true;
	}

	/**
		Stretches every note to where the next one starts, which is what a legato line is.

		The notes are taken in time order whatever key they sit on, so a chord stretches to
		the chord after it rather than each note to itself. The last one keeps its length,
		because there is nothing to stretch it to.
	**/
	public function stretched():Bool {
		final reach = reaching();
		if (reach.length < 2) return false;

		reach.sort(function(one:Note, two:Note):Int return one.at - two.at);

		final group = new mdd.song.edit.Together("legato " + counted(reach.length));
		var sized = 0;

		for (index in 0...reach.length) {
			final note = reach[index];
			var until = -1;

			for (after in index + 1...reach.length) {
				if (reach[after].at <= note.at) continue;

				until = reach[after].at;
				break;
			}

			if (until < 0) continue;

			final want = until - note.at;
			if (want < 1 || want == note.length) continue;

			group.also(new mdd.song.edit.SizeNote(session.pattern, session.part, note, want));
			sized++;
		}

		if (sized == 0) return false;

		session.does(group);
		session.says(Locale.SAID_NOTES_LEGATO, "" + sized);
		session.changed();

		invalidate();
		return true;
	}

	/**
		Offers tying and untying on a menu. Tying is only offered where the channel can hold a
		note across a tie.

		@param menu The menu to add them to.
	**/
	function tying(menu:Menu):Void {
		final tie = menu.offer(new Choice(translate(Locale.ROLL_TIE)));

		if (ties()) fires(tie, function():Void tied());
		else {
			tie.enabled = false;
			tie.reason = translate(Locale.ROLL_TIE_WHY);
		}

		fires(menu.offer(new Choice(translate(Locale.ROLL_UNTIE))), function():Void untied());
	}

	/**
		@return Whether the chosen channel holds a note across a tie: an FM channel changes the
			pitch without a key on, and a square without starting its envelope again.
	**/
	function ties():Bool {
		return session.part.fm() || session.part.square();
	}

	/**
		Ties every note to the one before it, so the line plays with one key on and changes pitch
		at each tie. A note that stops short of the next is stretched to it and one that runs into
		it is cut back to it. Notes that start together are a chord and are left untied, because a
		channel holds one note. One step on the undo stack.
	**/
	public function tied():Bool {
		if (!ties()) return false;

		final reach = reaching();
		if (reach.length < 2) return false;

		reach.sort(function(one:Note, two:Note):Int return one.at - two.at);

		final group = new mdd.song.edit.Together("tie " + counted(reach.length));
		var many = 0;

		for (index in 1...reach.length) {
			final before = reach[index - 1];
			final note = reach[index];

			if (note.at <= before.at) continue;

			if (before.ends() != note.at) {
				group.also(new mdd.song.edit.SizeNote(session.pattern, session.part, before,
					note.at - before.at));
			}

			if (note.tied) continue;

			group.also(new mdd.song.edit.TieNote(note, true));
			many++;
		}

		if (many == 0) return false;

		session.does(group);
		session.says(Locale.SAID_NOTES_TIED, "" + many);
		session.changed();

		invalidate();
		return true;
	}

	/**
		Unties every tied note, so each one keys on again. One step on the undo stack.
	**/
	public function untied():Bool {
		final reach = reaching();
		final group = new mdd.song.edit.Together("untie " + counted(reach.length));
		var many = 0;

		for (note in reach) {
			if (!note.tied) continue;

			group.also(new mdd.song.edit.TieNote(note, false));
			many++;
		}

		if (many == 0) return false;

		session.does(group);
		session.says(Locale.SAID_NOTES_UNTIED, "" + many);
		session.changed();

		invalidate();
		return true;
	}

	/**
		Folds a run of notes on one key into one.

		Where a note reaches the one after it on the same key, the first grows to cover both
		and the second goes. Notes on different keys are never folded together, however much
		they overlap, because they are two notes.
	**/
	public function glued():Bool {
		final reach = reaching();
		if (reach.length < 2) return false;

		reach.sort(function(one:Note, two:Note):Int {
			if (one.pitch != two.pitch) return one.pitch - two.pitch;
			return one.at - two.at;
		});

		final group = new mdd.song.edit.Together("glue " + counted(reach.length));
		var gone = 0;
		var index = 0;

		while (index < reach.length) {
			final lead = reach[index];
			var until = lead.ends();
			var next = index + 1;

			while (next < reach.length && reach[next].pitch == lead.pitch
					&& reach[next].at <= until) {
				final other = reach[next];
				if (other.ends() > until) until = other.ends();

				next++;
			}

			if (next > index + 1) {
				if (until - lead.at != lead.length) {
					group.also(new mdd.song.edit.SizeNote(session.pattern, session.part, lead,
						until - lead.at));
				}

				for (which in index + 1...next) {
					group.also(new RemoveNote(session.pattern, session.part, reach[which]));
					gone++;
				}
			}

			index = next;
		}

		if (gone == 0) return false;

		picked.clear();
		chosen = null;

		session.does(group);
		session.says(Locale.SAID_NOTES_GLUED, "" + gone);
		session.changed();

		invalidate();
		return true;
	}

	function alters(lead:Note, shift:Bool, ctrl:Bool):Void {
		picked.alters(everything(), chosen, lead, shift, ctrl);
		chosen = picked.holds(lead) ? lead : picked.lead();
	}

	function everything():Array<Note> {
		final pattern = session.current();
		return pattern == null ? [] : pattern.lane(session.part).notes;
	}

	/**
		How far in from the left edge the playhead lands when the view turns to keep it in sight,
		as a share of the view.
	**/
	static inline final LEAD = 0.02;

	/**
		Turns the view on a page to keep a position in the pattern in sight: where it has reached
		the right edge or is left of the left one, the view scrolls to put it just in from the left
		edge. A position outside the pattern moves nothing, because the playhead is then playing
		some other part of the song.

		@param local A position in the pattern, in ticks.
	**/
	public function keeps(local:Int):Void {
		final pattern = session.current();
		if (pattern == null || local < 0 || local > pattern.length) return;

		final room = width - gutter();
		if (room <= 0 || perTick <= 0) return;

		final at = local * perTick - offsetX;
		if (at >= 0 && at < room) return;

		scrollTo(local * perTick - room * LEAD, offsetY);
	}

	/**
		Scrolls to a position, clamped to the pattern.

		@param px How far across.
		@param py How far down.
	**/
	public function scrollTo(px:Float, py:Float):Void {
		final mostX = contentWidth() - (width - gutter());
		final mostY = contentHeight() - grid();

		offsetX = px < 0 ? 0 : (px > mostX ? (mostX < 0 ? 0 : mostX) : px);
		offsetY = py < 0 ? 0 : (py > mostY ? (mostY < 0 ? 0 : mostY) : py);

		invalidate();
	}

	var framedFor:Int = -1;

	/**
		Sets the zoom the first time the roll is drawn, and again where the piece changes
		what it counts a beat in, so a fresh window opens on four bars.
	**/
	public function framed():Void {
		final pattern = session.current();
		if (pattern == null || width <= 0) return;

		final beat = session.song.tempo.ppqn;
		if (beat < 1 || framedFor == beat) return;

		framedFor = beat;

		perTick = zoomed((width - gutter()) / (beat * 16));
		scrollTo(0, offsetY);
	}

	/**
		The zoom is the reader's to set and nothing here narrows it to what the pattern
		happens to be, so the bounds are what a bar can be read at rather than what fits.

		@param want A zoom.
		@return It, held between the two bounds.
	**/
	public function zoomed(want:Float):Float {
		final root = root();
		final bar = session.song.tempo.ppqn * 4;

		if (bar < 1) return want;

		final least = (root == null ? BAR_LEAST : root.metrics.whole(BAR_LEAST)) / bar;
		final most = (root == null ? BAR_MOST : root.metrics.whole(BAR_MOST)) / bar;

		return want < least ? least : (want > most ? most : want);
	}

	/**
		Zooms in or out, keeping a point where it was.

		@param by What to multiply the zoom by.
		@param around The point to keep still, across.
	**/
	public function zoom(by:Float, around:Float):Void {
		final tick = tickAt(around);

		perTick = zoomed(perTick * by);
		scrollTo(tick * perTick - (around - x - gutter()), offsetY);
	}

	/**
		@return How tall a row draws at least, which is the room the name written on it
			needs.
	**/
	public function rowLeast():Float {
		final root = root();
		if (root == null || root.metrics.body == null) return 12;

		final metrics = root.metrics;
		final named = metrics.small == null ? metrics.body : metrics.small;

		return named.height + metrics.unit * 1.5;
	}

	/**
		Makes the rows taller or shorter, keeping a key where it was.

		@param to How tall a row should be.
		@param around The point to keep still, down.
	**/
	public function heightens(to:Float, around:Float):Void {
		final least = rowLeast();
		final most = least * ROW_MOST;
		final want = to < least * ROW_LEAST ? least * ROW_LEAST : (to > most ? most : to);

		if (want == rowTall) return;

		final rows = (around - y - ruler() + offsetY) / rowTall;

		rowTall = want;
		scrollTo(offsetX, rows * want - (around - y - ruler()));
	}

	/**
		The end of a note resizes it and the pan tool drags the view, and neither
		of those shows on the screen.

		@param px A point, across.
		@param py A point, down.
		@return Which cursor shape belongs there.
	**/
	override function cursorAt(px:Float, py:Float):Int {
		if (session.tool == Session.PAN || panning) return mdd.host.Sdl.CURSOR_MOVE;

		if (sizing && dragging != null) return mdd.host.Sdl.CURSOR_ACROSS;

		final under = noteAt(px, py);

		if (under != null && (onEdge(under, px) || onStart(under, px))) {
			return mdd.host.Sdl.CURSOR_ACROSS;
		}

		return mdd.host.Sdl.CURSOR_ARROW;
	}

	override function took(event:Input):Bool {
		final pattern = session.current();
		if (pattern == null) return false;

		kitted();

		switch (event.kind) {
			case Kind.Wheel:
				if (onLaneHead(event.y)) {
					cycles(event.dy > 0 ? -1 : 1);
					return true;
				}

				final zooming = event.ctrl() || event.alt();

				if (zooming && (event.shift() || event.x < x + gutter())) {
					heightens(rowTall * (event.dy > 0 ? 1.15 : 0.87), event.y);
					return true;
				}

				if (zooming) {
					zoom(event.dy > 0 ? 1.25 : 0.8, event.x);
					return true;
				}

				if (event.shift()) {
					scrollTo(offsetX - event.dy * rowTall * 4, offsetY);
					return true;
				}

				scrollTo(offsetX, offsetY - event.dy * rowTall * 3);
				return true;

			case Kind.PointerDown:
				cloning = null;
				if (rubbing) rubDropped();

				final rein = reinAt(event.x, event.y);

				if (rein != 0) {
					reining = rein;
					reined(event.x, event.y);
					return true;
				}

				if (event.y < y + ruler() && event.x >= x + gutter()) {
					scrubbing = true;
					scrubbed(event.x);
					return true;
				}

				if (onLaneHead(event.y)) {
					offered(event.x, y + height - lanes() + stripHead(), 0);
					return true;
				}

				if (onVelocity(event.y)) {
					if (event.x < x + gutter()) return true;

					stalking = stalkAt(event.x);

					if (stalking != null) {
						leans(stalking);
						leaned(event.y);
					}

					return true;
				}

				if (onStrip(event.y)) return false;

				if (event.x < x + gutter()) {
					final pitch = pitchAt(event.y);
					final which = drumAt(pitch);

					if (which >= 0) {
						session.holds();
						session.song.rack[session.part.index()] = which;
						session.frees();
						session.changed();
					}

					if (onAudition != null) onAudition(session.part, pitch);
					records(pitch);
					return true;
				}

				if (event.button == Pointer.Middle || session.tool == Session.PAN) {
					panning = true;
					panX = event.x + offsetX;
					panY = event.y + offsetY;
					return true;
				}

				final under = noteAt(event.x, event.y);

				if (event.button == Pointer.Right) {
					if (under != null && session.tool == Session.DRAW && !event.shift()
						&& !event.ctrl()) {
						rubbing = true;
						rubs(under);
						return true;
					}

					if (under != null) alters(under, false, false);
					popped(under, event.x, event.y);
					invalidate();
					return true;
				}

				if (under != null) {
					if (session.tool == Session.ERASE) {
						rubbing = true;
						rubs(under);
						return true;
					}

					if (session.tool == Session.SLICE) {
						sliced(under, session.snapped(tickAt(event.x)));
						return true;
					}

					if (event.shift() && !event.ctrl()) {
						cloning = under;
						cloneX = event.x;
						cloneY = event.y;
						return true;
					}

					final adding = event.shift() || event.ctrl();
					alters(under, event.shift(), event.ctrl());

					if (adding) {
						invalidate();
						return true;
					}

					dragging = under;
					sizingStart = !onEdge(under, event.x) && onStart(under, event.x);
					sizing = sizingStart || onEdge(under, event.x);
					grabTick = sizing ? 0 : tickAt(event.x) - under.at;
					grabPitch = sizing ? 0 : pitchAt(event.y) - under.pitch;
					grabWasAt = under.at;
					grabWasSeat = under.pitch;
					grabFresh = false;
					grabs(under);
					invalidate();
					return true;
				}

				if (session.tool != Session.DRAW || event.shift() || event.ctrl()) {
					bands(event);
					return true;
				}

				final at = placed(tickAt(event.x), event.alt());
				final pitch = pitchAt(event.y);
				if (pitch < lowest() || pitch > highest()) return true;

				final note = draws(at, pitch);
				if (note == null) return true;

				dragging = note;
				sizing = true;
				sizingStart = false;
				grabTick = 0;
				grabPitch = 0;
				grabWasAt = note.at;
				grabWasSeat = note.pitch;
				grabFresh = true;
				grabs(note);

				if (onAudition != null) onAudition(session.part, pitch);

				invalidate();
				return true;

			case Kind.PointerMove:
				if (reining != 0) {
					reined(event.x, event.y);
					return true;
				}

				if (scrubbing) {
					scrubbed(event.x);
					return true;
				}

				if (panning) {
					scrollTo(panX - event.x, panY - event.y);
					return true;
				}

				if (rubbing) {
					final over = noteAt(event.x, event.y);
					if (over != null) rubs(over);

					return true;
				}

				if (cloning != null) {
					final held = cloning;
					final root = root();
					final far = root == null ? 3.0 : root.metrics.whole(3);

					if (Math.abs(event.x - cloneX) < far && Math.abs(event.y - cloneY) < far) {
						return true;
					}

					cloning = null;

					final copy = clones(held);
					if (copy == null) return true;

					dragging = copy;
					sizing = false;
					sizingStart = false;
					grabTick = tickAt(cloneX) - copy.at;
					grabPitch = pitchAt(cloneY) - copy.pitch;
					grabWasAt = copy.at;
					grabWasSeat = copy.pitch;
					grabFresh = true;
					grabs(copy);
				}

				if (stalking != null) {
					sweeps(event.x);
					leaned(event.y);
					return true;
				}

				if (banding) {
					bandToX = event.x;
					bandToY = event.y;
					invalidate();
					return true;
				}

				if (dragging == null) {
					described(event.x, event.y);
					return false;
				}

				if (sizing) {
					if (sizingStart) restarted(dragging, tickAt(event.x), event.alt());
					else resized(dragging, tickAt(event.x), event.alt());

					invalidate();
					return true;
				}

				hauled(freely(tickAt(event.x) - grabTick, event.alt()),
					pitchAt(event.y) - grabPitch);

				invalidate();
				return true;

			case Kind.PointerUp:
				if (reining != 0) {
					reining = 0;
					return true;
				}

				if (scrubbing) {
					scrubbing = false;
					return true;
				}

				if (panning) {
					panning = false;
					return true;
				}

				if (rubbing) {
					rubDropped();
					return true;
				}

				if (cloning != null) {
					alters(cloning, true, false);
					cloning = null;

					invalidate();
					return true;
				}

				if (stalking != null) {
					stalking = null;
					leanDropped();
					return true;
				}

				if (banding) {
					banded();
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

	function popped(under:Null<Note>, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		menu = new Menu();

		if (under != null) {
			fires(menu.offer(new Choice(translate(Locale.ROLL_COPY),
				mdd.app.Bindings.of(bindings, mdd.app.Bindings.COPY))), function():Void copies());
			fires(menu.offer(new Choice(translate(Locale.ROLL_CUT),
				mdd.app.Bindings.of(bindings, mdd.app.Bindings.CUT))), function():Void {
				copies();
				erased();
			});
			fires(menu.offer(new Choice(translate(Locale.ROLL_DELETE), "Del")), function():Void {
				erased();
			});

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.ROLL_LOUDER))), function():Void
				leant(16));
			fires(menu.offer(new Choice(translate(Locale.ROLL_QUIETER))), function():Void
				leant(-16));
			fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_UP))), function():Void
				nudges(0, 12));
			fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_DOWN))), function():Void
				nudges(0, -12));

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.ROLL_QUANTISE))), function():Void
				quantised());
			fires(menu.offer(new Choice(translate(Locale.ROLL_LEGATO))), function():Void
				stretched());
			fires(menu.offer(new Choice(translate(Locale.ROLL_GLUE))), function():Void glued());
			tying(menu);

			menu.divide();

			final why = menu.offer(new Choice(translate(Locale.ROLL_EXPLAIN)));
			final found = budget == null ? null : reasonFor(under);

			if (found == null) {
				why.enabled = false;
				why.reason = translate(Locale.ROLL_SOUNDS);
			} else {
				fires(why, function():Void {
					session.says(Locale.SAID_WARNING, filled(found.saying, found.values),
						filled(found.reason, found.values),
						filled(found.remedy, found.values));
					session.changed();
				});
			}
		} else {
			final paste = menu.offer(new Choice(translate(Locale.ROLL_PASTE),
				mdd.app.Bindings.of(bindings, mdd.app.Bindings.PASTE)));
			paste.enabled = session.copiedNotes.length > 0;
			if (!paste.enabled) paste.reason = translate(Locale.ROLL_NOTHING_COPIED);

			final at = session.snapped(tickAt(px));
			fires(paste, function():Void pasted(at));

			final row = pitchAt(py);
			final spacings = new Menu();

			for (index in 0...FILLS) {
				final which = index;
				fires(spacings.offer(new Choice(filling(which))), function():Void repeats(row, which));
			}

			menu.offer(new Choice(translate(Locale.ROLL_FILL))).submenu = spacings;

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.ROLL_QUANTISE))), function():Void
				quantised());
			fires(menu.offer(new Choice(translate(Locale.ROLL_LEGATO))), function():Void
				stretched());
			fires(menu.offer(new Choice(translate(Locale.ROLL_GLUE))), function():Void glued());
			tying(menu);

			menu.divide();

			final scales = new Menu();

			for (kind in 0...mdd.song.Scale.KINDS) {
				final choice = scales.offer(new Choice(translate(
					mdd.view.Scales.named(kind))));

				fires(choice, function():Void scaled(kind, session.scale.root));
			}

			final keys = new Menu();

			for (note in 0...12) {
				final choice = keys.offer(new Choice(mdd.song.Scale.rootOf(note, session.notation)));
				fires(choice, function():Void scaled(session.scale.kind, note));
			}

			menu.offer(new Choice(translate(Locale.ROLL_SCALE))).submenu = scales;
			menu.offer(new Choice(translate(Locale.ROLL_KEY))).submenu = keys;

			menu.divide();

			final snaps = new Menu();

			for (index in 0...SNAPS.length) {
				final step = SNAPS[index];
				final choice = snaps.offer(new Choice(translate(SNAP_NAMES[index])));

				fires(choice, function():Void snapped(step));
			}

			fires(menu.offer(new Choice(translate(Locale.ROLL_FIT))), function():Void fitted());
			menu.offer(new Choice(translate(Locale.TRANSPORT_SNAP))).submenu = snaps;
		}

		root.pop(menu, px, py, this);
	}

	function reasonFor(note:Note):Null<mdd.check.Diagnostic> {
		if (budget == null) return null;
		for (found in budget.found) if (found.note == note) return found;
		return null;
	}

	/**
		Which chord runs each action: the ones the menus show, and the piano roll's own, which
		move, transpose and lean the selected notes. The defaults until the application hands over
		the reader's.
	**/
	public var bindings:mdd.app.Bindings = new mdd.app.Bindings();

	function copies():Bool {
		final held = held();
		if (held.length == 0) return false;

		var least = held[0].at;
		for (note in held) if (note.at < least) least = note.at;

		session.copiedNotes.resize(0);

		for (note in held) {
			final made = note.copy();
			made.at -= least;

			session.copiedNotes.push(made);
		}

		session.says(Locale.SAID_NOTES_COPIED, "" + held.length);
		session.changed();

		return true;
	}

	function pasted(at:Int):Void {
		if (session.copiedNotes.length == 0) return;

		final where = at < 0 ? 0 : at;
		final made:Array<Note> = [];

		for (one in session.copiedNotes) {
			final held = one.copy();
			held.at = where + held.at;

			made.push(held);
		}

		if (made.length == 1) {
			session.does(new AddNote(session.pattern, session.part, made[0]));
		} else {
			final group = new mdd.song.edit.Together("paste " + counted(made.length));
			for (note in made) group.also(new AddNote(session.pattern, session.part, note));

			session.does(group);
		}

		picked.clear();
		for (note in made) picked.adds(note);
		chosen = picked.lead();

		session.says(Locale.SAID_NOTES_PASTED, "" + made.length);
		invalidate();
	}

	function leant(by:Int):Void {
		final held = held();
		if (held.length == 0) return;

		if (held.length == 1) {
			session.does(new mdd.song.edit.SetVelocity(held[0], held[0].velocity + by));
			session.says(Locale.SAID_VELOCITY, "" + held[0].velocity);
		} else {
			final group = new mdd.song.edit.Together((by > 0 ? "raise " : "lower ")
				+ counted(held.length));

			for (note in held) {
				group.also(new mdd.song.edit.SetVelocity(note, note.velocity + by));
			}

			session.does(group);
			session.says(by > 0 ? Locale.SAID_NOTES_LOUDER : Locale.SAID_NOTES_QUIETER,
				"" + held.length);
		}

		invalidate();
	}

	/**
		Takes hold of what a press on the velocity strip will lean.

		The selection leans together by however far the lead moves, which is what keeps the
		shape of a phrase while its level changes. A note the sweep reaches afterwards takes
		the height of the pointer outright instead, so a drag across the strip paints.

		@param lead The note pressed on.
	**/
	function leans(lead:Note):Void {
		leaning.resize(0);
		wereLoud.resize(0);

		if (picked.count > 1 && picked.holds(lead)) {
			for (index in 0...picked.count) leaning.push(picked.at(index));
		} else {
			picked.only(lead);
			leaning.push(lead);
		}

		for (note in leaning) wereLoud.push(note.velocity);

		leadLoud = lead.velocity;
		leadLean = leaning.length;
		chosen = lead;
	}

	/**
		Takes up a note the sweep across the strip has reached, so a drag paints every note
		it passes rather than only the one it went down on.

		@param px A point, across.
	**/
	function sweeps(px:Float):Void {
		final found = stalkAt(px);

		if (found == null || leaning.indexOf(found) >= 0) return;

		leaning.push(found);
		wereLoud.push(found.velocity);

		picked.adds(found);
	}

	function leanDropped():Void {
		var many = 0;
		for (index in 0...leaning.length) {
			if (leaning[index].velocity != wereLoud[index]) many++;
		}

		if (many == 0) return;

		final wants:Array<Int> = [];
		for (note in leaning) wants.push(note.velocity);

		for (index in 0...leaning.length) leaning[index].velocity = wereLoud[index];

		if (leaning.length == 1) {
			session.does(new mdd.song.edit.SetVelocity(leaning[0], wants[0]));
			return;
		}

		final group = new mdd.song.edit.Together("lean " + counted(leaning.length));

		for (index in 0...leaning.length) {
			group.also(new mdd.song.edit.SetVelocity(leaning[index], wants[index]));
		}

		session.does(group);
	}

	function scaled(kind:Int, key:Int):Void {
		session.scale.kind = kind;
		session.scale.root = key;

		final held = root();
		final named = held == null ? "" : translate(mdd.view.Scales.named(kind));

		if (kind == mdd.song.Scale.CHROMATIC) session.says(Locale.SAID_CHROMATIC);
		else {
			session.says(Locale.SAID_SCALE, mdd.song.Scale.rootOf(key, session.notation), named,
				"" + session.scale.degrees());
		}

		session.changed();
		invalidate();
	}

	/**
		@param to How many steps a bar is cut into, or nought for no snap.
	**/
	function snapped(to:Int):Void {
		session.snapping = to;
		if (to < 1) session.says(Locale.SAID_SNAP_OFF);
		else session.says(Locale.SAID_SNAP_TO, "" + to, "" + session.snap);
		session.changed();
	}

	function fitted():Void {
		final pattern = session.current();
		if (pattern == null || pattern.length <= 0) return;

		perTick = zoomed((width - gutter()) / pattern.length);

		scrollTo(0, offsetY);
		session.says(Locale.SAID_ZOOMED);
	}

	function steered(event:Input):Bool {
		if (event.code == Key.Escape && picked.count > 0) {
			picked.clear();
			chosen = null;
			invalidate();
			return true;
		}

		if (picked.count == 0) return false;

		if (event.code == Key.Delete || event.code == Key.Backspace) {
			erased();
			return true;
		}

		switch (bindings.actionIn(mdd.app.Bindings.ROLL, event.code, event.mods)) {
			case mdd.app.Bindings.NOTES_EARLIER: nudges(-session.snap, 0);
			case mdd.app.Bindings.NOTES_LATER: nudges(session.snap, 0);
			case mdd.app.Bindings.TRANSPOSE_UP: nudges(0, 1);
			case mdd.app.Bindings.TRANSPOSE_DOWN: nudges(0, -1);
			case mdd.app.Bindings.OCTAVE_UP: nudges(0, 12);
			case mdd.app.Bindings.OCTAVE_DOWN: nudges(0, -12);
			case mdd.app.Bindings.LOUDER: leant(LEAN);
			case mdd.app.Bindings.QUIETER: leant(-LEAN);
			case _: return false;
		}

		return true;
	}

	function erased():Void {
		final held = held();
		if (held.length == 0) return;

		if (held.length == 1) {
			session.does(new RemoveNote(session.pattern, session.part, held[0]));
		} else {
			final group = new mdd.song.edit.Together("remove " + counted(held.length));
			for (note in held) {
				group.also(new RemoveNote(session.pattern, session.part, note));
			}

			session.does(group);
		}

		picked.clear();
		chosen = null;
		invalidate();
	}

	function nudges(byTick:Int, bySeat:Int):Void {
		final held = held();
		if (held.length == 0) return;

		var tick = byTick;
		var seat = bySeat;

		var least = held[0].at;
		var low = held[0].pitch;
		var high = low;

		for (note in held) {
			final row = note.pitch;

			if (note.at < least) least = note.at;
			if (row < low) low = row;
			if (row > high) high = row;
		}

		if (least + tick < 0) tick = -least;
		if (low + seat < lowest()) seat = lowest() - low;
		if (high + seat > highest()) seat = highest() - high;

		if (tick == 0 && seat == 0) return;

		final wantAt:Array<Int> = [];
		final wantPitch:Array<Int> = [];
		final wantHeld:Array<Int> = [];

		for (note in held) {
			final wasAt = note.at;
			final wasPitch = note.pitch;
			final wasHeld = note.instrument;

			if (tick != 0) note.at += tick;
			if (seat != 0) seated(note, note.pitch + seat);

			wantAt.push(note.at);
			wantPitch.push(note.pitch);
			wantHeld.push(note.instrument);

			note.at = wasAt;
			note.pitch = wasPitch;
			note.instrument = wasHeld;
		}

		if (held.length == 1) {
			session.does(new mdd.song.edit.MoveNote(session.pattern, session.part, held[0],
				wantAt[0], wantPitch[0], wantHeld[0]));

			invalidate();
			return;
		}

		final group = new mdd.song.edit.Together("move " + counted(held.length));

		for (index in 0...held.length) {
			group.also(new mdd.song.edit.MoveNote(session.pattern, session.part, held[index],
				wantAt[index], wantPitch[index], wantHeld[index]));
		}

		session.does(group);
		invalidate();
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final pattern = session.current();

		framed();
		kitted();

		final least = rowLeast();

		if (rowTall < least) rowTall = least;
		else if (rowTall > least * ROW_MOST) rowTall = least * ROW_MOST;

		centred();

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		if (pattern == null) return;

		final left = x + gutter();
		final top = y + ruler();

		paint.pushClip(left, top, width - gutter(), grid());
		rows(paint, theme, left, top);
		bars(paint, theme, metrics, left, top, pattern.length);
		beyond(paint, theme, left, top, pattern.length);

		if (session.ghosts) notes(paint, theme, metrics, pattern, true);
		notes(paint, theme, metrics, pattern, false);

		if (banding) band(paint, theme, metrics);

		if (playhead >= 0) {
			final at = atTick(playhead - origin);
			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(2), grid(), theme.warn, 0.9);
			}
		}

		paint.popClip();

		keys(paint, theme, metrics, top);
		heading(paint, theme, metrics, pattern.length);
		strip(paint, theme, metrics, pattern);
		reins(paint, theme, metrics, left, top);

		super.paint(paint);
	}

	/**
		Darkens whatever is past the end of the pattern, which the view scrolls into and
		the grid stops at, so the end is read as an end rather than as a grid that gave
		out.
	**/
	function beyond(paint:Paint, theme:Theme, left:Float, top:Float, length:Int):Void {
		final at = atTick(length);
		final from = at < left ? left : at;
		final until = x + width;

		if (from >= until) return;

		paint.rect(from, top, until - from, grid(), theme.sink, 0.35);
	}

	function band(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final left = bandFromX < bandToX ? bandFromX : bandToX;
		final top = bandFromY < bandToY ? bandFromY : bandToY;
		final wide = bandToX > bandFromX ? bandToX - bandFromX : bandFromX - bandToX;
		final tall = bandToY > bandFromY ? bandToY - bandFromY : bandFromY - bandToY;

		if (wide < 1 || tall < 1) return;

		paint.rect(left, top, wide, tall, theme.ink, 0.1);
		paint.outline(left, top, wide, tall, theme.ink, metrics.whole(1), 0.6);
	}

	var reining:Int = 0;

	/**
		@return How tall the strip that folds the lanes is.
	**/
	public function reinTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	function span(across:Float, reach:Float):Float {
		final root = root();
		final least = root == null ? 24.0 : root.metrics.whole(24);
		final held = across * across / reach;

		return held < least ? least : held;
	}

	function reins(paint:Paint, theme:Theme, metrics:Metrics, left:Float,
			top:Float):Void {
		final thick = reinTall();
		final wide = width - gutter();
		final tall = grid();

		if (contentWidth() > wide + 0.5) {
			final held = span(wide, contentWidth());
			final room = wide - held;
			final most = contentWidth() - wide;
			final at = most <= 0 ? 0 : offsetX / most * room;

			paint.rect(left, top + tall - thick, wide, thick, theme.sink, 0.7);
			paint.roundedRect(left + at, top + tall - thick + metrics.whole(2), held,
				thick - metrics.whole(4), metrics.whole(2), theme.frame);
		}

		if (contentHeight() > tall + 0.5) {
			final held = span(tall, contentHeight());
			final room = tall - held;
			final most = contentHeight() - tall;
			final at = most <= 0 ? 0 : offsetY / most * room;

			paint.rect(x + width - thick, top, thick, tall, theme.sink, 0.7);
			paint.roundedRect(x + width - thick + metrics.whole(2), top + at,
				thick - metrics.whole(4), held, metrics.whole(2), theme.frame);
		}
	}

	function reinAt(px:Float, py:Float):Int {
		final thick = reinTall();
		final top = y + ruler();

		if (py >= top + grid() - thick && py < top + grid() && px >= x + gutter()
			&& contentWidth() > width - gutter() + 0.5) return 1;

		if (px >= x + width - thick && py >= top && py < top + grid()
			&& contentHeight() > grid() + 0.5) return 2;

		return 0;
	}

	function reined(px:Float, py:Float):Void {
		if (reining == 1) {
			final wide = width - gutter();
			final held = span(wide, contentWidth());
			final room = wide - held;

			if (room <= 0) return;

			final want = (px - x - gutter() - held * 0.5) / room;
			scrollTo(want * (contentWidth() - wide), offsetY);
			return;
		}

		final tall = grid();
		final held = span(tall, contentHeight());
		final room = tall - held;

		if (room <= 0) return;

		final want = (py - y - ruler() - held * 0.5) / room;
		scrollTo(offsetX, want * (contentHeight() - tall));
	}

	/**
		@return How tall the velocity strip header is.
	**/
	public function stripHead():Float {
		final root = root();
		return root == null ? 17 : root.metrics.whole(17);
	}

	function strip(paint:Paint, theme:Theme, metrics:Metrics, pattern:Pattern):Void {
		final tall = velocityTall();
		if (tall <= 0) return;

		final top = y + height - lanes();
		final left = x + gutter();
		final font = metrics.small == null ? metrics.body : metrics.small;
		final head = stripHead();

		paint.rect(x, top, width, tall, theme.panel);
		paint.rect(x, top, width, metrics.whole(1), theme.frame);

		paint.rect(x, top, width, head, theme.bar, 0.75);
		paint.rect(x, top + head - metrics.whole(1), width, metrics.whole(1), theme.frame, 0.5);

		paint.reface(font);

		final said = translate(Locale.LANE_VELOCITY);
		final line = top + (head - font.height) * 0.5 + font.ascent;

		paint.text(said, x + metrics.gap, line, theme.ink, 0.95);

		final reach = metrics.whole(3);
		final at = x + metrics.gap + font.measure(said) + metrics.unit + reach;
		final middle = top + head * 0.5;

		final points = new haxe.ds.Vector<Float>(6);

		points[0] = at - reach;
		points[1] = middle - reach * 0.5;
		points[2] = at + reach;
		points[3] = middle - reach * 0.5;
		points[4] = at;
		points[5] = middle + reach * 0.7;

		paint.polygon(points, 3, theme.dim, 0.9);

		paint.textRight(translate(Locale.LANE_PER_NOTE), x + width - metrics.gap, line,
			theme.dim, 0.55);

		final floor = top + tall - metrics.gap;
		final room = tall - head - metrics.gap * 2;
		final held = pattern.lane(session.part);
		final stalk = metrics.whole(3);

		paint.textRight("127", x + gutter() - metrics.unit,
			floor - room + font.ascent * 0.5, theme.dim, 0.45);

		paint.textRight("1", x + gutter() - metrics.unit, floor + font.ascent * 0.5,
			theme.dim, 0.45);

		paint.pushClip(left, top + head, width - gutter(), tall - head);
		paint.rect(left, floor, width - gutter(), metrics.whole(1), theme.frame);

		for (note in held.notes) {
			final at = atTick(note.at);
			if (at < left - stalk || at > x + width) continue;

			final on = picked.holds(note);
			final reach = room * note.velocity / 127.0;
			final colour = on ? theme.ink : theme.part(session.part.index());

			paint.rect(at, floor - reach, stalk, reach, colour, on ? 1 : 0.8);
		}

		paint.popClip();
	}



	/**
		Forgets the selection and the chosen note.
	**/
	public function forgets():Void {
		drawn = 0;
		gridded = -1;

		picked.clear();
		chosen = null;
	}

	/**
		Writes a note, which is what the draw tool does.

		@param at A position in the piece, in ticks.
		@param pitch A MIDI note number.
		@return The note, or null where the pattern would not take it.
	**/
	public function draws(at:Int, pitch:Int):Null<Note> {
		final pattern = session.current();
		if (pattern == null) return null;

		if (session.snap != gridded) {
			gridded = session.snap;
			drawn = 0;
		}

		final length = drawn < 1 ? stepped() : drawn;
		final note = new Note(at < 0 ? 0 : at, length, pitch, 100);

		seated(note, pitch);
		session.does(new AddNote(session.pattern, session.part, note));

		picked.only(note);
		chosen = note;

		return note;
	}

	/**
		@return How many ticks a sixteenth is, which is the default note length.
	**/
	public function sixteenth():Int {
		final held = Std.int(session.song.tempo.ppqn / 4);
		return held < 1 ? 1 : held;
	}

	/**
		@return How many ticks one grid step is.
	**/
	public function stepped():Int {
		final least = sixteenth();
		final held = session.snap < 1 ? least : session.snap;

		return held < least ? least : held;
	}

	/**
		@return How near the end of a note counts as its edge, for resizing.
	**/
	public function edge():Float {
		final root = root();
		return root == null ? 6 : root.metrics.whole(6);
	}

	/**
		@param note A note.
		@param px A point, across.
		@return Whether the point is on its edge rather than its body.
	**/
	public function onEdge(note:Note, px:Float):Bool {
		final right = atTick(note.at + note.length);
		final reach = edge();

		return px >= right - reach && px <= right + reach;
	}

	/**
		Whether a point is near where a note begins, which drags its start rather
		than the whole note.

		A note narrower than three of these handles has none: the end is what a
		narrow note resizes from, and the rest of it has to stay somewhere the
		whole note can be taken hold of and moved.

		@param note A note.
		@param px A point, across.
		@return Whether that point is on its start.
	**/
	public function onStart(note:Note, px:Float):Bool {
		final reach = edge();
		if (note.length * perTick < reach * 3) return false;

		final left = atTick(note.at);

		return px >= left - reach && px <= left + reach;
	}

	/**
		Changes how long a note is.

		@param note The note.
		@param to The tick it should end on.
		@param free Whether to ignore the snap, which holding alt does.
	**/
	public function resized(note:Note, to:Int, free:Bool = false):Void {
		final least = free || session.snap < 1 ? 1 : session.snap;
		var want = freely(to, free) - note.at;

		if (want < least) want = least;
		if (want == note.length) return;

		final by = want - note.length;

		note.length = want;
		drawn = want;

		final pattern = session.current();
		if (pattern != null) pattern.lane(session.part).grow(want);

		if (moving.length < 2 || !picked.holds(note)) return;

		for (index in 0...moving.length) {
			final other = moving[index];
			if (other == note) continue;

			var held = other.length + by;
			if (held < least) held = least;

			other.length = held;
			if (pattern != null) pattern.lane(session.part).grow(held);
		}
	}

	function sliced(note:Note, at:Int):Void {
		if (at <= note.at || at >= note.at + note.length) return;

		final rest = new Note(at, note.at + note.length - at, note.pitch, note.velocity,
			note.instrument);

		note.length = at - note.at;
		session.does(new AddNote(session.pattern, session.part, rest));
		invalidate();
	}

	/**
		Says in the tooltip what the pointer is over, tested in the order a press is: the ruler,
		the head of the lanes, the velocity strip and the keys. The notes and the grid are the
		music itself and say nothing, and the lanes below speak for themselves.

		@param px A point, across.
		@param py A point, down.
	**/
	function described(px:Float, py:Float):Void {
		detail = "";

		if (py < y + ruler()) {
			tip = px < x + gutter() ? "" : translate(Locale.EDITOR_RULER);
			if (tip != "") detail = translate(Locale.EDITOR_RULER_DETAIL);
			return;
		}

		if (onLaneHead(py)) {
			tip = translate(Locale.ROLL_LANES);
			return;
		}

		if (onVelocity(py)) {
			tip = px < x + gutter() ? "" : translate(Locale.ROLL_VELOCITY);
			if (tip != "") detail = translate(Locale.ROLL_VELOCITY_DETAIL);
			return;
		}

		if (onStrip(py)) {
			tip = "";
			return;
		}

		tip = px < x + gutter() ? translate(Locale.ROLL_KEYS) : "";
	}

	inline function onStrip(py:Float):Bool {
		return lanes() > 0 && py >= y + height - lanes();
	}

	inline function onVelocity(py:Float):Bool {
		final top = y + height - lanes();
		return lanes() > 0 && py >= top && py < top + velocityTall();
	}

	function stalkAt(px:Float):Null<Note> {
		final pattern = session.current();
		if (pattern == null) return null;

		final root = root();
		final reach = root == null ? 4.0 : root.metrics.whole(4);
		var found:Null<Note> = null;
		var nearest = reach;

		for (note in pattern.lane(session.part).notes) {
			final away = Math.abs(atTick(note.at) - px);
			if (away > nearest) continue;

			nearest = away;
			found = note;
		}

		return found;
	}

	function leaned(py:Float):Void {
		if (stalking == null) return;

		final root = root();
		final gap = root == null ? 6.0 : root.metrics.gap;

		final tall = velocityTall();
		final floor = y + height - lanes() + tall - gap;
		final room = tall - stripHead() - gap * 2;
		if (room <= 0) return;

		var part = (floor - py) / room;
		if (part < 0) part = 0;
		if (part > 1) part = 1;

		final want = Math.round(part * 127);
		final by = want - leadLoud;

		for (index in 0...leaning.length) {
			final held = index < leadLean ? wereLoud[index] + by : want;
			leaning[index].velocity = held < 1 ? 1 : (held > 127 ? 127 : held);
		}

		session.changed();
		invalidate();
	}



	function rows(paint:Paint, theme:Theme, left:Float, top:Float):Void {
		final floor = lowest();

		if (kitting()) {
			final under = atPitch(floor);

			if (under + rowTall < y + height) {
				paint.rect(left, under + rowTall, width - gutter(),
					y + height - under - rowTall, theme.sink, 0.6);
			}
		}
		var pitch = pitchAt(top);
		if (pitch > highest()) pitch = highest();

		while (pitch >= floor) {
			final row = atPitch(pitch);
			if (row > y + height) {
				pitch--;
				continue;
			}
			if (row + rowTall < top) break;

			final scale = session.scale;
			final lit = !kitting() && session.highlight
				&& scale.kind != mdd.song.Scale.CHROMATIC;

			if (kitting()) {
				if ((pitch & 1) == 0) {
					paint.rect(left, row, width - gutter(), rowTall, theme.sink, 0.35);
				}
			} else if (lit && scale.rooted(pitch)) {
				paint.rect(left, row, width - gutter(), rowTall,
					theme.part(session.part.index()), 0.14);
			} else if (lit && !scale.holds(pitch)) {
				paint.rect(left, row, width - gutter(), rowTall, theme.sink, 0.72);
			} else if (BLACK[pitch % 12]) {
				paint.rect(left, row, width - gutter(), rowTall, theme.sink, 0.5);
			} else if (pitch % 12 == 0) {
				paint.rect(left, row, width - gutter(), rowTall, theme.raise1, 0.4);
			}

			pitch--;
		}
	}

	function bars(paint:Paint, theme:Theme, metrics:Metrics, left:Float, top:Float,
			length:Int):Void {
		final beat = session.song.tempo.ppqn;
		final bar = beat * 4;
		final hair = metrics.whole(1);
		final step = session.snap;

		if (step > 0 && step < beat && step * perTick >= metrics.whole(5)) {
			var fine = Std.int(tickAt(left) / step) * step;
			if (fine < 0) fine = 0;

			while (fine <= length) {
				final at = atTick(fine);
				if (at > x + width) break;

				if (at > left && fine % beat != 0) {
					paint.rect(at, top, hair, grid(), theme.frame, 0.14);
				}

				fine += step;
			}
		}

		var tick = Std.int(tickAt(left) / beat) * beat;
		if (tick < 0) tick = 0;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at > left) {
				final major = tick % bar == 0;
				paint.rect(at, top, hair, grid(), theme.frame, major ? 0.9 : 0.35);
			}

			tick += beat;
		}
	}

	function notes(paint:Paint, theme:Theme, metrics:Metrics, pattern:mdd.song.Pattern,
			ghost:Bool):Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final own = index == session.part.index();

			if (ghost == own) continue;
			if (ghost && !session.song.audible(part)) continue;

			drawLane(paint, theme, metrics, pattern.lane(part), theme.part(index), ghost);
		}
	}

	function drawLane(paint:Paint, theme:Theme, metrics:Metrics, lane:Lane, colour:Colour,
			ghost:Bool):Void {
		final left = x + gutter();
		final radius = metrics.radiusSmall;
		final notes = lane.notes;

		for (index in 0...notes.length) {
			final note = notes[index];
			final at = atTick(note.at);
			final wide = note.length * perTick;

			if (at + wide < left || at > x + width) continue;

			final row = atPitch(note.pitch);
			if (row + rowTall < y + ruler() || row > y + height) continue;

			painted++;

			final tall = rowTall - 1;

			if (ghost) {
				paint.roundedRect(at, row, wide, tall, radius, theme.panel.mix(colour, 0.3));
				continue;
			}

			final unsound = budget != null && budget.troubled(note);

			paint.roundedGradient(at, row, wide, tall, radius, colour.lift(0.22),
				colour.sink(0.18), unsound ? 0.35 : 0.9);

			if (unsound) hatch(paint, theme, metrics, at, row, wide, tall);

			if (picked.holds(note)) {
				paint.outline(at, row, wide, tall, theme.ink, metrics.whole(1),
					note == chosen ? 1 : 0.65, radius);
			}

			if (note.tied && index > 0 && notes[index - 1].ends() >= note.at) {
				final from = atPitch(notes[index - 1].pitch) + tall * 0.5;
				final reach = metrics.whole(4);

				paint.line(at - reach, from, at + reach, row + tall * 0.5, metrics.whole(2),
					theme.ink, 0.85);
			}
		}
	}

	function hatch(paint:Paint, theme:Theme, metrics:Metrics, at:Float, row:Float, wide:Float,
			tall:Float):Void {
		final hair = metrics.whole(1);
		final step = tall;

		paint.outline(at, row, wide, tall, theme.warn, hair, 0.9);

		var pen = at;
		while (pen < at + wide) {
			final reach = pen + tall > at + wide ? at + wide - pen : tall;
			paint.line(pen, row + tall, pen + reach, row + tall - reach, hair, theme.warn, 0.7);
			pen += step;
		}
	}

	/**
		Lights the keys that are sounding now, read back out of the register stream
		rather than asked of the sequencer.

		@param sounding What is keyed.
	**/
	public function lights(sounding:mdd.play.Sounding):Void {
		final which = session.part.index();
		final on = sounding.keyed[which];
		final note = on ? sounding.notes[which] : -1;

		if (note == litNote && on == litOn) return;

		litNote = note;
		litOn = on;
		invalidate();
	}

	/**
		How many spacings the fill menu offers: a step, two, four, a beat, two and a bar.
	**/
	static inline final FILLS = 6;

	/**
		@param which Which spacing.
		@return What the fill menu calls it.
	**/
	function filling(which:Int):String {
		return switch (which) {
			case 0: translate(Locale.FILL_STEP);
			case 1: filled(Locale.FILL_STEPS, ["2"]);
			case 2: filled(Locale.FILL_STEPS, ["4"]);
			case 3: translate(Locale.FILL_BEAT);
			case 4: filled(Locale.FILL_BEATS, ["2"]);
			case _: translate(Locale.FILL_BAR);
		}
	}

	/**
		Fills a row of the pattern with notes a spacing apart across its whole length, each a step
		long or the spacing where that is shorter, and leaves any place that already starts a note
		on that row alone. One step on the undo stack.

		@param pitch The row.
		@param which Which spacing the fill menu offered.
	**/
	function repeats(pitch:Int, which:Int):Void {
		final pattern = session.current();
		if (pattern == null || pitch < 0 || pitch > 127) return;

		final beat = session.song.tempo.ppqn;
		final step = session.snap < 1 ? Std.int(beat / 4) : session.snap;

		final every = switch (which) {
			case 0: step;
			case 1: step * 2;
			case 2: step * 4;
			case 3: beat;
			case 4: beat * 2;
			case _: beat * 4;
		}

		if (every < 1) return;

		final lane = pattern.lane(session.part);
		final length = step < every ? step : every;
		final group = new mdd.song.edit.Together("fill");

		var many = 0;
		var at = 0;

		while (at < pattern.length) {
			var taken = false;

			for (note in lane.notes) {
				if (note.at != at || note.pitch != pitch) continue;

				taken = true;
				break;
			}

			if (!taken) {
				group.also(new AddNote(session.pattern, session.part, new Note(at, length, pitch, 100)));
				many++;
			}

			at += every;
		}

		if (many > 0) session.does(group);
	}

	/**
		@param pitch A MIDI note number.
		@param style How notes are written, English with sharps unless given.
		@return Its name and octave.
	**/
	public static function named(pitch:Int, style:Int = 0):String {
		return mdd.song.Notation.spelt(pitch, style);
	}

	function keys(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final wide = gutter();

		paint.rect(x, top, wide, grid(), theme.panel);
		paint.pushClip(x, top, wide, grid());
		paint.reface(metrics.small == null ? metrics.body : metrics.small);

		final font = metrics.small == null ? metrics.body : metrics.small;
		final drums = kitting();
		final floor = lowest();
		var pitch = highest();

		while (pitch >= floor) {
			final row = atPitch(pitch);

			if (row + rowTall >= top && row <= y + height) {
				final seated = drums && drumAt(pitch) >= 0;
				final black = BLACK[pitch % 12];
				final lit = litOn && pitch == litNote;

				if (lit) {
					paint.rect(x, row, wide, rowTall - 1, theme.part(session.part.index()));
				} else if (seated) {
					paint.rect(x, row, wide, rowTall - 1, theme.raise1);
				} else {
					paint.rect(x, row, wide, rowTall - 1, black ? theme.ebony : theme.ivory,
						black ? 1 : (drums ? SILENT : 0.72));
				}

				if (rowTall >= font.height) {
					final rooted = !drums && pitch % 12 == 0;

					if (seated) {
						paint.text(seatName(pitch), x + metrics.unit * 2,
							row + (rowTall - font.height) * 0.5 + font.ascent, theme.ink, 0.9);
					} else {
						paint.textRight(named(pitch, session.notation), x + wide - metrics.unit * 2,
							row + (rowTall - font.height) * 0.5 + font.ascent,
							black ? (theme.light ? theme.frame : theme.dim) : theme.ebony,
							drums ? SILENT : (rooted ? 1 : 0.75));
					}
				}
			}

			pitch--;
		}

		paint.popClip();

		paint.rect(x + wide - metrics.whole(1), top, metrics.whole(1), grid(),
			theme.frame);
	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics, length:Int):Void {
		final tall = ruler();
		final left = x + gutter();

		paint.rect(x, y, width, tall, theme.bar);
		paint.pushClip(left, y, width - gutter(), tall);

		final font = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(font);

		final bar = session.song.tempo.ppqn * 4;
		var tick = Std.int(tickAt(left) / bar) * bar;
		if (tick < 0) tick = 0;

		var written = left - metrics.gap;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left && at >= written) {
				final said = Std.string(Std.int((origin + tick) / bar) + 1);

				paint.text(said, at + metrics.unit,
					y + (tall - font.height) * 0.5 + font.ascent, theme.dim);

				written = at + metrics.unit + paint.measure(said) + metrics.gap;
			}

			tick += bar;
		}

		paint.popClip();
		paint.rect(x, y + tall - metrics.whole(1), width, metrics.whole(1), theme.frame, 0.7);
	}
}
