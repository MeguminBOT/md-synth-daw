package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.play.Render;
import mdd.play.Stream;
import mdd.play.Transport;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.view.Centre;
import mdd.view.editor.ChannelRack;
import mdd.view.Status;
import mdd.view.Inspector;
import mdd.view.editor.PianoRoll;
import mdd.app.Session;
import mdd.view.editor.Tracker;
import mdd.view.TransportBar;

@:unreflective
class SpineCheck {
	static inline final RATE = 48000;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  spine");

		played();
		blocks();
		looping();
		ending();
		drawn(args.length > 0 ? args[0] : Gate.root);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function sized(roll:mdd.view.editor.PianoRoll, session:mdd.app.Session):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		while (lane.notes.length > 0) lane.notes.pop();

		final note = new mdd.song.Note(0, session.snap, 60, 100);
		lane.add(note);

		final was = note.length;
		roll.resized(note, session.snap * 6);

		says("a note takes the length it is dragged to", note.length == session.snap * 6
			&& note.length != was,
			"a note of " + was + " ticks became " + note.length + " when its end was pulled");

		roll.resized(note, -500);

		says("and never shorter than the grid", note.length == session.snap,
			"pulling the end back past the start left " + note.length + " ticks, one snap");

		note.length = session.snap * 4;
		final right = roll.atTick(note.at + note.length);

		says("and its end is what the pointer grabs", roll.onEdge(note, right)
			&& !roll.onEdge(note, right - roll.edge() * 4),
			"the last few pixels of a note resize it and the middle of it does not");
	}

	static function menued(tree:Root):Void {
		final one = new mdd.ui.control.Menu();
		final two = new mdd.ui.control.Menu();

		for (index in 0...3) one.offer(new mdd.ui.control.Choice("one " + index));
		for (index in 0...3) two.offer(new mdd.ui.control.Choice("two " + index));

		tree.pop(one, 100, 100);
		says("a menu opens", tree.opened() == 1, tree.opened() + " menu up");

		tree.pop(two, 300, 300);
		says("and a second menu closes the first", tree.opened() == 1,
			tree.opened() + " menu up after opening another, not " + tree.popups.length);

		tree.pressed(900, 700, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("and a press outside closes it", tree.opened() == 0,
			tree.opened() + " menus up after pressing away from it");

		while (tree.popups.length > 0) tree.shut(tree.popups[0]);
	}

	static var strayed:String = "";

	static function inside(held:mdd.ui.Widget, said:String):Int {
		var out = 0;

		for (child in held.children) {
			if (!child.visible) continue;
			if (child.width <= 0 || child.height <= 0) continue;

			final name = said + " > " + Type.getClassName(Type.getClass(child)).split(".").pop();

			final over = Math.max(Math.max(held.x - child.x, held.y - child.y),
				Math.max(child.x + child.width - held.x - held.width,
					child.y + child.height - held.y - held.height));

			if (over > 0.51) {
				out++;

				if (strayed == "") {
					strayed = name + " by " + Math.round(over * 10) / 10 + " px";
				}
			}

			out += inside(child, name);
		}

		return out;
	}

	static function fitted(tree:Root):Void {
		strayed = "";

		final out = inside(tree.top, "shell");

		says("nothing is drawn outside what holds it", out == 0,
			out + " widgets reach past the one that holds them"
			+ (strayed == "" ? "" : ", the first being " + strayed));
	}

	static var blurred:String = "";
	static var counted:Int = 0;

	static function between(held:mdd.ui.Widget, said:String):Void {
		for (child in held.children) {
			if (!child.visible) continue;
			if (child.width <= 0 || child.height <= 0) continue;

			final name = said + " > " + Type.getClassName(Type.getClass(child)).split(".").pop();

			final off = Math.max(Math.max(fraction(child.x), fraction(child.y)),
				Math.max(fraction(child.width), fraction(child.height)));

			if (off > 0.001) {
				counted++;

				if (blurred == "") {
					blurred = name + " at " + round(child.x, 2) + ", " + round(child.y, 2)
						+ " by " + round(child.width, 2) + " by " + round(child.height, 2);
				}
			}

			between(child, name);
		}
	}

	static inline function fraction(value:Float):Float {
		final part = value - Math.ffloor(value);
		return part > 0.5 ? 1 - part : part;
	}

	static function aligned(tree:Root):Void {
		blurred = "";
		counted = 0;

		between(tree.top, "shell");

		says("every widget lands on a pixel", counted == 0,
			counted + " widgets sit between pixels"
			+ (blurred == "" ? "" : ", the first being " + blurred));
	}

	static function laned(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;
		final held = mdd.view.Parameter.of(session.part);

		for (index in 0...held.length) {
			if (held[index].target != mdd.song.Automation.LEVEL) continue;

			roll.shows(index + 1);
			break;
		}

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		final before = stack.lineOf(0);

		says("a lane can be shown", stack.rows() == 1 && stack.wants() > 0
			&& before == null,
			"one lane on " + session.part.name() + ", " + Std.int(stack.wants())
			+ " px tall, with no line behind it yet");

		final at = stack.atTick(session.song.tempo.ppqn * 2);
		final top = stack.rowTop(0) + stack.rowHeight() * 0.25;

		stack.took(pressAt(at, top));

		final line = stack.lineOf(0);
		final many = line == null ? 0 : line.points.length;

		says("and a press in it puts a point down", many == 1 && stack.chosen != null,
			many + " point after one press, holding " + (stack.chosen == null ? "nothing"
			: "" + stack.chosen.value));

		final was = stack.chosen == null ? 0 : stack.chosen.value;

		final move = new mdd.ui.Input();
		move.pointer(mdd.ui.Kind.PointerMove, at, stack.rowTop(0) + stack.rowHeight() * 0.75,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(move);

		final now = stack.chosen == null ? was : stack.chosen.value;

		says("and dragging it changes what it holds", now != was,
			"the point read " + was + " and reads " + now + " after being dragged down");

		session.undo();
		session.undo();

		final after = stack.lineOf(0);

		traded(tree, roll);
		pointed(tree, session, roll);

		says("and both undo", after == null || after.points.length == 0,
			"the lane is back to " + (after == null ? "no line at all"
			: after.points.length + " points"));

		stack.hide(0);

		tree.reshape();
		tree.top.arrange(0, 0, tree.width, tree.height);
	}

	static function tagged(tree:Root, presets:mdd.view.editor.Presets,
			session:mdd.app.Session):Void {
		final held = session.song.instrumentAt(0);
		if (held == null) return;

		held.tags.push("brass");
		held.tags.push("lead");

		laid(tree);
		final every = presets.listed;

		presets.search.set("brass");
		laid(tree);

		final some = presets.listed;

		presets.search.set("nothingatall");
		laid(tree);

		final none = presets.listed;

		presets.search.set("");
		laid(tree);

		says("a search finds a preset by its tag", every > some && some > 0 && none == 0
			&& presets.listed == every,
			every + " presets listed, " + some + " matching the tag brass, " + none
			+ " matching nothing, and " + presets.listed + " again when the box is cleared");

		var noted = "";
		var said = "";
		var tags = 0;

		var down = presets.tree.y + 2;

		while (down < presets.tree.y + presets.tree.height) {
			final index = presets.tree.rowAt(down);
			final row = index < 0 ? null : presets.tree.shownAt(index);

			if (row != null && row.note != "") {
				noted = row.note;
				said = row.says;

				final move = new mdd.ui.Input();

				move.pointer(mdd.ui.Kind.PointerMove,
					presets.tree.x + presets.tree.width * 0.5, down,
					mdd.ui.Pointer.Left, mdd.ui.Mod.None);

				presets.tree.took(move);
				tags = said.split(", ").length;

				break;
			}

			down += 2;
		}

		says("a preset shows its tags and names them all", noted != "" && said != ""
			&& said.length >= noted.length && presets.tree.tip == said,
			"the row reads '" + noted + "' beside its name and the pointer over it offers "
			+ tags + " tags, '" + said + "'");

		final zones = mdd.view.editor.Presets.briefly(["Green Hill Zone", "GHZ",
			"Scrap Brain Zone", "SBZ", "Boss", "Credits"]);

		final plain = mdd.view.editor.Presets.briefly(["Boss", "Credits", "Title Screen"]);
		final none = mdd.view.editor.Presets.briefly([]);

		says("a game preset shows its zones and nothing else",
			zones == "GHZ SBZ" && plain == "Boss, Credits  +1" && none == "",
			"six tags across two zones read '" + zones + "', three with no zone read '"
			+ plain + "', and none reads nothing");

		says("and a tag survives a project", tagsKeep(session),
			"written and read back with " + held.tags.length + " tags");

		var lifted = 0;
		for (one in session.song.instruments) if (one.tags.length > 0) lifted++;

		presets.search.set("Green Hill Zone");
		laid(tree);

		final narrowed = presets.listed;

		presets.search.set("");
		laid(tree);

		says("the shipped bank is tagged by its track", lifted > 100 && narrowed > 0
			&& narrowed < lifted,
			lifted + " presets carry a tag, and " + narrowed
			+ " of them answer to Green Hill Zone");
	}

	static function tagsKeep(session:mdd.app.Session):Bool {
		final back = mdd.format.Project.read(mdd.format.Project.text(session.song));

		if (back == null || back.instruments.length == 0) return false;

		final one = back.instruments[0];
		return one.tags.length == 2 && one.tags[0] == "brass" && one.tags[1] == "lead";
	}

	static function tabbed(tree:Root, centre:mdd.view.Centre):Void {
		final session = centre.session;
		final pattern = session.current();

		if (pattern != null) {
			final lane = pattern.lane(session.part);

			for (target in [mdd.song.Automation.LEVEL, mdd.song.Automation.TUNE,
					mdd.song.Automation.SIDES, mdd.song.Automation.TIMBRE,
					mdd.song.Automation.ATTACK, mdd.song.Automation.DECAY,
					mdd.song.Automation.RELEASE]) {
				for (slot in 0...4) {
					final line = new mdd.song.Automation(target, slot);

					line.add(new mdd.song.Point(0, 0));
					line.add(new mdd.song.Point(session.song.tempo.ppqn, 12));

					lane.automation.push(line);
				}
			}
		}

		centre.show(mdd.view.Centre.AUTOMATION);
		centre.automation.stack.fills();

		laid(tree);

		final tab = centre.automation;
		final stack = tab.stack;
		final many = stack.rows();

		says("the automation tab opens every lane", many > 0,
			many + " lanes for " + tab.drivenPart().name() + ", "
			+ Math.round(stack.wants()) + " px of stack in " + Math.round(tab.height) + " px");

		final was = stack.heightOf(0);

		stack.folds(0);
		laid(tree);

		final shut = stack.heightOf(0);

		stack.folds(0);
		laid(tree);

		says("and a lane folds to its header", shut == stack.headTall()
			&& stack.heightOf(0) == was,
			"folded to " + Math.round(shut) + " px from " + Math.round(was)
			+ ", and back again");

		tab.scrollDown(10000);
		laid(tree);

		final most = stack.wants() - tab.height + tab.head() + tab.ruler();
		final held = tab.offsetDown;

		tab.scrollDown(0);
		laid(tree);

		says("and the stack scrolls when it overflows",
			most <= 0 || Math.abs(held - most) < 1.5,
			most <= 0 ? "every lane fits, so there is nothing to scroll"
				: "scrolled to " + Math.round(held) + " of " + Math.round(most));

		centre.show(mdd.view.Centre.ROLL);
		laid(tree);
	}

	static function laid(tree:Root):Void {
		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);
	}

	static function leaned(stack:mdd.view.editor.Lanes, from:Float, to:Float,
			fine:Bool):Int {
		final at = stack.atTick(0) + stack.width * 0.25;
		final mods = fine ? mdd.ui.Mod.Ctrl : mdd.ui.Mod.None;

		final press = new mdd.ui.Input();
		press.pointer(mdd.ui.Kind.PointerDown, at, from, mdd.ui.Pointer.Left, mods);
		stack.took(press);

		final was = stack.chosen == null ? 0 : stack.chosen.value;

		final move = new mdd.ui.Input();
		move.pointer(mdd.ui.Kind.PointerMove, at, to, mdd.ui.Pointer.Left, mods);
		stack.took(move);

		final now = stack.chosen == null ? was : stack.chosen.value;

		final lift = new mdd.ui.Input();
		lift.pointer(mdd.ui.Kind.PointerUp, at, to, mdd.ui.Pointer.Left, mods);
		stack.took(lift);

		return now - was;
	}

	static function fined(tree:Root, roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;

		laid(tree);

		final top = stack.plotTop(0) + stack.plotTall(0) * 0.2;
		final coarse = leaned(stack, top, top + 40, false);

		roll.session.undo();
		laid(tree);

		final fine = leaned(stack, top, top + 40, true);

		roll.session.undo();
		laid(tree);

		final want = Math.abs(coarse) * 0.125;
		final off = Math.abs(Math.abs(fine) - want);

		says("holding ctrl moves a point finely", coarse != 0 && off <= 2,
			"40 px moved the value " + coarse + " normally and " + fine
			+ " with ctrl held, against an eighth of " + Math.round(want));
	}

	static function pointed(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;

		laid(tree);

		final shown = stack.position.visible && stack.amount.visible;
		final one = mdd.view.Parameter.found(session.part, mdd.song.Automation.LEVEL, 0);

		says("a point brings up its own fields", shown && stack.chosen != null,
			shown ? "position, value, shape, bend and steps for "
				+ (one == null ? "?" : one.name) : "no fields for the selected point");

		if (stack.chosen == null || one == null) return;

		final snap = session.snap;
		final want = snap * 3 + 7;

		stack.position.set(want);
		laid(tree);

		says("a typed position ignores the grid", stack.chosen.at == want,
			"asked for tick " + want + " against a snap of " + snap + " and the point sits at "
			+ stack.chosen.at);

		stack.amount.set(one.low + 3);
		laid(tree);

		says("and a typed value is the register step", stack.chosen.value == one.low + 3,
			"asked for " + (one.low + 3) + " and the point reads " + stack.chosen.value
			+ ", which is " + one.said(stack.chosen.value));

		stack.shape.set(mdd.song.Automation.CURVE);
		stack.bend.set(40);
		laid(tree);

		says("and the shape is reachable without a menu",
			stack.chosen.shape == mdd.song.Automation.CURVE && stack.chosen.tension == 40,
			"shape " + stack.chosen.shape + " with a bend of " + stack.chosen.tension);

		session.undo();
		session.undo();
		session.undo();
		session.undo();

		laid(tree);
	}

	static function traded(tree:Root, roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;

		laid(tree);

		final was = stack.heightOf(0);
		final grid = roll.grid();

		final press = new mdd.ui.Input();
		press.pointer(mdd.ui.Kind.PointerDown, stack.x + stack.width * 0.5, stack.y,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(press);

		final drag = new mdd.ui.Input();
		drag.pointer(mdd.ui.Kind.PointerMove, stack.x + stack.width * 0.5, stack.y - 30,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(drag);

		final lift = new mdd.ui.Input();
		lift.pointer(mdd.ui.Kind.PointerUp, stack.x + stack.width * 0.5, stack.y - 30,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(lift);

		laid(tree);

		final now = stack.heightOf(0);
		final after = roll.grid();

		says("a lane takes room from the roll", Math.abs(now - was - 30) < 1.5
			&& Math.abs(grid - after - 30) < 1.5,
			"dragging the stack up 30 made the lane " + Math.round(now) + " px from "
			+ Math.round(was) + ", and the roll " + Math.round(after) + " from "
			+ Math.round(grid));

		fined(tree, roll);

		final back = new mdd.ui.Input();
		back.pointer(mdd.ui.Kind.PointerDown, stack.x + stack.width * 0.5, stack.y,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(back);

		final down = new mdd.ui.Input();
		down.pointer(mdd.ui.Kind.PointerMove, stack.x + stack.width * 0.5, stack.y + 300,
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(down);
		stack.took(lift);

		laid(tree);

		says("and it stops at a floor", stack.heightOf(0) == mdd.view.editor.Lanes.LEAST_ROW
			&& roll.grid() > 0,
			"dragged far down the lane holds at " + Math.round(stack.heightOf(0))
			+ " px and the roll keeps " + Math.round(roll.grid()));
	}

	static function sheeted(tree:Root, session:mdd.app.Session):Void {
		final held = new mdd.view.overlay.Preferences(session);

		held.speaks(["en-GB", "en-US"], "en-GB");
		tree.raise(held);
		held.arrive();

		final row = mdd.view.overlay.Preferences.THEME;
		final top = held.rowTop(row) + held.fieldTall() * 0.5;
		final at = held.fieldLeft() + held.fieldWide() * 0.5;

		final was = held.showing(row);

		tree.pressed(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("a press inside a sheet reaches it", tree.sheet == held && tree.popups.length == 1
			&& tree.popups[0].commands() == held.choices(row).length,
			"the sheet is still up and its dropdown offers "
			+ (tree.popups.length == 0 ? 0 : tree.popups[0].commands()) + " themes");

		if (tree.popups.length == 1) tree.popups[0].fire(was == 0 ? 1 : 0);

		says("and picking from it takes", held.showing(row) != was,
			"the theme moved from " + was + " to " + held.showing(row));

		final moved = held.showing(row);

		held.cancels();

		says("and cancel puts it back", held.showing(row) == was,
			"the theme was " + was + ", became " + moved + ", and reads " + held.showing(row)
			+ " after cancelling");

		held.shows(mdd.view.overlay.Preferences.FILES);

		says("a category shows its own rows", held.rowsIn().length == 5
			&& held.rowsIn()[0] == mdd.view.overlay.Preferences.KEEPING,
			"Files carries " + held.rowsIn().length + " rows, the first being autosave");

		held.shows(mdd.view.overlay.Preferences.LOOK);

		while (tree.popups.length > 0) tree.shut(tree.popups[0]);

		tree.pressed(held.x - 20, held.y - 20, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("and a press beside it closes it", tree.sheet == null,
			"a press on the scrim lowers the sheet");
	}

	static function dragged(tree:Root, roll:mdd.view.editor.PianoRoll, session:mdd.app.Session,
			centre:Centre, paint:Paint, renderer:cpp.Star<Canvas>):Void {
		centre.show(Centre.ROLL);
		session.uses(mdd.app.Session.SELECT);

		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		lane.notes.resize(0);

		final note = new mdd.song.Note(96, 48, 60, 100);
		lane.add(note);

		roll.reveal(96, 60);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final atX = roll.atTick(96) + roll.perTick * 12;
		final atY = roll.atPitch(60) + roll.rowTall * 0.5;

		tree.pressed(atX, atY, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.moved(atX + roll.perTick * 48, atY, mdd.ui.Mod.None);
		tree.released(atX + roll.perTick * 48, atY, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final moved = note.at;
		final back = session.undo();

		says("a dragged note can be taken back", moved != 96 && back && note.at == 96,
			"the note moved from 96 to " + moved + " and undo put it at " + note.at);

		final right = roll.atTick(note.at + note.length) - roll.edge() * 0.5;

		tree.pressed(right, atY, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.moved(right + roll.perTick * 96, atY, mdd.ui.Mod.None);
		tree.released(right + roll.perTick * 96, atY, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final grew = note.length;
		final undone = session.undo();

		says("and so can a stretched one", grew != 48 && undone && note.length == 48,
			"the note grew from 48 to " + grew + " and undo put it at " + note.length);

		lane.notes.resize(0);
	}

	static function median(times:haxe.ds.Vector<Float>, many:Int):Float {
		if (many <= 0) return 0;

		final held = new Array<Float>();
		for (index in 0...many) held.push(times[index]);

		held.sort(function(one:Float, two:Float):Int
			return one < two ? -1 : (one > two ? 1 : 0));

		return held[Std.int(many / 2)];
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function tipUnder(tree:Root, widget:mdd.ui.Widget, px:Float, py:Float):String {
		tree.moved(px, py, mdd.ui.Mod.None);
		tree.advance(1.0);

		return tree.tipUp ? widget.tip : "";
	}

	static function popUnder(tree:Root, widget:mdd.ui.Widget, px:Float, py:Float):Int {
		tree.dismiss();

		final event = new mdd.ui.Input();
		event.pointer(mdd.ui.Kind.PointerDown, px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		widget.took(event);

		return tree.popups.length == 0 ? 0 : tree.popups[0].commands();
	}

	static function pressAt(px:Float, py:Float):mdd.ui.Input {
		final event = new mdd.ui.Input();
		event.pointer(mdd.ui.Kind.PointerDown, px, py, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		return event;
	}

	static function drawn(root:String):Void {
		Native.ready();

		if (Sdl.init() == 0) {
			says("the spine draws", false, "SDL would not start: " + Sdl.error());
			return;
		}

		final face = root + "/vendor/fonts/Go-Regular.ttf";
		final monoFace = root + "/vendor/fonts/Go-Mono.ttf";

		if (!sys.FileSystem.exists(face)) {
			says("the spine draws", false, "no font at " + face);
			Sdl.quit();
			return;
		}

		final window = Sdl.createWindow("mdd gate spine", 1440, 900, 0, 0);
		final renderer = Sdl.createRenderer(window, 0);

		final body = Font.bake(renderer, face, 15);
		final small = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 14);

		if (body == null || small == null || mono == null) {
			says("the spine draws", false, "the fonts would not bake");
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			Sdl.quit();
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, small, mono, mono);

		final session = Session.started(mdd.song.Library.embedded());

		session.song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme());

		mdd.app.Languages.speak(tree.translation, "en-GB");

		tree.flow = mdd.ui.Flow.None;
		tree.resize(1440, 900);
		shell.fit(metrics);

		final bar = new TransportBar(session);
		final rack = new ChannelRack(session);
		final centre = new Centre(session);
		final roll = centre.roll;
		final editor = new Inspector(session);

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rack);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(editor);

		final dock = new Status(session, centre.warnings);
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());

		centre.warnings.budget = budget;
		shell.zone(Shell.STATUS).add(dock);

		session.onReveal = function(found:mdd.check.Diagnostic):Void {
			if (found.note == null) return;
			centre.show(Centre.ROLL);
			centre.roll.reveal(found.note.at, found.note.pitch);
			centre.roll.choose(found.note);
		};

		final pattern = session.current();
		pattern.length = 96 * 4 * 64;

		var seed = 0x51DE;
		var placed = 0;

		for (index in 0...6) {
			final part:Part = index;
			var at = index * 12;

			while (at < pattern.length - 48) {
				seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

				pattern.lane(part).add(new Note(at, 24 + (seed % 48), 40 + (seed >> 8) % 40,
					60 + (seed >> 4) % 60));

				placed++;
				at += 24 + (seed >> 12) % 72;
			}
		}

		final paint = Paint.on(renderer, body);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final rolls = 600;
		var worst = 0.0;
		var total = 0.0;
		var first = 0.0;
		var worstAt = 0;
		final times = new haxe.ds.Vector<Float>(rolls);

		centre.show(Centre.ROLL);
		var over = 0;
		var drawnNotes = 0;
		var calls = 0;

		for (frame in 0...rolls) {
			roll.scrollTo(frame * 6, roll.offsetY);
			roll.playhead = frame * 24;
			roll.invalidate();
			rack.invalidate();

			Draw.resetCalls();
			final began = Sdl.ticks();
			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final spent = Sdl.ticks() - began;

			final took = Draw.calls();
			if (took > calls) calls = took;
			if (roll.painted > drawnNotes) drawnNotes = roll.painted;

			if (frame == 0) first = spent;
			else {
				if (spent > worst) {
					worst = spent;
					worstAt = frame;
				}
				if (spent * 1000 > 16.67) over++;
			}

			times[frame] = spent;
			total += spent;
		}

		final mean = total / rolls * 1000;

		says("the spine draws", drawnNotes > 0 && calls > 0,
			placed + " notes on six channels, " + drawnNotes + " of them on screen, "
			+ calls + " draw calls a frame");

		centre.show(Centre.SCOPE);

		for (index in 0...6) {
			for (step in 0...mdd.view.monitor.Scope.SPAN) {
				centre.scope.feed(index, Math.sin(step * (index + 1) * 0.05) * (0.2 + index * 0.1));
			}
			centre.scope.sang(index, 48 + index * 5);
		}

		var scopeWorst = 0.0;
		final scopeTimes = new haxe.ds.Vector<Float>(120);

		for (frame in 0...120) {
			centre.scope.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			final began = Sdl.ticks();
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final took = Sdl.ticks() - began;

			scopeTimes[frame] = took;
			if (took > scopeWorst) scopeWorst = took;
		}

		says("a key row fits its name", roll.rowTall >= small.height,
			"a row of the gutter is " + round(roll.rowTall, 1) + " px against a name "
			+ round(small.height, 1) + " px tall, so every key can be labelled");

		final nested = paint.nesting();

		says("a frame puts back every clip it took", nested == 0,
			nested + " clips, transforms and veils left on the stacks after "
			+ rolls + " frames of the whole shell");

		final scopeMiddle = median(scopeTimes, 120) * 1000;

		says("the scope draws its lanes", centre.scope.painted == 6 && scopeMiddle < 16.67,
			centre.scope.painted + " lanes traced, median frame " + round(scopeMiddle, 3)
			+ " ms, worst " + round(scopeWorst * 1000, 3)
			+ " ms with the scope in the centre");

		centre.scope.shows(mdd.view.monitor.Scope.SPECTRUM);

		var bandWorst = 0.0;
		final bandTimes = new haxe.ds.Vector<Float>(120);

		for (frame in 0...120) {
			centre.scope.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			final began = Sdl.ticks();
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final took = Sdl.ticks() - began;

			bandTimes[frame] = took;
			if (took > bandWorst) bandWorst = took;
		}

		final bandMiddle = median(bandTimes, 120) * 1000;

		says("and its spectrum", centre.scope.painted == 6 && bandMiddle < 16.67,
			centre.scope.painted + " lanes transformed, median frame " + round(bandMiddle, 3)
			+ " ms, worst " + round(bandWorst * 1000, 3)
			+ " ms over " + mdd.view.monitor.Scope.BARS + " bands of " + mdd.view.monitor.Scope.SPAN
			+ " samples");

		centre.scope.shows(mdd.view.monitor.Scope.WAVEFORM);

		editor.show(Inspector.PRESETS);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final fmListed = editor.presets.listed;
		final fmBanks = editor.presets.banks;

		session.choose(Part.Dac);
		editor.presets.fit();

		final dacListed = editor.presets.listed;

		session.choose(Part.Psg1);
		editor.presets.fit();

		final psgListed = editor.presets.listed;

		says("the bank holds every kind", fmListed == dacListed && fmListed == psgListed
			&& fmBanks == 4 && fmListed > 16,
			fmListed + " patches under " + fmBanks + " kinds, the same list whichever"
			+ " channel is chosen: " + fmListed + " on an fm part, " + dacListed
			+ " on the converter and " + psgListed + " on a square");

		session.choose(Part.Dac);
		editor.show(Inspector.CHANNEL);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final columns = editor.samples.painted;
		final was = session.song.samples[0].length();

		editor.samples.start = 100;
		editor.samples.ends = 400;
		editor.samples.trim();

		says("a sample is drawn and trimmed", columns > 100
			&& session.song.samples[0].length() == 300,
			columns + " columns of waveform, and trimming " + was + " bytes to the markers left "
			+ session.song.samples[0].length());

		session.choose(Part.Fm1);
		editor.show(Inspector.CHANNEL);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final fm = editor.fm;
		final patch = fm.patch();

		final level = fm.detailOf(patch, 3, 0);
		final spelt = fm.saying(patch, 3, 0);
		final at = fm.registerOf(3, 0);

		says("a parameter says what the chip sees", at == 0x4C
			&& StringTools.startsWith(spelt, "Total level")
			&& level.indexOf("$4C") >= 0 && level.indexOf("dB") >= 0,
			spelt + "   " + level);

		final rackTip = tipUnder(tree, rack, rack.x + 30, rack.y + 40);

		says("a channel says what it is", rackTip != "",
			"hovering the rack says " + rackTip);

		final menus = popUnder(tree, rack, rack.x + 30, rack.y + 40);

		says("a channel has a menu", menus > 0 && tree.popups.length == 1
			&& !tree.popups[0].crowded(),
			menus + " commands under the right button, of " + mdd.ui.control.Menu.CEILING
			+ " allowed, separators excluded");

		var fired = "";
		final before = session.song.muted[session.part.index()];

		tree.popups[0].fire(0);
		fired = session.said;

		says("and the menu does something", session.song.muted[session.part.index()] != before
			&& tree.popups.length == 0,
			"the first command said \"" + fired + "\" and closed the menu");

		sized(roll, session);
		dragged(tree, roll, session, centre, paint, renderer);

		centre.show(Centre.TRACKER);
		session.snap = 24;

		final tracker = centre.tracker;
		tracker.octave = 4;

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final grid = tracker.rows();
		final shown = tracker.painted;

		says("the tracker is the arrangement", grid == session.song.ends() / 24 && shown > 8,
			grid + " rows of " + Part.COUNT + " voices at a snap of 24 ticks, " + shown
			+ " of them on screen, covering the whole song");

		session.plays(true);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		says("and the pattern when the transport is on one",
			tracker.rows() == pattern.length / 24,
			tracker.rows() + " rows for a pattern of " + pattern.length + " ticks");

		session.plays(false);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final third = pattern.lane(Part.Fm3);
		third.notes.resize(0);

		tree.focusOn(tracker);
		tracker.at(4, Part.Fm3.index());

		tree.key(true, mdd.ui.Key.Z, mdd.ui.Mod.None);
		tree.key(true, mdd.ui.Key.S, mdd.ui.Mod.None);

		final written = tracker.noteAt(4, Part.Fm3.index());
		final next = tracker.noteAt(5, Part.Fm3.index());

		says("and a key writes a note", third.notes.length == 2 && written != null
			&& next != null && written.pitch == 60 && next.pitch == 61,
			"Z and S at octave 4 wrote " + (written == null ? "nothing" : Tracker.spelt(written.pitch))
			+ " and " + (next == null ? "nothing" : Tracker.spelt(next.pitch))
			+ ", each on its own row");

		tracker.at(4, Part.Fm3.index());
		tree.key(true, mdd.ui.Key.X, mdd.ui.Mod.None);

		final over = tracker.noteAt(4, Part.Fm3.index());

		says("and a cell holds one note", third.notes.length == 2 && over != null
			&& over.pitch == 62,
			"typing into a row that already sounds replaced it with "
			+ Tracker.spelt(over.pitch) + " rather than stacking on it");

		tracker.at(4, Part.Fm3.index());
		tree.key(true, mdd.ui.Key.Delete, mdd.ui.Mod.None);

		says("and delete takes it away", tracker.noteAt(4, Part.Fm3.index()) == null
			&& third.notes.length == 1,
			"the note under the cursor is gone and the one after it is not");

		final second = session.song.add(new mdd.song.Pattern("later", 384));
		final where = session.song.tracks[0];

		where.add(new mdd.song.Clip(session.song.patterns.length - 1, 384, 384));

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final row = Std.int((384 + 48) / tracker.step());

		tracker.at(row, Part.Fm4.index());
		tree.key(true, mdd.ui.Key.Z, mdd.ui.Mod.None);

		final placed = second.lane(Part.Fm4).notes;

		says("and a row past a clip writes inside it",
			placed.length == 1 && placed[0].at == 48,
			placed.length + " notes landed in the second clip's pattern"
			+ (placed.length == 0 ? "" : " at tick " + placed[0].at + " of a clip that starts"
			+ " at 384"));

		where.clips.pop();
		session.song.patterns.pop();

		says("and it is the roll's data", centre.roll.session == tracker.session,
			"the tracker and the roll read the same pattern, not a copy of it");

		centre.show(Centre.ROLL);
		session.snap = 24;

		final rollMenus = popUnder(tree, roll, roll.x + 200, roll.y + 120);

		says("the roll has a menu too", rollMenus > 0 && tree.popups.length == 1,
			rollMenus + " commands on the roll's background");

		tree.dismiss();

		pattern.lane(Part.Fm1).add(new Note(0, 384, 60, 100));
		pattern.lane(Part.Fm1).add(new Note(96, 192, 64, 100));
		pattern.lane(Part.Psg1).add(new Note(0, 96, 20, 100));

		budget.overSong(session.song);
		centre.warnings.fit();
		centre.show(mdd.view.Centre.WARNINGS);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final warned = budget.warnings();
		final linked = warned > 0 && budget.found[0].linked();

		centre.warnings.took(pressAt(centre.warnings.x + 10, centre.warnings.y + 10));

		says("a warning is a link", warned > 0 && linked
			&& session.part == budget.found[0].part
			&& roll.chosen == budget.found[0].note,
			warned + " warnings in the centre, and clicking the first one selected "
			+ session.part.name() + " and the note it names");

		final middle = median(times, rolls) * 1000;

		says("it holds sixty a second", middle < 16.67,
			"median " + round(middle, 3) + " ms a frame while scrolling, mean "
			+ round(mean, 3) + ", worst " + round(worst * 1000, 3) + " at frame " + worstAt
			+ ", " + over + " frames of " + rolls + " over 16.67, first frame "
			+ round(first * 1000, 1));

		menued(tree);
		fitted(tree);
		aligned(tree);
		laned(tree, session, centre.roll);
		tagged(tree, editor.presets, session);
		tabbed(tree, centre);
		sheeted(tree, session);

		tree.resize(900, 600);
		shell.fit(metrics);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final floor = rack.y + rack.height;
		final last = rack.atRow(Part.COUNT - 1) + rack.rowHeight();
		final tabs = centre.tabs;

		var strays = 0;

		for (field in bar.fields()) {
			if (!field.visible) continue;
			if (field.x + field.width <= bar.x + bar.width) continue;

			strays++;
		}

		says("a small window still holds every channel", last <= floor + 1 && strays == 0
			&& tabs.overflowed == 0,
			"at 900 by 600 the rack's last row ends at " + Math.round(last) + " against a panel"
			+ " floor of " + Math.round(floor) + ", " + strays + " transport fields fall outside"
			+ " the bar, and every editor is still reachable with " + tabs.overflowed
			+ " hidden of "
			+ tabs.labels.length);

		tree.resize(1440, 900);
		shell.fit(metrics);

		body.shut();
		small.shut();
		mono.shut();

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();
	}

	static function heard(song:Song, frames:Int, seconds:Float,
			into:Null<Vector<cpp.Float32>>):Int {
		final render = new Render(RATE, frames);
		final transport = new Transport(song, 65536);

		render.transport = transport;
		transport.rewind();
		transport.play();

		final want = Std.int(seconds * RATE);
		var done = 0;

		while (done < want) {
			final from = transport.advance(frames, RATE);
			final many = render.serve(transport.stream, from, frames, transport.entering, true);

			if (into != null) {
				for (i in 0...many) {
					if ((done + i) * 2 + 1 >= into.length) break;
					into[(done + i) * 2] = render.block[i * 2];
					into[(done + i) * 2 + 1] = render.block[i * 2 + 1];
				}
			}

			done += many;
		}

		return render.writes;
	}

	static function played():Void {
		final song = StreamCheck.written();
		final seconds = 2.0;

		final sound = new Vector<cpp.Float32>(Std.int(seconds * RATE) * 2);
		for (i in 0...sound.length) sound[i] = 0;

		final began = Sdl.ticks();
		final writes = heard(song, Render.BLOCK, seconds, sound);
		final spent = Sdl.ticks() - began;

		var loudest = 0.0;
		var moved = 0;

		for (i in 0...sound.length) {
			final value = sound[i] < 0 ? -sound[i] : sound[i];
			if (value > loudest) loudest = value;
			if (value > 0.0005) moved++;
		}

		says("the song sounds", loudest > 0.001,
			writes + " register writes reached the chips and the loudest sample is "
			+ round(loudest, 4));

		says("and keeps sounding", moved > sound.length / 4,
			round(100.0 * moved / sound.length, 1) + " per cent of the samples are away from zero");

		says("it plays ahead of time", spent < seconds,
			round(seconds, 1) + " s of song rendered in " + round(spent, 2) + " s, "
			+ round(seconds / spent, 1) + " times faster than real time");

		final offline = new Stream(262144);
		final sequencer = new mdd.play.Sequencer(song);
		sequencer.emit(offline, 0, Std.int(seconds * Tempo.TICKS));

		says("what is heard is exported", writes == offline.count,
			writes + " writes played against " + offline.count + " the same span exports");
	}

	static function blocks():Void {
		final song = StreamCheck.written();
		final seconds = 1.0;
		final length = Std.int(seconds * RATE) * 2;

		final small = new Vector<cpp.Float32>(length);
		final large = new Vector<cpp.Float32>(length);

		for (i in 0...length) {
			small[i] = 0;
			large[i] = 0;
		}

		heard(song, 128, seconds, small);
		heard(song, 512, seconds, large);

		var parted = -1;
		var worst = 0.0;

		for (i in 0...length) {
			final off = small[i] - large[i];
			final size = off < 0 ? -off : off;

			if (size > worst) worst = size;
			if (size != 0 && parted < 0) parted = i;
		}

		says("the block size is not heard", parted < 0,
			parted < 0 ? "128 and 512 frame blocks render the same "
				+ Std.int(length / 2) + " frames sample for sample"
				: "they part at sample " + Std.int(parted / 2) + ", worst " + round(worst, 6));
	}

	static function ending():Void {
		final song = new Song("an end", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		pattern.lane(Part.Fm1).add(new Note(0, 336, 60, 100));
		song.instrument(new mdd.song.Instrument("lead", Part.Fm1));
		song.rack[0] = 0;

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		final transport = new Transport(song, 8192);
		final render = new Render(RATE, Render.BLOCK);

		render.transport = transport;
		transport.rewind();
		transport.play();

		final bar = song.tempo.ppqn * 4;
		final want = song.tempo.samplesAt(384 + bar);
		final limit = Std.int(want * (RATE / Tempo.TICKS)) + RATE;

		var frames = 0;
		var stopped = -1;

		while (frames < limit) {
			final at = transport.advance(Render.BLOCK, RATE);
			render.serve(transport.stream, at, Render.BLOCK, transport.entering, true);

			frames += Render.BLOCK;
			if (stopped < 0 && !transport.playing) stopped = frames;
		}

		says("a song stops a bar after its last clip", stopped > 0,
			stopped < 0 ? "it never stopped in " + round(limit / RATE, 2) + " s"
			: "the transport stopped at " + round(stopped / RATE, 3) + " s, against "
			+ round(want / Tempo.TICKS, 3) + " s of song and a bar");

		var most = 0.0;

		for (block in 0...200) {
			final at = transport.advance(Render.BLOCK, RATE);
			final many = render.serve(transport.stream, at, Render.BLOCK, transport.entering, true);

			if (block < 40) continue;

			for (i in 0...many) {
				final value = render.block[i * 2];
				final size = value < 0 ? -value : value;
				if (size > most) most = size;
			}
		}

		says("and nothing is left ringing", most < 0.0005,
			"half a second of rendering past the end peaks at " + round(most, 6));
	}

	static function looping():Void {
		final song = new Song("a loop", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		pattern.lane(Part.Fm1).add(new Note(0, 48, 60, 100));
		song.instrument(new mdd.song.Instrument("lead", Part.Fm1));
		song.rack[0] = 0;

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		final transport = new Transport(song, 8192);
		transport.rewind();
		transport.loop(0, song.tempo.samplesAt(384));
		transport.play();

		var writes = 0;
		final want = song.tempo.samplesAt(384 * 3);
		final limit = Std.int(want * (RATE / Tempo.TICKS));
		var frames = 0;

		while (frames < limit) {
			transport.advance(128, RATE);
			writes += transport.stream.count;
			frames += 128;
		}

		says("a loop comes round", transport.wrapped >= 2 && writes > 0,
			"three bars of playing wrapped " + transport.wrapped
			+ " times and made " + writes + " writes");

		says("the playhead stays inside", transport.position >= transport.loopFrom
			&& transport.position <= transport.loopTo,
			"the playhead is at " + round(transport.position / Tempo.TICKS, 3)
			+ " s inside a " + round(transport.loopTo / Tempo.TICKS, 3) + " s loop");
	}
}
