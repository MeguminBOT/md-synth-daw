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
	public var lane(default, null):Int = VELOCITY;

	var dragging:Null<Note> = null;
	var grabTick:Int = 0;
	var grabPitch:Int = 0;
	var panning:Bool = false;
	var menu:Null<Menu> = null;
	var panX:Float = 0;
	var panY:Float = 0;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
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
		return root == null ? 44 : root.metrics.whole(44);
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
		return HIGHEST - Std.int((py - y - ruler() + offsetY) / rowTall);
	}

	public inline function atPitch(pitch:Int):Float {
		return y + ruler() + (HIGHEST - pitch) * rowTall - offsetY;
	}

	public function contentWidth():Float {
		final pattern = session.current();
		return pattern == null ? 0 : pattern.length * perTick;
	}

	public function contentHeight():Float {
		return (HIGHEST - LOWEST + 1) * rowTall;
	}

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

	public function reveal(tick:Int, pitch:Int):Void {
		final wide = width - gutter();
		final tall = grid();

		scrollTo(tick * perTick - wide * 0.3, (HIGHEST - pitch) * rowTall - tall * 0.5);
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

	public function zoom(by:Float, around:Float):Void {
		final tick = tickAt(around);
		final want = perTick * by;

		perTick = want < 0.02 ? 0.02 : (want > 4 ? 4 : want);
		scrollTo(tick * perTick - (around - x - gutter()), offsetY);
	}

	override function took(event:Input):Bool {
		final pattern = session.current();
		if (pattern == null) return false;

		switch (event.kind) {
			case Kind.Wheel:
				if (event.ctrl()) {
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
					if (onAudition != null) onAudition(session.part, pitch);
					records(pitch);
					return true;
				}

				if (event.button == Pointer.Middle) {
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
					chosen = under;
					dragging = under;
					grabTick = tickAt(event.x) - under.at;
					grabPitch = pitchAt(event.y) - under.pitch;
					invalidate();
					return true;
				}

				final at = session.snapped(tickAt(event.x));
				final pitch = pitchAt(event.y);
				if (pitch < LOWEST || pitch > HIGHEST) return true;

				final note = new Note(at < 0 ? 0 : at, session.snap, pitch, 100);
				session.does(new AddNote(session.pattern, session.part, note));

				chosen = note;
				dragging = note;
				grabTick = 0;
				grabPitch = 0;

				if (onAudition != null) onAudition(session.part, pitch);

				invalidate();
				return true;

			case Kind.PointerMove:
				if (panning) {
					scrollTo(panX - event.x, panY - event.y);
					return true;
				}

				if (stalking != null) {
					leaned(event.y);
					return true;
				}

				if (dragging == null) return false;

				final at = session.snapped(tickAt(event.x) - grabTick);
				final pitch = pitchAt(event.y) - grabPitch;

				dragging.at = at < 0 ? 0 : at;
				dragging.pitch = pitch < LOWEST ? LOWEST : (pitch > HIGHEST ? HIGHEST : pitch);

				invalidate();
				return true;

			case Kind.PointerUp:
				if (panning) {
					panning = false;
					return true;
				}

				if (stalking != null) {
					stalking = null;
					return true;
				}

				if (dragging == null) return false;

				pattern.lane(session.part).sort();
				dragging = null;
				session.changed();
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
		final want = note.pitch + by;
		note.pitch = want < LOWEST ? LOWEST : (want > HIGHEST ? HIGHEST : want);

		session.say("moved to " + note.pitch);
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
		if (perTick < 0.02) perTick = 0.02;

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
				chosen.pitch = chosen.pitch < HIGHEST ? chosen.pitch + 1 : HIGHEST;
				invalidate();
				return true;

			case Key.Down:
				chosen.pitch = chosen.pitch > LOWEST ? chosen.pitch - 1 : LOWEST;
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
		var pitch = pitchAt(top);
		if (pitch > HIGHEST) pitch = HIGHEST;

		while (pitch >= LOWEST) {
			final row = atPitch(pitch);
			if (row > y + height) {
				pitch--;
				continue;
			}
			if (row + rowTall < top) break;

			final scale = session.scale;
			final lit = session.highlight && scale.kind != mdd.song.Scale.CHROMATIC;

			if (lit && scale.rooted(pitch)) {
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

			final row = atPitch(note.pitch);
			if (row + rowTall < y + ruler() || row > y + height) continue;

			painted++;

			final tall = rowTall - 1;

			if (ghost) {
				paint.roundedRect(at, row, wide, tall, radius, colour, 0.22);
				continue;
			}

			final unsound = budget != null && budget.troubled(note);

			paint.roundedRect(at, row, wide, tall, radius, colour, unsound ? 0.35 : 0.9);

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

	function keys(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final wide = gutter();

		paint.rect(x, top, wide, grid(), theme.panel);
		paint.reface(metrics.small == null ? metrics.body : metrics.small);

		final font = metrics.small == null ? metrics.body : metrics.small;
		var pitch = HIGHEST;

		while (pitch >= LOWEST) {
			final row = atPitch(pitch);

			if (row + rowTall >= top && row <= y + height) {
				final black = BLACK[pitch % 12];

				paint.rect(x, row, wide, rowTall - 1, black ? theme.sink : theme.ink,
					black ? 1 : 0.85);

				if (pitch % 12 == 0 && rowTall >= font.height) {
					paint.text("C" + (Std.int(pitch / 12) - 1), x + metrics.unit,
						row + (rowTall - font.height) * 0.5 + font.ascent, theme.dim);
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
