package mdd.view;

import mdd.check.Budget;
import mdd.song.edit.AddNote;
import mdd.song.Lane;
import mdd.song.Note;
import mdd.song.Pattern;
import mdd.song.Part;
import mdd.song.edit.RemoveNote;
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

@:unreflective
final class PianoRoll extends Widget {
	public static inline final VELOCITY = 0;
	public static inline final PAN = 1;
	public static inline final AUTOMATION = 2;
	public static inline final LANES = 3;

	public static inline final LOWEST = 12;
	public static inline final HIGHEST = 108;
	public static inline final KIT_BASE = 24;

	static final BLACK:Array<Bool> = [false, true, false, true, false, false, true, false, true,
		false, true, false];

	public final session:Session;

	public var perTick:Float = 0.25;
	public var rowTall:Float = 12;

	public var offsetX:Float = 0;
	public var offsetY:Float = 0;

	public var playhead:Int = -1;
	public var budget:Null<Budget> = null;

	public var painted(default, null):Int = 0;
	public var chosen(default, null):Null<Note> = null;

	public var onAudition:Null<(Part, Int) -> Void> = null;
	public var showLanes:Bool = true;
	var stalking:Null<Note> = null;
	var litNote:Int = -1;
	var litOn:Bool = false;
	public var lane(default, null):Int = VELOCITY;

	var dragging:Null<Note> = null;
	var grabTick:Int = 0;
	var grabPitch:Int = 0;
	var grabWasAt:Int = 0;
	var grabWasPitch:Int = 0;
	var grabWasHeld:Int = 0;
	var grabWasLong:Int = 0;
	var grabFresh:Bool = false;
	var sizing:Bool = false;
	var drawn:Int = 0;
	var panning:Bool = false;
	var scrubbing:Bool = false;
	var menu:Null<Menu> = null;
	var panX:Float = 0;
	var panY:Float = 0;

	final kit:Array<Int> = [];

	var wasTall:Float = 0;
	var settledOn:Int = -1;
	var settledPart:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public inline function kitting():Bool {
		return session.part.sampled();
	}

	public function kitted():Void {
		kit.resize(0);

		if (!kitting()) {
			if (wasTall > 0) {
				rowTall = wasTall;
				wasTall = 0;
			}

			return;
		}

		final root = root();
		var want = root == null ? 34.0 : root.metrics.row;

		if (wasTall <= 0) wasTall = rowTall;

		final song = session.song;

		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			if (held.sample < 0 || song.sampleAt(held.sample) == null) continue;

			kit.push(index);
		}

		final most = root == null ? 60.0 : root.metrics.whole(60);
		final room = kit.length < 1 ? want : grid() / kit.length;

		if (room > want) want = room > most ? most : room;

		rowTall = want;
	}

	public function lowest():Int {
		return kitting() ? KIT_BASE : LOWEST;
	}

	public function highest():Int {
		if (!kitting()) return HIGHEST;
		return KIT_BASE + (kit.length < 1 ? 0 : kit.length - 1);
	}

	public function seatOf(note:Note):Int {
		if (!kitting()) return note.pitch;

		final want = note.instrument >= 0 ? note.instrument
			: session.song.rack[session.part.index()];
		final at = kit.indexOf(want);

		return KIT_BASE + (at < 0 ? 0 : at);
	}

	public function seated(note:Note, seat:Int):Void {
		if (!kitting()) {
			note.pitch = seat;
			return;
		}

		final at = seat - KIT_BASE;
		if (at < 0 || at >= kit.length) return;

		final which = kit[at];
		note.instrument = which;

		final held = session.song.instrumentAt(which);
		final sample = held == null ? null : session.song.sampleAt(held.sample);

		note.pitch = sample == null ? 60 : sample.root;
	}

	public function seatName(seat:Int):String {
		if (!kitting()) return named(seat);

		final at = seat - KIT_BASE;
		if (at < 0 || at >= kit.length) return "";

		final held = session.song.instrumentAt(kit[at]);
		return held == null ? "" : held.name;
	}

	function records(pitch:Int):Void {
		if (!session.arming || !session.transport.playing) return;

		final pattern = session.current();
		if (pattern == null) return;

		final at = session.snapped(session.transport.tick());
		final length = session.snap < 1 ? session.song.tempo.ppqn : session.snap;

		session.does(new mdd.song.edit.AddNote(session.pattern, session.part,
			new mdd.song.Note(at, length, pitch)));
	}

	public function gutter():Float {
		final root = root();
		return root == null ? 56 : root.metrics.whole(56);
	}

	public function ruler():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	public function lanes():Float {
		if (!showLanes) return 0;

		final root = root();
		return root == null ? 80 : root.metrics.whole(80);
	}

	public inline function grid():Float {
		return height - ruler() - lanes();
	}

	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - gutter() + offsetX) / perTick);
	}

	public inline function atTick(tick:Int):Float {
		return x + gutter() + tick * perTick - offsetX;
	}

	public inline function pitchAt(py:Float):Int {
		return highest() - Std.int((py - y - ruler() + offsetY) / rowTall);
	}

	public inline function atPitch(pitch:Int):Float {
		return y + ruler() + (highest() - pitch) * rowTall - offsetY;
	}

	public function contentWidth():Float {
		final pattern = session.current();
		return pattern == null ? 0 : pattern.length * perTick;
	}

	public function contentHeight():Float {
		return (highest() - lowest() + 1) * rowTall;
	}

	public function noteAt(px:Float, py:Float):Null<Note> {
		final pattern = session.current();
		if (pattern == null) return null;

		final tick = tickAt(px);
		final pitch = pitchAt(py);
		final lane = pattern.lane(session.part);

		var found:Null<Note> = null;

		for (note in lane.notes) {
			if (seatOf(note) != pitch) continue;
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

		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		if (lane.notes.length == 0) return;

		final first = lane.notes[0];
		var low = seatOf(first);
		var high = low;

		for (note in lane.notes) {
			if (note.at > first.at + session.song.tempo.ppqn * 16) break;

			final seat = seatOf(note);
			if (seat < low) low = seat;
			if (seat > high) high = seat;
		}

		reveal(first.at, Math.round((low + high) * 0.5));
	}

	function settled():Void {
		final held = dragging;

		dragging = null;

		if (held == null) {
			sizing = false;
			return;
		}

		session.holds();
		session.current().lane(session.part).sort();
		session.frees();

		if (grabFresh) {
			sizing = false;
			grabFresh = false;
			session.changed();
			return;
		}

		if (sizing && held.length != grabWasLong) {
			final want = held.length;

			held.length = grabWasLong;
			session.does(new mdd.song.edit.SizeNote(session.pattern, session.part, held,
				want));
		} else if (!sizing && (held.at != grabWasAt || held.pitch != grabWasPitch
				|| held.instrument != grabWasHeld)) {
			final at = held.at;
			final pitch = held.pitch;
			final want = held.instrument;

			held.at = grabWasAt;
			held.pitch = grabWasPitch;
			held.instrument = grabWasHeld;

			session.does(new mdd.song.edit.MoveNote(session.pattern, session.part, held, at,
				pitch, want));
		}

		sizing = false;
		session.changed();
	}

	public function scrubbed(px:Float):Void {
		final tick = session.snapped(tickAt(px));
		final want = tick < 0 ? 0 : tick;

		session.transport.seek(session.song.tempo.samplesAt(want));
		playhead = want;

		invalidate();
	}

	public function reveal(tick:Int, pitch:Int):Void {
		final wide = width - gutter();
		final tall = grid();

		scrollTo(tick * perTick - wide * 0.3, (highest() - pitch) * rowTall - tall * 0.5);
	}

	public function choose(note:Null<Note>):Void {
		chosen = note;
		invalidate();
	}

	public function scrollTo(px:Float, py:Float):Void {
		final mostX = contentWidth() - (width - gutter());
		final mostY = contentHeight() - grid();

		offsetX = px < 0 ? 0 : (px > mostX ? (mostX < 0 ? 0 : mostX) : px);
		offsetY = py < 0 ? 0 : (py > mostY ? (mostY < 0 ? 0 : mostY) : py);

		invalidate();
	}

	public function widest():Float {
		final pattern = session.current();
		final length = pattern == null ? 0 : pattern.length;

		if (length < 1) return 0.02;

		final fits = (width - gutter()) / length;
		return fits < 0.02 ? fits : 0.02;
	}

	public function zoom(by:Float, around:Float):Void {
		final tick = tickAt(around);
		final want = perTick * by;
		final least = widest();

		perTick = want < least ? least : (want > 4 ? 4 : want);
		scrollTo(tick * perTick - (around - x - gutter()), offsetY);
	}

	override function took(event:Input):Bool {
		final pattern = session.current();
		if (pattern == null) return false;

		kitted();

		switch (event.kind) {
			case Kind.Wheel:
				if (event.ctrl() || event.alt()) {
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

				if (onStrip(event.y)) {
					if (event.x < x + gutter()) {
						showsLane((lane + 1) % LANES);
						return true;
					}

					stalking = stalkAt(event.x);
					if (stalking != null) leaned(event.y);
					return true;
				}

				if (event.x < x + gutter()) {
					final pitch = pitchAt(event.y);
					final seat = pitch - KIT_BASE;

					if (kitting() && seat >= 0 && seat < kit.length) {
						session.song.rack[session.part.index()] = kit[seat];
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
					if (under != null) chosen = under;
					popped(under, event.x, event.y);
					invalidate();
					return true;
				}

				if (under != null) {
					if (session.tool == Session.ERASE) {
						if (chosen == under) chosen = null;
						session.does(new mdd.song.edit.RemoveNote(session.pattern, session.part, under));
						invalidate();
						return true;
					}

					if (session.tool == Session.SLICE) {
						sliced(under, session.snapped(tickAt(event.x)));
						return true;
					}

					chosen = under;
					dragging = under;
					sizing = onEdge(under, event.x);
					grabTick = sizing ? 0 : tickAt(event.x) - under.at;
					grabPitch = sizing ? 0 : pitchAt(event.y) - seatOf(under);
					grabWasAt = under.at;
					grabWasPitch = under.pitch;
					grabWasHeld = under.instrument;
					grabWasLong = under.length;
					grabFresh = false;
					invalidate();
					return true;
				}

				if (session.tool != Session.DRAW) {
					chosen = null;
					invalidate();
					return true;
				}

				final at = session.snapped(tickAt(event.x));
				final pitch = pitchAt(event.y);
				if (pitch < lowest() || pitch > highest()) return true;

				final length = drawn < 1 ? (session.snap < 1 ? 24 : session.snap) : drawn;
				final note = new Note(at < 0 ? 0 : at, length, pitch, 100);

				seated(note, pitch);
				session.does(new AddNote(session.pattern, session.part, note));

				chosen = note;
				dragging = note;
				sizing = true;
				grabTick = 0;
				grabPitch = 0;
				grabWasAt = note.at;
				grabWasPitch = note.pitch;
				grabWasHeld = note.instrument;
				grabWasLong = note.length;
				grabFresh = true;

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

				if (stalking != null) {
					leaned(event.y);
					return true;
				}

				if (dragging == null) return false;

				if (sizing) {
					resized(dragging, tickAt(event.x));
					invalidate();
					return true;
				}

				final at = session.snapped(tickAt(event.x) - grabTick);
				final pitch = pitchAt(event.y) - grabPitch;
				final floor = lowest();
				final ceiling = highest();

				dragging.at = at < 0 ? 0 : at;
				seated(dragging, pitch < floor ? floor : (pitch > ceiling ? ceiling : pitch));

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

				if (stalking != null) {
					stalking = null;
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
			fires(menu.offer(new Choice(translate(Locale.ROLL_COPY), "Ctrl+C")), function():Void copy(under));
			fires(menu.offer(new Choice(translate(Locale.ROLL_CUT), "Ctrl+X")), function():Void {
				copy(under);
				session.does(new RemoveNote(session.pattern, session.part, under));
				chosen = null;
			});
			fires(menu.offer(new Choice(translate(Locale.ROLL_DELETE), "Del")), function():Void {
				session.does(new RemoveNote(session.pattern, session.part, under));
				chosen = null;
			});

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.ROLL_LOUDER))), function():Void {
				under.velocity = under.velocity > 111 ? 127 : under.velocity + 16;
				session.say("velocity " + under.velocity);
				session.changed();
			});
			fires(menu.offer(new Choice(translate(Locale.ROLL_QUIETER))), function():Void {
				under.velocity = under.velocity < 16 ? 0 : under.velocity - 16;
				session.say("velocity " + under.velocity);
				session.changed();
			});
			fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_UP))), function():Void shifted(under, 12));
			fires(menu.offer(new Choice(translate(Locale.ROLL_OCTAVE_DOWN))), function():Void shifted(under, -12));

			menu.divide();

			final why = menu.offer(new Choice(translate(Locale.ROLL_EXPLAIN)));
			final found = budget == null ? null : reasonFor(under);

			if (found == null) {
				why.enabled = false;
				why.reason = translate(Locale.ROLL_SOUNDS);
			} else {
				fires(why, function():Void {
					session.say(found.saying + " because " + found.reason + ", so " + found.remedy);
					session.changed();
				});
			}
		} else {
			final paste = menu.offer(new Choice(translate(Locale.ROLL_PASTE), "Ctrl+V"));
			paste.enabled = session.copiedNotes.length > 0;
			if (!paste.enabled) paste.reason = translate(Locale.ROLL_NOTHING_COPIED);

			final at = session.snapped(tickAt(px));
			fires(paste, function():Void pasted(at));

			menu.divide();

			final scales = new Menu();

			for (kind in 0...mdd.song.Scale.KINDS) {
				final choice = scales.offer(new Choice(translate(
					mdd.song.Scale.nameOf(kind))));

				fires(choice, function():Void scaled(kind, session.scale.root));
			}

			final keys = new Menu();

			for (note in 0...12) {
				final choice = keys.offer(new Choice(mdd.song.Scale.rootOf(note)));
				fires(choice, function():Void scaled(session.scale.kind, note));
			}

			menu.offer(new Choice(translate(Locale.ROLL_SCALE))).submenu = scales;
			menu.offer(new Choice(translate(Locale.ROLL_KEY))).submenu = keys;

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.ROLL_FIT))), function():Void fitted());
			fires(menu.offer(new Choice(translate(Locale.ROLL_SNAP_BEAT))), function():Void snapped(24));
			fires(menu.offer(new Choice(translate(Locale.ROLL_SNAP_BAR))), function():Void snapped(96));
			fires(menu.offer(new Choice(translate(Locale.ROLL_SNAP_NONE))), function():Void snapped(1));
		}

		root.pop(menu, px, py, this);
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}

	function reasonFor(note:Note):Null<mdd.check.Diagnostic> {
		if (budget == null) return null;
		for (found in budget.found) if (found.note == note) return found;
		return null;
	}

	function copy(note:Note):Void {
		session.copiedNotes.resize(0);
		session.copiedNotes.push(note.copy());

		session.say("copied a note");
		session.changed();
	}

	function pasted(at:Int):Void {
		if (session.copiedNotes.length == 0) return;

		final held = session.copiedNotes[0].copy();
		held.at = at < 0 ? 0 : at;

		session.does(new AddNote(session.pattern, session.part, held));
		chosen = held;

		session.say("pasted a note");
		invalidate();
	}

	function shifted(note:Note, by:Int):Void {
		final floor = lowest();
		final ceiling = highest();
		final want = seatOf(note) + by;

		seated(note, want < floor ? floor : (want > ceiling ? ceiling : want));
		session.say("moved to " + seatName(seatOf(note)));
		session.changed();
		invalidate();
	}

	function scaled(kind:Int, key:Int):Void {
		session.scale.kind = kind;
		session.scale.root = key;

		final held = root();
		final named = held == null ? mdd.song.Scale.nameOf(kind)
			: translate(mdd.song.Scale.nameOf(kind));

		session.say(kind == mdd.song.Scale.CHROMATIC ? "every note lit"
			: mdd.song.Scale.rootOf(key) + " " + named + ", "
			+ session.scale.degrees() + " of twelve lit");

		session.changed();
		invalidate();
	}

	function snapped(to:Int):Void {
		session.snap = to;
		session.say(to == 1 ? "no snap" : "snapping to " + to + " ticks");
		session.changed();
	}

	function fitted():Void {
		final pattern = session.current();
		if (pattern == null || pattern.length <= 0) return;

		perTick = (width - gutter()) / pattern.length;

		scrollTo(0, offsetY);
		session.say("zoomed to the pattern");
	}

	function steered(event:Input):Bool {
		if (chosen == null) return false;

		switch (event.code) {
			case Key.Delete, Key.Backspace:
				session.does(new RemoveNote(session.pattern, session.part, chosen));
				chosen = null;
				invalidate();
				return true;

			case Key.Up:
				if (seatOf(chosen) < highest()) seated(chosen, seatOf(chosen) + 1);
				invalidate();
				return true;

			case Key.Down:
				if (seatOf(chosen) > lowest()) seated(chosen, seatOf(chosen) - 1);
				invalidate();
				return true;

			case Key.Left:
				chosen.at = chosen.at > session.snap ? chosen.at - session.snap : 0;
				invalidate();
				return true;

			case Key.Right:
				chosen.at += session.snap;
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final pattern = session.current();

		kitted();

		final named = metrics.small == null ? metrics.body : metrics.small;
		final least = named.height + metrics.unit * 1.5;

		if (rowTall < least) rowTall = least;

		centred();

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		if (pattern == null) return;

		final left = x + gutter();
		final top = y + ruler();

		paint.pushClip(left, top, width - gutter(), grid());
		rows(paint, theme, left, top);
		bars(paint, theme, metrics, left, top, pattern.length);

		if (session.ghosts) notes(paint, theme, metrics, pattern, true);
		notes(paint, theme, metrics, pattern, false);

		if (playhead >= 0) {
			final at = atTick(playhead);
			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(2), grid(), theme.warn, 0.9);
			}
		}

		paint.popClip();

		keys(paint, theme, metrics, top);
		heading(paint, theme, metrics, pattern.length);
		strip(paint, theme, metrics, pattern);
		reins(paint, theme, metrics, left, top);

		Panel.edge(paint, theme, metrics, x, y, width, height);
	}

	var reining:Int = 0;

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

	function strip(paint:Paint, theme:Theme, metrics:Metrics, pattern:Pattern):Void {
		final tall = lanes();
		if (tall <= 0) return;

		final top = y + height - tall;
		final left = x + gutter();
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.rect(x, top, width, tall, theme.panel);
		paint.rect(x, top, width, metrics.whole(1), theme.frame);

		paint.reface(font);
		paint.text(translate(laneName()), x + metrics.gap, top + metrics.gap + font.ascent,
			theme.dim, 0.7);

		paint.pushClip(left, top, width - gutter(), tall);

		final floor = y + height - metrics.gap;
		final room = tall - metrics.gap * 2 - font.height;
		final held = pattern.lane(session.part);
		final stalk = metrics.whole(3);

		paint.rect(left, floor, width - gutter(), metrics.whole(1), theme.frame);

		if (lane != VELOCITY) {
			laned(paint, theme, metrics, held, left, floor, room);
			paint.popClip();
			return;
		}

		for (note in held.notes) {
			final at = atTick(note.at);
			if (at < left - stalk || at > x + width) continue;

			final part = share(note);
			final reach = room * part;
			final colour = note == chosen ? theme.ink : theme.part(session.part.index());

			paint.rect(at, floor - reach, stalk, reach, colour, note == chosen ? 1 : 0.8);
		}

		paint.popClip();
	}

	function laned(paint:Paint, theme:Theme, metrics:Metrics, held:mdd.song.Lane, left:Float,
			floor:Float, room:Float):Void {
		final want = lane == PAN ? mdd.song.Automation.SIDES : mdd.song.Automation.LEVEL;
		final colour = theme.part(session.part.index());
		final hair = metrics.whole(2);

		var lines = 0;

		for (line in held.automation) {
			if (line.target != want || line.points.length == 0) continue;

			lines++;

			var last = -1.0;
			var lastAt = 0.0;

			for (point in line.points) {
				final at = atTick(point.at);
				if (at > x + width) break;

				final part = want == mdd.song.Automation.SIDES
					? sided(point.value) : 1 - (point.value & 0x7F) / 127.0;
				final level = floor - room * part;

				if (last >= 0 && at >= left) {
					paint.rect(lastAt < left ? left : lastAt, last, at - lastAt, hair,
						colour, 0.8);
					paint.rect(at, level < last ? level : last, hair,
						(level < last ? last - level : level - last) + hair, colour, 0.8);
				}

				last = level;
				lastAt = at;
			}

			if (last >= 0 && lastAt < x + width) {
				paint.rect(lastAt < left ? left : lastAt, last, x + width - lastAt, hair,
					colour, 0.8);
			}
		}

		if (lines > 0) return;

		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.LANE_EMPTY), left + metrics.gap,
			floor - room * 0.5 + font.ascent * 0.5, theme.dim, 0.6);
	}

	static function sided(value:Int):Float {
		return switch ((value >> 6) & 3) {
			case 1: 0.15;
			case 2: 0.85;
			case _: 0.5;
		}
	}

	function share(note:Note):Float {
		return switch (lane) {
			case PAN: 0.5;
			case AUTOMATION: 0;
			case _: note.velocity / 127.0;
		}
	}

	function laneName():String {
		return switch (lane) {
			case PAN: Locale.LANE_PAN;
			case AUTOMATION: Locale.LANE_AUTOMATION;
			case _: Locale.LANE_VELOCITY;
		}
	}

	public function edge():Float {
		final root = root();
		return root == null ? 6 : root.metrics.whole(6);
	}

	public function onEdge(note:Note, px:Float):Bool {
		final right = atTick(note.at + note.length);
		final reach = edge();

		return px >= right - reach && px <= right + reach;
	}

	public function resized(note:Note, to:Int):Void {
		final least = session.snap < 1 ? 1 : session.snap;
		var want = session.snapped(to) - note.at;

		if (want < least) want = least;
		if (want == note.length) return;

		note.length = want;
		drawn = want;

		final pattern = session.current();
		if (pattern != null) pattern.lane(session.part).grow(want);
	}

	function sliced(note:Note, at:Int):Void {
		if (at <= note.at || at >= note.at + note.length) return;

		final rest = new Note(at, note.at + note.length - at, note.pitch, note.velocity,
			note.instrument);

		note.length = at - note.at;
		session.does(new AddNote(session.pattern, session.part, rest));
		invalidate();
	}

	public inline function onStrip(py:Float):Bool {
		return lanes() > 0 && py >= y + height - lanes();
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
		if (stalking == null || lane != VELOCITY) return;

		final root = root();
		final metrics = root == null ? null : root.metrics;
		final gap = metrics == null ? 6.0 : metrics.gap;
		final font = metrics == null ? null : (metrics.small == null ? metrics.body
			: metrics.small);
		final head = font == null ? 11.0 : font.height;

		final floor = y + height - gap;
		final room = lanes() - gap * 2 - head;
		if (room <= 0) return;

		var part = (floor - py) / room;
		if (part < 0) part = 0;
		if (part > 1) part = 1;

		final want = Math.round(part * 127);
		if (want == stalking.velocity) return;

		stalking.velocity = want < 1 ? 1 : want;
		chosen = stalking;
		session.changed();
		invalidate();
	}

	public function showsLane(which:Int):Void {
		if (which < 0 || which >= LANES || which == lane) return;

		lane = which;
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

		var tick = Std.int(tickAt(left) / beat) * beat;
		if (tick < 0) tick = 0;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left) {
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

		for (note in lane.notes) {
			final at = atTick(note.at);
			final wide = note.length * perTick;

			if (at + wide < left || at > x + width) continue;

			final row = atPitch(seatOf(note));
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

			if (note == chosen) {
				paint.outline(at, row, wide, tall, theme.ink, metrics.whole(1), 0.9);
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

	public function lights(sounding:mdd.play.Sounding):Void {
		final which = session.part.index();
		final on = sounding.keyed[which];
		final note = on ? sounding.notes[which] : -1;

		if (note == litNote && on == litOn) return;

		litNote = note;
		litOn = on;
		invalidate();
	}

	static final NAMES:Array<String> = ["C", "C#", "D", "D#", "E", "F", "F#", "G",
		"G#", "A", "A#", "B"];

	public static function named(pitch:Int):String {
		final held = pitch < 0 ? 0 : pitch;
		return NAMES[held % 12] + (Std.int(held / 12) - 1);
	}

	function keys(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final wide = gutter();

		paint.rect(x, top, wide, grid(), theme.panel);
		paint.reface(metrics.small == null ? metrics.body : metrics.small);

		final font = metrics.small == null ? metrics.body : metrics.small;
		final drums = kitting();
		final floor = lowest();
		var pitch = highest();

		while (pitch >= floor) {
			final row = atPitch(pitch);

			if (row + rowTall >= top && row <= y + height) {
				final black = !drums && BLACK[pitch % 12];
				final lit = !drums && litOn && pitch == litNote;

				if (lit) {
					paint.rect(x, row, wide, rowTall - 1, theme.part(session.part.index()));
				} else if (drums) {
					paint.rect(x, row, wide, rowTall - 1, theme.raise1);
				} else {
					paint.rect(x, row, wide, rowTall - 1, black ? theme.sink : theme.ink,
						black ? 1 : 0.72);
				}

				if (rowTall >= font.height) {
					final rooted = !drums && pitch % 12 == 0;

					if (drums) {
						paint.text(seatName(pitch), x + metrics.unit * 2,
							row + (rowTall - font.height) * 0.5 + font.ascent, theme.ink, 0.9);
					} else {
						paint.textRight(named(pitch), x + wide - metrics.unit * 2,
							row + (rowTall - font.height) * 0.5 + font.ascent,
							black ? theme.dim : theme.sink, rooted ? 1 : 0.75);
					}
				}
			}

			pitch--;
		}

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

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left) {
				paint.text(Std.string(Std.int(tick / bar) + 1), at + metrics.unit,
					y + (tall - font.height) * 0.5 + font.ascent, theme.dim);
			}

			tick += bar;
		}

		paint.popClip();
		paint.rect(x, y + tall - metrics.whole(1), width, metrics.whole(1), theme.frame);
	}
}
