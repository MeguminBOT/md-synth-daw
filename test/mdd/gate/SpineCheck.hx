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

		snapping();
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

	static function snapping():Void {
		final session = Session.started(mdd.song.Library.embedded());
		final song = session.song;

		session.snapping = Session.SIXTEENTH;

		final was = song.tempo.ppqn;
		final coarse = session.snap;
		final wantCoarse = Std.int(song.tempo.ppqn * 4 / Session.SIXTEENTH);

		song.retick(480);

		final fine = session.snap;
		final wantFine = Std.int(480 * 4 / Session.SIXTEENTH);

		says("the snap follows the piece it is in",
			coarse == wantCoarse && fine == wantFine,
			"a sixteenth is " + coarse + " ticks at " + was + " a beat and " + fine
			+ " at 480, rather than staying at " + coarse + " and meaning nothing");

		final step = session.snap;

		says("a placed note takes the step it was pointed at",
			session.begins(step + 1) == step
			&& session.begins(step * 2 - 1) == step,
			"a point anywhere inside a step of " + step
			+ " ticks lands on the tick that step begins at");

		says("and a moved one takes the nearest line",
			session.snapped(step * 2 - 1) == step * 2
			&& session.snapped(step + 1) == step,
			"which is what dragging something that already exists wants");

		session.snapping = 0;

		says("and no snap leaves a tick alone",
			session.snap == 0 && session.begins(7) == 7 && session.snapped(7) == 7,
			"a tick of 7 stays at 7");
	}

	static function restarted(tree:Root, session:Session,
			roll:mdd.view.editor.PianoRoll):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		lane.notes.resize(0);

		final beat = session.song.tempo.ppqn;
		lane.add(new Note(beat * 4, beat * 4, 60, 100));

		session.uses(Session.DRAW);
		session.history.clear();
		roll.shows(0);
		roll.choose(null);
		roll.reveal(beat * 4, 60);
		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		final note = lane.notes[0];
		final wasAt = note.at;
		final wasLong = note.length;
		final ends = wasAt + wasLong;

		final row = roll.atPitch(60) + roll.rowTall * 0.5;
		final start = roll.atTick(wasAt);

		says("a wide note has a handle on its start",
			roll.onStart(note, start) && !roll.onStart(note, roll.atTick(ends)),
			"its start answers and its end does not");

		tree.pressed(start, row, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.moved(roll.atTick(wasAt + beat), row, mdd.ui.Mod.None);
		tree.released(roll.atTick(wasAt + beat), row, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);

		final movedAt = note.at;
		final movedLong = note.length;
		final steps = session.history.depth();

		says("and dragging it moves the start and leaves the end",
			movedAt == wasAt + beat && movedAt + movedLong == ends,
			"the note begins at " + movedAt + " against " + wasAt
			+ " and still ends at " + (movedAt + movedLong));

		session.undo();

		says("and that undoes as one step",
			steps == 1 && note.at == wasAt && note.length == wasLong,
			"one step took the note back to " + note.at + " for " + note.length);

		lane.notes.resize(0);
		lane.add(new Note(0, 4, 60, 100));

		says("and a narrow one has none, so it can still be moved",
			!roll.onStart(lane.notes[0], roll.atTick(0)),
			"a note of 4 ticks answers nothing on its start");

		lane.notes.resize(0);
		session.history.clear();
	}

	/**
		Every view that shows a playhead has to ask for a frame when it moves, or
		the playhead only advances when something else happens to want one and it
		is seen to stutter.
	**/
	static function chased(tree:Root, session:Session, centre:mdd.view.Centre,
			paint:Paint, renderer:cpp.Star<Canvas>):Void {
		session.transport.play();

		final views = [mdd.view.Centre.PLAYLIST, mdd.view.Centre.ROLL,
			mdd.view.Centre.AUTOMATION];

		final names = ["the playlist", "the roll", "the automation editor"];

		var stuck = "";
		var asked = 0;

		for (index in 0...views.length) {
			centre.show(views[index]);
			tree.reshape();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);

			centre.playhead(session.song.tempo.ppqn * (index + 3));

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			final drew = tree.frame(paint);
			Sdl.renderPresent(renderer);

			if (drew) asked++;
			else stuck += names[index] + " ";
		}

		session.transport.stop();
		centre.show(mdd.view.Centre.ROLL);
		tree.reshape();

		says("every view redraws as the playhead moves", stuck == "",
			stuck == ""
				? asked + " of " + views.length + " asked for a frame of their own"
				: stuck + "waited for something else to want one");
	}

	static function budgeted(tree:Root, session:Session,
			budget:mdd.check.Budget, roll:mdd.view.editor.PianoRoll):Void {
		var notes = 0;
		for (pattern in session.song.patterns) {
			for (index in 0...Part.COUNT) notes += pattern.lane(index).notes.length;
		}

		budget.overSong(session.song);

		final began = Sdl.ticks();
		final rounds = 20;

		for (index in 0...rounds) budget.overSong(session.song);

		final each = (Sdl.ticks() - began) / rounds * 1000;

		says("reading the budget over a song is worth measuring", each >= 0,
			round(each, 3) + " ms over " + notes + " notes in "
			+ session.song.patterns.length + " patterns");

		session.choose(Part.Fm1);
		session.uses(Session.DRAW);

		final held = mdd.view.Parameter.of(session.part);

		for (index in 0...held.length) {
			if (held[index].target != mdd.song.Automation.LEVEL) continue;

			roll.shows(index + 1);
			break;
		}

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		final stack = roll.stack;

		says("an automation lane is up to drag on", stack.rows() > 0,
			"" + stack.rows() + " lane on " + session.part.name());

		if (stack.rows() == 0) return;

		final beat = session.song.tempo.ppqn;
		final top = stack.rowTop(0) + stack.rowHeight() * 0.5;
		final from = stack.atTick(beat * 2);

		stack.took(pressAt(from, top));

		var worst = 0.0;
		var spent = 0.0;
		final moves = 60;

		for (index in 0...moves) {
			final at = from + index * 3;
			final began = Sdl.ticks();

			stack.took(moveAt(at, top + (index % 7) - 3));

			final took = Sdl.ticks() - began;

			spent += took;
			if (took > worst) worst = took;
		}

		stack.took(releaseAt(from + moves * 3, top));

		says("and dragging automation does not stall the frame",
			worst * 1000 < 8,
			round(spent / moves * 1000, 3) + " ms a move over " + moves
			+ " moves, worst " + round(worst * 1000, 3)
			+ " ms, against a 16.7 ms frame");
	}

	static function racked(tree:Root, session:Session,
			rack:mdd.view.editor.ChannelRack):Void {
		session.history.clear();

		final at = Part.Fm1.index();
		final wasMuted = session.song.muted[at];
		final wasVolume = session.song.volume[at];

		final row = rack.atRow(at) + rack.rowHeight() * 0.5;
		final mute = rack.slotMiddle(mdd.view.editor.ChannelRack.MUTE);

		tree.pressed(mute, row, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(mute, row, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final muted = session.song.muted[at];
		session.undo();

		says("muting a channel undoes",
			muted != wasMuted && session.song.muted[at] == wasMuted,
			"the mute went on and undo took it back off");

		session.history.clear();
		final fader = rack.slotMiddle(mdd.view.editor.ChannelRack.METER);
		final along = fader + (wasVolume > 60 ? -14 : 14);

		tree.pressed(fader, row, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.moved(along, row, mdd.ui.Mod.None);
		tree.released(along, row, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final moved = session.song.volume[at];
		final steps = session.history.depth();

		session.undo();

		says("and a fader lands as one step",
			steps == 1 && moved != wasVolume
			&& session.song.volume[at] == wasVolume,
			"the volume went from " + wasVolume + " to " + moved + " in " + steps
			+ " step, and undo put " + session.song.volume[at] + " back");

		session.history.clear();
	}

	static function shaped(tree:Root, session:Session,
			roll:mdd.view.editor.PianoRoll):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		lane.notes.resize(0);

		final beat = session.song.tempo.ppqn;
		lane.add(new Note(beat, beat, 60, 100));

		session.uses(Session.DRAW);
		roll.reveal(beat, 60);
		tree.resize(tree.width, tree.height);

		final note = lane.notes[0];
		final row = roll.atPitch(60) + roll.rowTall * 0.5;
		final ends = roll.atTick(note.at + note.length);
		final middle = roll.atTick(note.at + Std.int(note.length / 2));

		final onEnd = roll.cursorAt(ends - 2, row);
		final onBody = roll.cursorAt(middle, row);

		says("the end of a note says it resizes",
			onEnd == mdd.host.Sdl.CURSOR_ACROSS
			&& onBody == mdd.host.Sdl.CURSOR_ARROW,
			"the cursor is a double arrow on the end and an arrow over the body");

		session.uses(Session.PAN);

		says("and the pan tool says it drags the view",
			roll.cursorAt(middle, row) == mdd.host.Sdl.CURSOR_MOVE,
			"with the pan tool in hand the whole roll answers the four pointed arrow");

		session.uses(Session.DRAW);

		lane.notes.resize(0);
		session.history.clear();
	}

	/**
		A name a preset carries, and a tag one carries, both find it.

		Asking for something nothing carries and getting nothing back only says the
		search reached the rows. It says nothing about whether a reader can find the
		sound they remember, which is the whole of what the search is for.

		@param tree The shell.
		@param browser The preset browser.
		@param session The piece.
		@param whole How many it lists with nothing typed.
	**/
	static function named(tree:Root, browser:mdd.view.editor.Presets,
			session:Session, whole:Int):Void {
		var word = "";
		var tag = "";

		for (index in 0...session.song.instruments.length) {
			final instrument = session.song.instrumentAt(index);
			if (instrument == null || !instrument.kind.fm()) continue;

			if (word == "" && instrument.name.length > 3) word = instrument.name;
			if (tag == "" && instrument.tags.length > 0) tag = instrument.tags[0];
		}

		typed(tree, browser, "");
		final allRows = browser.tree.rows();

		typed(tree, browser, word);
		final byName = browser.listed;
		final nameRows = browser.tree.rows();

		says("a name a preset carries finds it", byName > 0 && byName < whole,
			"\"" + word + "\" left " + byName + " of " + whole);

		says("and the rows on screen are the ones it left",
			nameRows > 0 && nameRows < allRows,
			nameRows + " rows shown against " + allRows + " with nothing typed");

		typed(tree, browser, tag);
		final byTag = browser.listed;

		says("and a tag one carries finds it", tag == "" || (byTag > 0 && byTag < whole),
			"\"" + tag + "\" left " + byTag + " of " + whole);

		typed(tree, browser, "");

		var folded = 0;

		for (row in 0...browser.tree.rows()) {
			final item = browser.tree.shownAt(row);
			if (item == null || item.children.length == 0) continue;

			browser.tree.fold(item, false);
			folded++;
		}

		says("a folded group hides the presets in it", leaves(browser) == 0,
			browser.tree.rows() + " rows and none of them a preset");

		typed(tree, browser, word);

		says("and a search opens it again to show what it found", leaves(browser) > 0,
			leaves(browser) + " presets on screen for \"" + word
			+ "\" with every group folded first");

		typed(tree, browser, "");

		typed(tree, browser, "");
	}

	/**
		Puts something in the search the way a reader would.

		@param tree The shell.
		@param browser The preset browser.
		@param said What to type.
	**/
	/**
		@param browser The preset browser.
		@return How many rows on screen are a preset rather than a heading, which is
			what a reader is looking for when they search.
	**/
	static function leaves(browser:mdd.view.editor.Presets):Int {
		var many = 0;

		for (row in 0...browser.tree.rows()) {
			final item = browser.tree.shownAt(row);
			if (item != null && item.children.length == 0) many++;
		}

		return many;
	}

	static function typed(tree:Root, browser:mdd.view.editor.Presets,
			said:String):Void {
		browser.search.set("");
		tree.focusOn(browser.search);

		if (said == "") {
			browser.fit();
			return;
		}

		tree.said(said, mdd.ui.Mod.None);
	}

	static function spared(tree:Root, centre:mdd.view.Centre, paint:Paint,
			renderer:cpp.Star<Canvas>):Void {
		final names = ["playlist", "roll", "tracker", "scope", "registers", "automation",
			"warnings"];

		final grew:Array<Int> = [];
		var worst = 0;
		var worstAt = 0;

		for (which in 0...mdd.view.Centre.TABS) {
			centre.show(which);
			tree.reshape();

			for (warm in 0...8) {
				tree.soil();
				Sdl.renderClear(renderer, 0, 0, 0, 1);
				tree.frame(paint);
				Sdl.renderPresent(renderer);
			}

			cpp.vm.Gc.run(true);
			cpp.vm.Gc.enable(false);

			final before = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);

			for (frame in 0...60) {
				tree.soil();
				Sdl.renderClear(renderer, 0, 0, 0, 1);
				tree.frame(paint);
				Sdl.renderPresent(renderer);
			}

			final took = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT) - before;
			cpp.vm.Gc.enable(true);

			final each = Math.round(took / 60);
			grew.push(each);

			if (each > worst) {
				worst = each;
				worstAt = which;
			}
		}

		final said:Array<String> = [];
		for (which in 0...grew.length) said.push(names[which] + " " + grew[which]);

		says("and every tab of the centre draws without allocating", worst == 0,
			worst == 0 ? "0 bytes a frame on all " + grew.length + " tabs"
				: names[worstAt] + " allocates " + worst + " bytes a frame: "
					+ said.join(", "));

		centre.show(mdd.view.Centre.PLAYLIST);
		tree.reshape();
	}

	/**
		An editing command reaches the editor in front even where nothing has the
		keyboard.

		Pressing anywhere that does not take the keyboard leaves nothing holding it,
		and an editing command walks up from whatever holds it. With nothing there it
		walked up from nothing and did nothing at all, silently, which reads as a
		shortcut that works sometimes and not others.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	/**
		The right button takes a note away while the pencil is out.

		Reaching for the rubber to take back the note just drawn is a tool change for
		one note, so the right button does it where the pencil is the tool, the way the
		playlist already takes a clip away. The menu is still what the right button
		does everywhere else, and holding shift or control still reaches it.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	/**
		The zoom on the roll is the reader's and the pattern does not bound it.

		The zoom used to stop where the pattern filled the view, so a short pattern could
		not be opened out and the end of a long one was a wall. It now runs between what
		a bar can be read at either way, and the view scrolls into room past the end.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	/**
		The three note tools, which act on the selection or on the whole lane.

		Quantise is the one an import needs: a driver writes a key on where its own timer
		put it, so the notes a register log gives back sit between the lines rather than on
		them. Legato and glue are checked beside it because all three are one group on the
		undo stack and all three have to come back off it.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	/**
		Presses and releases on the roll, which shift needs: a shift press is held until it
		is known whether the pointer moved, because moving clones what is under it.

		@param roll The roll.
		@param press An input to fill in, so a check is not allocating one a click.
		@param px Where to click, across.
		@param py Where to click, down.
		@param mod What is held down.
	**/
	static function clicked(roll:PianoRoll, press:mdd.ui.Input, px:Float, py:Float,
			mod:Int):Void {
		press.pointer(mdd.ui.Kind.PointerDown, px, py, mdd.ui.Pointer.Left, mod);
		roll.took(press);

		press.pointer(mdd.ui.Kind.PointerUp, px, py, mdd.ui.Pointer.Left, mod);
		roll.took(press);
	}

	/**
		Drags a pointer across a widget, stopping at each point on the way, which is what a
		sweep needs: a rubber and a velocity brush both act on what they pass rather than on
		where they end.

		@param widget What to drag across.
		@param stops Points to stop at, across and down in pairs. The first is the press.
		@param button Which button is down.
		@param mods What is held down.
	**/
	static function swept(widget:mdd.ui.Widget, stops:Array<Float>, button:Int,
			mods:mdd.ui.Mod):Void {
		if (stops.length < 4) return;

		final event = new mdd.ui.Input();

		event.pointer(mdd.ui.Kind.PointerDown, stops[0], stops[1], button, mods);
		widget.took(event);

		var index = 2;

		while (index + 1 < stops.length) {
			event.pointer(mdd.ui.Kind.PointerMove, stops[index], stops[index + 1], button, mods);
			widget.took(event);

			index += 2;
		}

		event.pointer(mdd.ui.Kind.PointerUp, stops[stops.length - 2],
			stops[stops.length - 1], button, mods);

		widget.took(event);
	}

	/**
		The three drags a note takes: the rubber sweeping, shift carrying a copy away, and
		the velocity strip painting what it passes.

		Each of the three has to leave one step on the undo stack rather than one a frame,
		which is the part a drag gets wrong, so the depth of the history is checked beside
		the notes every time.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	/**
		The keys that reach a note: duplicate, an octave and a lean.

		The menu already offered an octave and a lean and neither had a key, so a reader who
		knew what the entries did still had to go to the menu for them.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	static function chorded(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final roll = centre.roll;
		final lane = pattern.lane(session.part);
		final beat = session.song.tempo.ppqn;

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		final held = new mdd.app.Bindings();

		says("control and b is what duplicates",
			held.actionFor(mdd.ui.Key.B, mdd.ui.Mod.Ctrl) == mdd.app.Bindings.DOUBLE,
			"the chord reads " + held.shortcut(mdd.app.Bindings.DOUBLE));

		for (at in 0...2) lane.add(new Note(at * beat, Std.int(beat / 2), 60, 100));

		roll.picksAll();

		final was = lane.notes.length;
		final depth = session.history.depth();
		final reach = beat * 2;

		roll.edited(mdd.ui.Edit.DOUBLE);

		var laid = 0;
		for (note in lane.notes) if (note.at >= reach) laid++;

		says("and it lays the copy a rounded span after what it copied",
			lane.notes.length == was * 2 && laid == was
			&& session.history.depth() == depth + 1,
			was + " notes became " + lane.notes.length + ", " + laid + " of them at or past"
			+ " tick " + reach + ", which is the two beats a span of "
			+ Std.int(beat * 1.5) + " rounds up to, in "
			+ (session.history.depth() - depth) + " step of history");

		says("and the copy is what is selected, so pressing again lays a third",
			roll.picked.count == was,
			roll.picked.count + " notes selected, of the " + was + " just laid");

		session.history.undo(session.song);

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		for (at in 0...4) lane.add(new Note(at * beat, Std.int(beat / 2), 60, 100));

		roll.picksAll();
		roll.edited(mdd.ui.Edit.DOUBLE);

		var onBar = 0;
		for (note in lane.notes) if (note.at >= beat * 4) onBar++;

		var first = beat * 100;
		for (note in lane.notes) if (note.at >= beat * 4 && note.at < first) first = note.at;

		says("and a bar whose last hit falls short still copies onto the line",
			onBar == 4 && first == beat * 4,
			"a bar whose last hit ends at " + (beat * 3 + Std.int(beat / 2))
			+ " put its copy at " + first + " rather than early, with " + onBar
			+ " of 4 notes past the line");

		session.history.undo(session.song);

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		lane.add(new Note(0, Std.int(beat / 2), 60, 100));

		final only = lane.notes[0];
		roll.choose(only);

		roll.took(chord(mdd.ui.Key.Up, mdd.ui.Mod.Ctrl));
		final up = only.pitch;

		roll.took(chord(mdd.ui.Key.Down, mdd.ui.Mod.Ctrl));
		final down = only.pitch;

		says("control and an arrow moves a note by an octave", up == 72 && down == 60,
			"the note went from 60 to " + up + " and back to " + down);

		roll.took(chord(mdd.ui.Key.Up, mdd.ui.Mod.None));

		says("and an arrow on its own still moves it by a semitone", only.pitch == 61,
			"the note reads " + only.pitch + " against 61");

		roll.took(chord(mdd.ui.Key.Down, mdd.ui.Mod.None));

		final level = only.velocity;
		roll.took(chord(mdd.ui.Key.Up, mdd.ui.Mod.Shift));

		final louder = only.velocity;
		roll.took(chord(mdd.ui.Key.Down, mdd.ui.Mod.Shift));

		says("and shift and an arrow leans it", louder > level && only.velocity == level,
			"the velocity went from " + level + " to " + louder + " and back to "
			+ only.velocity);

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();
	}

	/**
		A video export draws the scope over the mix, a frame for every part of it.

		The frames are drawn into a texture the size of the video rather than into the window, so
		beyond counting them the check has to see the scope in them. The notes start a beat in, so
		the first frame is empty lanes and a frame from the middle has traces on it: both are decoded
		back where ffmpeg is on the path, and the pixels that changed between them are counted.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
		@param paint What the window is drawn with.
	**/
	static function filmed(tree:Root, session:Session, centre:mdd.view.Centre, paint:Paint):Void {
		final song = session.song;
		final pattern = session.current();
		if (pattern == null || song.tracks.length == 0) return;

		final beat = song.tempo.ppqn;
		final lane = pattern.lane(Part.Fm1);
		final track = song.tracks[0];

		lane.notes.resize(0);
		for (at in 1...4) lane.add(new Note(at * beat, beat, 60 + at * 4, 110));

		track.clips.resize(0);
		track.add(new mdd.song.Clip(session.pattern, 0, beat * 4));

		final mixing = new mdd.play.Mixing();

		mixing.kind = mdd.play.Mixing.WEBM;
		mixing.rate = 48000;
		mixing.size = 0;
		mixing.fps = 30;
		mixing.padEnd = 0;

		final made = mdd.play.Mixdown.of(song, mixing);

		final where = Gate.root + "/export/video";
		mdd.host.Paths.make(where);

		final path = where + "/scope.webm";
		if (sys.FileSystem.exists(path)) sys.FileSystem.deleteFile(path);

		final film = new mdd.app.Filming(tree, paint, tree.metrics, session, song, mixing, made,
			path);

		var rounds = 0;
		while (film.step(1.0) && rounds < 100000) rounds++;

		final wrong = film.finish();
		final counted = sys.FileSystem.exists(path) ? VideoCheck.framesIn(path) : -1;

		says("a video export draws a frame for all of the mix",
			wrong == "" && film.frames > 0 && film.done == film.frames && counted == film.frames,
			(wrong == "" ? "" : wrong + ", ") + film.done + " of " + film.frames + " frames drawn for "
			+ round(film.seconds(), 2) + " s of mix, " + counted + " in the file, " + film.size()
			+ " bytes");

		if (counted > 0 && VideoCheck.present("ffmpeg")) {
			final quiet = frameOf(path, 0, where + "/quiet.rgb");
			final middle = Std.int(counted / 2);
			final loud = frameOf(path, middle, where + "/loud.rgb");

			final pixels = mixing.wide() * mixing.tall();
			var moved = 0;

			if (quiet != null && loud != null && quiet.length == pixels * 3
					&& loud.length == pixels * 3) {
				for (index in 0...pixels) {
					var apart = 0;

					for (channel in 0...3) {
						final diff = loud.get(index * 3 + channel) - quiet.get(index * 3 + channel);
						apart += diff < 0 ? -diff : diff;
					}

					if (apart > 60) moved++;
				}
			}

			final share = moved / pixels;

			says("and the frames hold the scope tracing what sounds",
				quiet != null && loud != null && share > 0.001 && share < 0.5,
				"between the silent first frame and frame " + middle + ", " + moved + " of " + pixels
				+ " pixels changed, " + round(share * 100, 2) + " per cent");
		} else {
			Sys.println("    not run: ffmpeg is not on the path, so no frame of the video was decoded");
		}

		track.clips.resize(0);
		lane.notes.resize(0);
		session.history.clear();
	}

	/**
		Decodes one frame of a video back to raw RGB with ffmpeg.

		@param path The video.
		@param frame Which frame.
		@param into Where to write the pixels.
		@return The pixels, or null where ffmpeg would not decode it.
	**/
	static function frameOf(path:String, frame:Int, into:String):Null<haxe.io.Bytes> {
		if (sys.FileSystem.exists(into)) sys.FileSystem.deleteFile(into);

		final code = Sys.command("ffmpeg", ["-v", "error", "-y", "-i", path, "-vf",
			"trim=start_frame=" + frame + ":end_frame=" + (frame + 1), "-frames:v", "1", "-f",
			"rawvideo", "-pix_fmt", "rgb24", into]);

		return code == 0 && sys.FileSystem.exists(into) ? sys.io.File.getBytes(into) : null;
	}

	/**
		@param code Which key.
		@param mods What is held with it.
		@return An event for that chord being pressed.
	**/
	static function chord(code:mdd.ui.Key, mods:mdd.ui.Mod):mdd.ui.Input {
		final event = new mdd.ui.Input();
		event.keyed(mdd.ui.Kind.KeyDown, code, mods, false);

		return event;
	}

	static function swiped(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final roll = centre.roll;
		final lane = pattern.lane(session.part);
		final beat = session.song.tempo.ppqn;

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		for (at in 0...4) lane.add(new Note(at * beat, Std.int(beat / 2), 60, 100));

		roll.reveal(0, 60);
		tree.reshape();

		final row = roll.atPitch(60) + roll.rowTall * 0.5;
		final was = lane.notes.length;
		final depth = session.history.depth();

		session.tool = Session.DRAW;

		swept(roll, [roll.atTick(4) , row, roll.atTick(beat) + 4, row,
			roll.atTick(beat * 2) + 4, row, roll.atTick(beat * 3) + 4, row],
			mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("the rubber takes away every note it sweeps over, in one step",
			lane.notes.length == 0 && session.history.depth() == depth + 1,
			was + " notes became " + lane.notes.length + " across "
			+ (session.history.depth() - depth) + " step of history");

		session.history.undo(session.song);

		says("and one undo puts the whole sweep back", lane.notes.length == was,
			lane.notes.length + " notes again, of " + was);

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		lane.add(new Note(0, Std.int(beat / 2), 60, 100));

		final only = lane.notes[0];
		roll.choose(only);

		final held = session.history.depth();

		swept(roll, [roll.atTick(0) + 2, row, roll.atTick(beat) + 2, row],
			mdd.ui.Pointer.Left, mdd.ui.Mod.Shift);

		var stayed = false;
		var carried = -1;

		for (note in lane.notes) {
			if (note == only) stayed = note.at == 0;
			else carried = note.at;
		}

		says("shift carries a copy away and leaves the note behind",
			lane.notes.length == 2 && stayed && carried == beat
			&& session.history.depth() == held + 1,
			lane.notes.length + " notes, the one dragged from "
			+ (stayed ? "still at 0" : "moved") + " and the copy at " + carried + " of "
			+ beat + ", in " + (session.history.depth() - held) + " step of history");

		session.history.undo(session.song);

		says("and one undo takes the copy back off", lane.notes.length == 1,
			lane.notes.length + " notes after a single undo");

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		for (at in 0...4) lane.add(new Note(at * beat, Std.int(beat / 2), 60, 100));

		tree.reshape();

		final gap = tree.metrics.gap;
		final floor = roll.y + roll.height - roll.lanes() + roll.velocityTall() - gap;
		final room = roll.velocityTall() - roll.stripHead() - gap * 2;
		final strip = floor - room * 0.5;

		final before = session.history.depth();

		swept(roll, [roll.atTick(0), strip, roll.atTick(beat), strip,
			roll.atTick(beat * 2), strip, roll.atTick(beat * 3), strip],
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		var leant = 0;
		var apart = false;

		for (note in lane.notes) {
			if (note.velocity != 100) leant++;
			if (note.velocity != lane.notes[0].velocity) apart = true;
		}

		final painted = lane.notes[0].velocity;

		says("a drag across the strip paints every note it passes, in one step",
			leant == 4 && !apart && painted > 32 && painted < 96
			&& session.history.depth() == before + 1,
			leant + " of 4 notes left 100, all of them at " + painted
			+ (apart ? " but not the same" : "") + " against the 64 halfway up the strip, in "
			+ (session.history.depth() - before) + " step of history");

		session.history.undo(session.song);

		var back = 0;
		for (note in lane.notes) if (note.velocity == 100) back++;

		says("and one undo puts every velocity back", back == 4,
			back + " of 4 notes back at 100");

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();
		session.tool = Session.SELECT;
	}

	static function tooled(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final roll = centre.roll;
		final lane = pattern.lane(session.part);
		final step = session.snap;

		lane.notes.resize(0);
		roll.picked.clear();

		for (at in 0...4) lane.add(new Note(at * step * 2 + 5, 12, 60 + at, 100));

		final off = lane.notes.copy();
		var astray = 0;

		for (note in off) if (note.at % step != 0) astray++;

		roll.quantised();

		var landed = 0;
		for (note in off) if (note.at % step == 0) landed++;

		says("quantise pulls every note onto the grid", landed == off.length,
			astray + " of " + off.length + " notes sat between the lines and " + landed
			+ " sit on one after, with a grid of " + step + " ticks");

		session.history.undo(session.song);

		var back = 0;
		for (note in off) if (note.at % step != 0) back++;

		says("and one undo puts all of them back", back == astray,
			back + " notes are off the grid again, of the " + astray + " that were");

		session.history.redo(session.song);

		roll.stretched();

		var joined = 0;
		for (index in 0...off.length - 1) {
			if (off[index].ends() == off[index + 1].at) joined++;
		}

		says("legato stretches every note to the next", joined == off.length - 1,
			joined + " of " + (off.length - 1) + " notes reach the one after them, and the"
			+ " last still holds " + off[off.length - 1].length + " ticks");

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();

		lane.add(new Note(0, 96, 60, 100));
		lane.add(new Note(48, 96, 60, 100));
		lane.add(new Note(200, 48, 60, 100));
		lane.add(new Note(48, 96, 67, 100));

		final was = lane.notes.length;
		roll.glued();

		var covering = -1;
		var apart = 0;

		for (note in lane.notes) {
			if (note.pitch == 60 && note.at == 0) covering = note.length;
			if (note.pitch == 60 && note.at == 200) apart++;
			if (note.pitch == 67) apart++;
		}

		says("glue folds a run on one key into one and leaves the others",
			lane.notes.length == was - 1 && covering == 144 && apart == 2,
			was + " notes became " + lane.notes.length + ", the two that overlapped are one"
			+ " of " + covering + " ticks, and the note on another key and the one past the"
			+ " end are both still there");

		session.history.undo(session.song);

		says("and one undo puts the run back", lane.notes.length == was,
			lane.notes.length + " notes again, of " + was);

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();
	}

	static function zoomed(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final roll = centre.roll;
		final was = pattern.length;

		pattern.length = session.song.tempo.ppqn * 4;
		roll.perTick = 0.25;
		roll.scrollTo(0, roll.offsetY);

		final fits = (roll.width - roll.gutter()) / pattern.length;

		for (turn in 0...40) roll.zoom(0.8, roll.x + roll.gutter());
		final out = roll.perTick;

		says("a one bar pattern zooms out past what fills the view", out < fits,
			"a bar draws at " + round(out * pattern.length, 1) + " pixels where filling the"
			+ " view takes " + round(fits * pattern.length, 1));

		for (turn in 0...20) roll.zoom(0.8, roll.x + roll.gutter());

		says("and stops at a bound of its own rather than at the pattern",
			roll.perTick == out,
			"forty turns out and sixty both reach " + round(out, 5) + " pixels a tick");

		for (turn in 0...80) roll.zoom(1.25, roll.x + roll.gutter());
		final near = roll.perTick;

		says("and it zooms in far past what fills the view", near > fits,
			"a bar draws at " + round(near * pattern.length, 1) + " pixels");

		for (turn in 0...20) roll.zoom(1.25, roll.x + roll.gutter());

		says("and stops there too", roll.perTick == near,
			"eighty turns in and a hundred both reach " + round(near, 3)
			+ " pixels a tick");

		roll.perTick = 0.25;
		roll.scrollTo(1 << 20, roll.offsetY);

		final end = roll.atTick(pattern.length);
		final edge = roll.x + roll.width;

		says("and the view scrolls into room past the end of the pattern", end < edge,
			"the end of the pattern sits " + round(edge - end, 1)
			+ " pixels from the right of the view at the furthest it scrolls");

		final tall = roll.rowTall;
		final middle = roll.y + roll.ruler() + roll.grid() * 0.5;
		final pitch = roll.pitchAt(middle);

		for (turn in 0...20) roll.heightens(roll.rowTall * 1.15, middle);
		final grown = roll.rowTall;

		says("a row grows and the key under the pointer stays where it was",
			grown > tall && Math.abs(roll.pitchAt(middle) - pitch) <= 1,
			"a row went from " + round(tall, 1) + " to " + round(grown, 1)
			+ " pixels and key " + pitch + " is now key " + roll.pitchAt(middle));

		for (turn in 0...40) roll.heightens(roll.rowTall * 0.87, middle);

		says("and it stops where the name written on it still fits",
			round(roll.rowTall, 3) == round(roll.rowLeast(), 3),
			"a row bottoms out at " + round(roll.rowTall, 1) + " pixels against the "
			+ round(roll.rowLeast(), 1) + " a name needs");

		pattern.length = was;
		roll.rowTall = tall;
		roll.perTick = 0.25;
		roll.scrollTo(0, roll.offsetY);
	}

	static function rubbed(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final roll = centre.roll;
		final lane = pattern.lane(session.part);

		lane.notes.resize(0);
		for (at in 0...3) lane.add(new Note(at * 96, 96, 60, 100));

		roll.reveal(96, 60);
		tree.reshape();

		final was = lane.notes.length;
		final note = lane.notes[1];

		final px = roll.atTick(note.at) + 4;
		final py = roll.atPitch(note.pitch) + roll.rowTall * 0.5;

		session.tool = Session.DRAW;

		tree.pressed(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.released(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("the right button takes a note away while the pencil is out",
			lane.notes.length == was - 1 && lane.notes.indexOf(note) < 0,
			was + " notes before and " + lane.notes.length + " after");

		session.does(new mdd.song.edit.AddNote(session.pattern, session.part,
			new Note(96, 96, 60, 100)));

		final back = lane.notes.length;
		session.tool = Session.SELECT;

		final other = lane.notes[1];
		final ox = roll.atTick(other.at) + 4;
		final oy = roll.atPitch(other.pitch) + roll.rowTall * 0.5;

		tree.pressed(ox, oy, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.released(ox, oy, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("and leaves it alone with any other tool", lane.notes.length == back,
			back + " notes before and " + lane.notes.length + " after, so the menu is"
			+ " still what the right button does");

		tree.dismiss();
		lane.notes.resize(0);
		session.tool = Session.SELECT;
		session.history.clear();
	}

	static function commanded(tree:Root, session:Session, centre:mdd.view.Centre):Void {
		centre.show(mdd.view.Centre.ROLL);
		session.choose(Part.Fm1);
		tree.resize(tree.width, tree.height);

		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		lane.notes.resize(0);

		for (at in 0...4) lane.add(new Note(at * 96, 96, 60 + at, 100));

		final roll = centre.roll;

		tree.focusOn(roll);
		roll.picked.clear();

		final withFocus = tree.edits(mdd.ui.Edit.ALL) ? roll.picked.count : -1;

		says("select all reaches the editor holding the keyboard", withFocus == 4,
			withFocus + " of " + lane.notes.length + " notes chosen");

		tree.focusOn(null);
		roll.picked.clear();

		final walked = tree.edits(mdd.ui.Edit.ALL);

		says("and nothing holds it after pressing where nothing takes it",
			!walked && roll.picked.count == 0,
			"walking up from the keyboard finds nothing to take it, which is why the"
				+ " editor in front is asked next");

		final editor = centre.editing();
		final loose = editor != null && editor.edited(mdd.ui.Edit.ALL)
			? roll.picked.count : -1;

		says("and it reaches the editor in front with nothing holding it", loose == 4,
			loose < 0 ? "nothing took it, so the shortcut did nothing at all"
				: loose + " of " + lane.notes.length + " notes chosen");

		lane.notes.resize(0);
		roll.picked.clear();
		session.history.clear();
	}

	/**
		Typing in the preset search narrows what the browser lists.

		The rows are built by `fit`, and what is typed is only read while they are
		built. A search that does not build them again leaves whatever was listed
		before on screen, which reads as a search that does nothing at all.

		@param tree The shell.
		@param session The piece.
		@param editor The inspector the browser sits in.
	**/
	static function sought(tree:Root, session:Session,
			editor:mdd.view.Inspector):Void {
		final missing = "zzqqxx";

		session.choose(Part.Fm1);
		editor.show(mdd.view.Inspector.PRESETS);
		tree.resize(tree.width, tree.height);

		final browser = editor.presets;
		final whole = browser.listed;

		says("the preset browser lists what the piece carries", whole > 0,
			whole + " presets over " + browser.banks + " banks");

		tree.focusOn(browser.search);
		tree.said(missing, mdd.ui.Mod.None);

		final none = browser.listed;

		says("and a name nothing carries leaves none of them",
			none == 0 && browser.search.value == missing,
			none == whole ? "what was typed never reached the rows"
				: none + " left of " + whole);

		browser.search.set("");
		browser.fit();

		says("and clearing it puts them back", browser.listed == whole,
			browser.listed + " listed again against " + whole);

		named(tree, browser, session, whole);

		final began = Sdl.ticks();
		for (round in 0...20) browser.fit();
		final each = (Sdl.ticks() - began) * 1000 / 20;

		says("and building them again is cheap enough to do per keystroke",
			each < 4,
			round(each, 3) + " ms to build " + whole + " presets over "
				+ browser.banks + " banks, against 16.67 in a frame");
	}

	static function synthed(tree:Root, session:Session,
			editor:mdd.view.Inspector):Void {
		session.choose(Part.Fm1);
		editor.show(mdd.view.Inspector.CHANNEL);
		tree.resize(tree.width, tree.height);

		final fm = editor.fm;
		final patch = fm.patch();

		if (patch == null || fm.width <= 0) {
			says("an operator edit undoes", false, "the fm editor is not up");
			return;
		}

		session.history.clear();

		final slot = 0;
		final row = 1;
		final was = fm.valueOf(patch, slot, row);

		final wide = fm.width / mdd.song.Patch.SLOTS;
		final middle = fm.rowMiddle(row);
		final left = fm.x + slot * wide;

		tree.pressed(left + 4, middle, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.moved(left + wide * 0.8, middle, mdd.ui.Mod.None);
		tree.released(left + wide * 0.8, middle, mdd.ui.Pointer.Right,
			mdd.ui.Mod.None);

		says("a right button never edits a patch",
			fm.valueOf(patch, slot, row) == was && session.history.depth() == 0,
			"the field is still " + was + " after a right drag across it");

		tree.pressed(left + 4, middle, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.moved(left + wide * 0.8, middle, mdd.ui.Mod.None);

		final during = fm.valueOf(patch, slot, row);

		tree.released(left + wide * 0.8, middle, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);

		final after = fm.valueOf(patch, slot, row);

		says("an operator bar follows the pointer", during != was && after == during,
			"a drag across the bar took it from " + was + " to " + after
			+ ", and the release left it there");

		final steps = session.history.depth();
		session.undo();

		says("and the whole drag undoes as one step",
			steps == 1 && fm.valueOf(patch, slot, row) == was,
			"the drag left " + steps + " step on the stack and undo put " + was
			+ " back");

		session.history.clear();

		final fresh = new mdd.song.Patch().reads(slot, row);
		patch.writes(slot, row, fresh == 0 ? 9 : 0);

		tree.pressed(left + 4, middle, mdd.ui.Pointer.Left, mdd.ui.Mod.None, 2);
		tree.released(left + 4, middle, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("and a double click puts a field back where a fresh patch has it",
			fm.valueOf(patch, slot, row) == fresh && session.history.depth() == 1,
			"the field reads " + fm.valueOf(patch, slot, row) + " against the " + fresh
			+ " a new patch carries, in one step");

		session.history.clear();
		session.choose(Part.Psg1);
		editor.show(mdd.view.Inspector.CHANNEL);
		tree.resize(tree.width, tree.height);

		final psg = editor.psg;
		final envelope = psg.envelope();

		if (envelope == null || psg.width <= 0) {
			says("an envelope stroke undoes", false, "the square editor is not up");
			return;
		}

		final before = envelope.steps.copy();
		final band = psg.y + psg.height * 0.5;
		final step = psg.width / mdd.song.Envelope.LENGTH;

		tree.pressed(psg.x + step * 2.5, band, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		for (index in 3...9) {
			tree.moved(psg.x + step * (index + 0.5), band, mdd.ui.Mod.None);
		}

		tree.released(psg.x + step * 8.5, band, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final drawnSteps = session.history.depth();
		final wrote = envelope.steps.copy();

		var moved = wrote.length != before.length;
		if (!moved) {
			for (index in 0...wrote.length) {
				if (wrote[index] != before[index]) moved = true;
			}
		}

		session.undo();

		var back = envelope.steps.length == before.length;
		if (back) {
			for (index in 0...before.length) {
				if (envelope.steps[index] != before[index]) back = false;
			}
		}

		says("an envelope stroke undoes as one step",
			drawnSteps == 1 && moved && back,
			"a stroke over 7 steps left " + drawnSteps + " step on the stack, wrote "
			+ wrote.length + " steps against " + before.length
			+ " before it, and undo put them all back");

		session.history.clear();
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

		lengthy(roll, session);
	}

	static function lengthy(roll:mdd.view.editor.PianoRoll,
			session:mdd.app.Session):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);
		final beat = session.song.tempo.ppqn;
		final wasSnap = session.snapping;

		lane.notes.resize(0);
		roll.forgets();

		session.snapping = 4;
		session.uses(mdd.app.Session.DRAW);

		roll.draws(0, 60);

		final first = lane.notes.length == 0 ? 0 : lane.notes[0].length;

		says("a drawn note takes the grid", first == session.snap,
			"drawn at a snap of " + session.snap + " ticks, the note is " + first + " long");

		session.snapping = 32;
		roll.draws(beat * 4, 62);

		final tight = lane.notes.length < 2 ? 0 : lane.notes[1].length;

		says("and never comes out shorter than a sixteenth",
			tight == roll.sixteenth() && session.snap < tight,
			"at a snap of " + session.snap + " ticks the note is still " + tight
			+ ", a sixteenth of " + beat);

		roll.resized(lane.notes[1], lane.notes[1].at + beat * 2);
		roll.draws(beat * 8, 64);

		final next = lane.notes.length < 3 ? 0 : lane.notes[2].length;

		says("and the next one takes the length the last was given",
			next == beat * 2 && lane.notes.length == 3,
			"after one was pulled to " + (beat * 2) + " ticks the next drawn note is "
			+ next);

		session.snapping = 1;
		roll.draws(beat * 12, 65);

		final moved = lane.notes.length < 4 ? 0 : lane.notes[3].length;

		says("and moving the grid takes the length back to it", moved == beat * 4
			&& moved != next,
			"the grid moved to " + session.snap + " ticks and the next drawn note is "
			+ moved + " rather than the " + next + " the one before it kept");

		session.snapping = wasSnap;
		lane.notes.resize(0);
		roll.forgets();
	}

	static function wasted(litter:Array<haxe.ds.Vector<Float>>, many:Int):Void {
		for (round in 0...many) litter.push(new haxe.ds.Vector<Float>(16));
		litter.resize(0);
	}

	static function collected():Void {
		final held = new mdd.host.Collector();
		final litter:Array<haxe.ds.Vector<Float>> = [];

		wasted(litter, 40000);

		held.rests(1.0, false);

		says("a collector left alone does nothing", held.swept == 0,
			held.swept + " sweeps before it was asked to mind the heap");

		held.minds();
		held.sweeps(true);

		final settled = held.swept;

		wasted(litter, 260000);

		held.rests(1.0, true);

		says("and it leaves a busy frame alone", held.swept == settled,
			Math.round(held.loose() / 1048576) + " mb of garbage and "
			+ (held.swept - settled) + " sweeps while the frame was drawing");

		held.rests(1.0, false);

		says("and sweeps once the frame goes quiet", held.swept == settled + 1
			&& held.loose() < mdd.host.Collector.ROUSE,
			"one quiet frame swept it down to "
			+ Math.round(held.loose() / 1048576) + " mb");

		final before = held.swept;

		wasted(litter, 900000);

		held.rests(0.0, true);

		says("and past a ceiling it sweeps whatever the frame is doing",
			held.swept == before + 1 && held.forced == 1,
			"a busy frame with " + Math.round(mdd.host.Collector.CEILING / 1048576)
			+ " mb behind it was swept anyway, " + held.forced + " forced");

		held.leaves();
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

		session.uses(mdd.app.Session.DRAW);

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
		final depth = session.history.depth();
		final floor = stack.rowTop(0) + stack.rowHeight() * 0.75;

		for (step in 0...24) {
			final move = new mdd.ui.Input();
			move.pointer(mdd.ui.Kind.PointerMove, at,
				top + (floor - top) * (step + 1) / 24, mdd.ui.Pointer.Left,
				mdd.ui.Mod.None);

			stack.took(move);
		}

		final now = stack.chosen == null ? was : stack.chosen.value;

		says("and dragging it changes what it holds", now != was,
			"the point read " + was + " and reads " + now + " after being dragged down");

		final lift = new mdd.ui.Input();
		lift.pointer(mdd.ui.Kind.PointerUp, at, floor, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(lift);

		says("and dragging one just drawn adds no step of its own",
			session.history.depth() == depth,
			"24 moves after the press that made it added "
			+ (session.history.depth() - depth) + " steps, so undoing the press takes the"
			+ " point away wherever it was dragged to");

		final again = session.history.depth();
		stack.took(pressAt(at, floor));

		for (step in 0...24) {
			final move = new mdd.ui.Input();
			move.pointer(mdd.ui.Kind.PointerMove, at,
				floor + (top - floor) * (step + 1) / 24, mdd.ui.Pointer.Left,
				mdd.ui.Mod.None);

			stack.took(move);
		}

		final during = session.history.depth() - again;

		final up = new mdd.ui.Input();
		up.pointer(mdd.ui.Kind.PointerUp, at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		stack.took(up);

		says("and moving it again is one step too", during == 0
			&& session.history.depth() == again + 1,
			"24 pointer moves added " + during + " steps while dragging and "
			+ (session.history.depth() - again) + " once the button came up");

		session.undo();

		session.undo();
		session.undo();

		final after = stack.lineOf(0);

		traded(tree, roll);
		pointed(tree, session, roll);
		ranged(tree, session, roll);

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

		sorted(tree, presets, session);

		says("a game preset shows its zones and nothing else",
			zones == "GHZ SBZ" && plain == "Boss, Credits  +1" && none == "",
			"six tags across two zones read '" + zones + "', three with no zone read '"
			+ plain + "', and none reads nothing");

		final table = new mdd.app.Bindings();

		final wasUndo = table.shortcut(mdd.app.Bindings.UNDO);
		final wasDraw = table.shortcut(mdd.app.Bindings.DRAW);

		final found = table.actionFor(mdd.ui.Key.Z, mdd.ui.Mod.Ctrl);
		final none = table.actionFor(mdd.ui.Key.Q, mdd.ui.Mod.None);

		says("a shortcut finds what it is bound to", wasUndo == "Ctrl+Z" && wasDraw == "P"
			&& found == mdd.app.Bindings.UNDO && none == mdd.app.Bindings.NONE,
			"undo reads '" + wasUndo + "' and draw '" + wasDraw + "', Ctrl+Z finds undo and"
			+ " an unbound key finds nothing");

		table.binds(mdd.app.Bindings.UNDO, mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt);

		final spelt = table.shortcut(mdd.app.Bindings.UNDO);
		final moved = table.actionFor(mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt);
		final gone = table.actionFor(mdd.ui.Key.Z, mdd.ui.Mod.Ctrl);

		final written = table.said();

		final other = new mdd.app.Bindings();
		other.reads(written);

		says("a shortcut can be moved and is remembered",
			spelt == "Ctrl+Alt+B" && moved == mdd.app.Bindings.UNDO
			&& gone == mdd.app.Bindings.NONE
			&& other.shortcut(mdd.app.Bindings.UNDO) == "Ctrl+Alt+B"
			&& other.shortcut(mdd.app.Bindings.DRAW) == wasDraw,
			"undo moved to '" + spelt + "', the old shortcut finds nothing, and '" + written
			+ "' brings it back with the rest left alone");

		table.binds(mdd.app.Bindings.DRAW, mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt);

		says("and taking a shortcut leaves the other without one",
			table.shortcut(mdd.app.Bindings.UNDO) == ""
			&& table.actionFor(mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt)
				== mdd.app.Bindings.DRAW,
			"draw took Ctrl+Alt+B and undo was left with nothing rather than a second owner");

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

	/**
		Every tab of the centre draws a frame without allocating.

		The shell is measured on the playlist alone, and the tabs that are not it draw
		different widgets: the register timeline, the scope, the automation editor and
		the warning list. A string built while painting is an allocation a frame, which
		is what makes the collector run, and the collector is the longest stall there
		is.

		@param tree The shell.
		@param centre The tabs.
		@param paint What to draw with.
		@param renderer What to draw into.
	**/
	static function tabbed(tree:Root, centre:mdd.view.Centre, paint:Paint,
			renderer:cpp.Star<Canvas>):Void {
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

		var worst = 0.0;
		final times = new haxe.ds.Vector<Float>(120);

		for (frame in 0...120) {
			stack.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			final began = Sdl.ticks();
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final took = Sdl.ticks() - began;

			times[frame] = took;
			if (took > worst) worst = took;
		}

		final middle = median(times, 120) * 1000;

		says("and it draws every one of them inside a frame", middle < 16.67,
			many + " lanes traced, median frame " + round(middle, 3) + " ms, worst "
			+ round(worst * 1000, 3) + " ms");

		cpp.vm.Gc.run(true);
		cpp.vm.Gc.enable(false);

		final before = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);

		for (frame in 0...120) {
			stack.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);
		}

		final grew = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT) - before;
		cpp.vm.Gc.enable(true);

		says("and every one of them allocates nothing", grew == 0,
			Math.round(grew / 120) + " bytes a frame with " + many
			+ " lanes open, measured from a swept heap");

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

		final was = stack.height;

		tab.zoom(4, tab.x + tab.width * 0.5);
		laid(tree);

		final floor = tab.y + tab.height - tab.reinTall() * 0.5;
		final started = tab.offsetX;

		tree.pressed(tab.x + tab.width - 4, floor, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(tab.x + tab.width - 4, floor, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("the automation tab scrolls sideways on a bar of its own",
			tab.across() && tab.onRein(tab.x + tab.width - 4, floor)
			&& tab.offsetX > started && stack.height < was,
			"zoomed in, the bar reaches " + Math.round(tab.span() * tab.perTick)
			+ " px across " + Math.round(tab.width - tab.gutter())
			+ ", a press at its right end moved the view from " + Math.round(started)
			+ " to " + Math.round(tab.offsetX) + ", and the lanes gave up "
			+ Math.round(was - stack.height) + " px for it");

		tab.zoom(0.001, tab.x + tab.width * 0.5);
		laid(tree);

		says("and the bar goes when everything fits", !tab.across()
			&& stack.height == was,
			"zoomed back out the bar is gone and the lanes have their "
			+ Math.round(stack.height) + " px again");

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

	/**
		What the right hand button does to a clip, which is a preference because it is a
		habit rather than a rule.

		Removing outright is what this has always done and is what stays; opening the menu
		is what every other sequencer does with that button, and somebody arriving from one
		will have taken a clip off the playlist before working out why.
	**/
	static function buttoned(tree:Root, session:mdd.app.Session, centre:Centre):Void {
		centre.show(Centre.PLAYLIST);

		final list = centre.playlist;
		final track = session.song.tracks[0];

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		track.clips.resize(0);
		track.add(new mdd.song.Clip(0, 0, 384));

		final px = list.atTick(192);
		final py = list.atTrack(0) + (list.atTrack(1) - list.atTrack(0)) * 0.5;

		says("a clip is where the pointer says", list.clipAt(px, py) != null,
			"the clip on the first row covers the point the presses are aimed at");

		session.rightClick = mdd.app.Session.DELETES;

		tree.pressed(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.released(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("removing a clip is the default", track.clips.length == 0
			&& tree.popups.length == 0,
			"the clip is gone and no menu was opened");

		session.undo();
		session.rightClick = mdd.app.Session.OPENS;

		tree.pressed(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.released(px, py, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("and opens the menu where asked", track.clips.length == 1
			&& tree.popups.length == 1,
			"the clip is still there and a menu of "
			+ (tree.popups.length == 0 ? 0 : tree.popups[0].commands()) + " is open on it");

		while (tree.popups.length > 0) tree.shut(tree.popups[0]);

		session.rightClick = mdd.app.Session.DELETES;
		track.clips.resize(0);
		session.history.clear();
	}

	/**
		A lane's values zoom under the wheel over its scale.

		A frequency lane spans four thousand steps and a vibrato swings a dozen of them, which drew as
		a flat line with nothing to change it. The scale beside a lane now zooms and moves what the
		lane shows, a double click fits it to its points, and a point is added at the value drawn where
		the press was rather than at the value the whole range would have put there.
	**/
	static function ranged(tree:Root, session:mdd.app.Session, roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;

		session.uses(mdd.app.Session.DRAW);
		laid(tree);

		final held = stack.parameterOf(0);
		if (stack.rows() == 0 || held == null) return;

		final low = stack.lowOf(0);
		final high = stack.highOf(0);
		final scale = stack.x + stack.left * 0.5;
		final middle = stack.plotTop(0) + stack.plotTall(0) * 0.5;

		for (turn in 0...2) {
			final wheel = new mdd.ui.Input();
			wheel.turned(scale, middle, 0, 1, mdd.ui.Mod.None);
			stack.took(wheel);
		}

		final shown = stack.highOf(0) - stack.lowOf(0);
		final centred = Math.abs((stack.lowOf(0) + stack.highOf(0)) - (low + high)) <= 2;

		says("a lane zooms under the wheel",
			stack.zoomed(0) && Math.abs(shown * 4 - (high - low)) <= 4 && centred,
			"two turns over the scale show " + stack.lowOf(0) + " to " + stack.highOf(0) + " of "
			+ low + " to " + high + ", around the value that was under the pointer");

		final from = stack.lowOf(0);

		stack.took(pressAt(scale, middle));
		stack.took(moveAt(scale, middle + stack.plotTall(0) * 0.25));
		stack.took(releaseAt(scale, middle + stack.plotTall(0) * 0.25));

		final moved = stack.lowOf(0) - from;

		says("and dragging the scale moves them", moved != 0
			&& stack.highOf(0) - stack.lowOf(0) == shown,
			"a quarter of the lane down moved what it shows by " + moved + " and kept " + shown
			+ " values in view");

		final top = held.attenuates() ? stack.lowOf(0) : stack.highOf(0);
		final across = stack.atTick(session.song.tempo.ppqn * 7);
		final depth = session.history.depth();

		stack.took(pressAt(across, stack.plotTop(0) + 1));
		stack.took(releaseAt(across, stack.plotTop(0) + 1));

		final added = session.history.depth() > depth && stack.chosen != null;
		final value = added ? stack.chosen.value : 0;

		says("and a point takes the value drawn", added && value == top,
			added ? "pressed at the top of the zoomed lane, the point holds " + value
				+ " where the lane shows " + top + " and the whole range would have given "
				+ (held.attenuates() ? low : high)
				: "no point was added");

		final twice = new mdd.ui.Input();
		twice.pointer(mdd.ui.Kind.PointerDown, scale, middle, mdd.ui.Pointer.Left, mdd.ui.Mod.None, 2);

		stack.took(twice);
		stack.took(releaseAt(scale, middle));

		final fitted = stack.zoomed(0) && stack.lowOf(0) <= value && stack.highOf(0) >= value
			&& stack.highOf(0) - stack.lowOf(0) < high - low;
		final fitLow = stack.lowOf(0);
		final fitHigh = stack.highOf(0);

		stack.took(twice);
		stack.took(releaseAt(scale, middle));

		says("and a double click fits the points",
			fitted && !stack.zoomed(0) && stack.lowOf(0) == low && stack.highOf(0) == high,
			"fitted to " + fitLow + " to " + fitHigh + " around the point at " + value
			+ ", then back to " + stack.lowOf(0) + " to " + stack.highOf(0));

		if (added) session.undo();
		stack.unzooms(0);
	}

	/**
		A double click on a pattern clip opens its pattern in the roll, and the roll measures its ruler
		and scrubbing from where that clip sits in the song.

		The editors measured from the start of the song whatever clip a pattern was opened from, so a
		pattern placed at bar fifty three was drawn at bar one, and scrubbing it moved the song there.
	**/
	static function reopened(tree:Root, session:mdd.app.Session, centre:Centre):Void {
		centre.show(Centre.PLAYLIST);
		laid(tree);

		final list = centre.playlist;
		final tracks = session.song.tracks;
		final track = tracks[0];
		final kept = [for (each in tracks) each.clips.copy()];
		final bar = session.song.tempo.ppqn * 4;
		final was = session.pattern;

		for (each in tracks) each.clips.resize(0);
		final clip = track.add(new mdd.song.Clip(0, bar * 2, bar));

		laid(tree);

		final px = list.atTick(bar * 2 + Std.int(bar / 2));
		final py = list.atTrack(0) + (list.atTrack(1) - list.atTrack(0)) * 0.5;

		tree.pressed(px, py, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(px, py, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.pressed(px, py, mdd.ui.Pointer.Left, mdd.ui.Mod.None, 2);
		tree.released(px, py, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("a double click opens a pattern", centre.showing == Centre.ROLL
			&& session.opened == clip && session.pattern == clip.pattern,
			"the roll is " + (centre.showing == Centre.ROLL ? "" : "not ") + "showing, on pattern "
			+ (session.pattern + 1) + " from the clip at bar 3");

		laid(tree);

		centre.playhead(0);
		final roll = centre.roll;
		final origin = roll.origin;

		roll.scrubbed(roll.atTick(Std.int(bar / 4)));
		final landed = session.transport.tick();

		says("and it scrubs where the clip sits", origin == bar * 2 && landed >= bar * 2
			&& landed < bar * 3,
			"the roll measures from tick " + origin + " and scrubbing its first beat moved the song to "
			+ landed + ", inside the clip at " + clip.at);

		session.transport.seek(0);
		session.opened = null;
		session.chooses(was);

		for (index in 0...tracks.length) {
			tracks[index].clips.resize(0);
			for (held in kept[index]) tracks[index].add(held);
		}

		centre.show(Centre.PLAYLIST);
		laid(tree);
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
			&& tree.popups[0].commands() == held.counted(row),
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

		final wanted = #if mac 5 #else 6 #end;

		says("a category shows its own rows", held.rowsIn().length == wanted
			&& held.rowsIn()[0] == mdd.view.overlay.Preferences.KEEPING,
			"Files carries " + held.rowsIn().length + " rows, the first being autosave");

		final clicking = mdd.view.overlay.Preferences.RIGHT_CLICK;
		final wasClicking = session.rightClick;

		held.chose(clicking, mdd.app.Session.OPENS);

		says("a preference reaches its reader",
			session.rightClick == mdd.app.Session.OPENS
			&& held.holding(clicking) == mdd.app.Session.OPENS,
			"the row and the session agree that the right button opens a clip's menu");

		held.chose(clicking, wasClicking);

		final monitor = mdd.view.overlay.Preferences.HOST_MONITOR;
		final wasMonitor = held.holding(monitor);

		held.chose(monitor, mdd.App.MONITOR_EVERYTHING);
		final everything = held.holding(monitor);

		held.chose(monitor, mdd.App.MONITOR_OFF);
		final off = held.holding(monitor);

		held.chose(monitor, wasMonitor);

		says("the monitor row shows its choice",
			everything == mdd.App.MONITOR_EVERYTHING && off == mdd.App.MONITOR_OFF,
			"it reads " + everything + " and " + off + " back rather than the language's place in"
			+ " its own list");

		while (tree.popups.length > 0) tree.shut(tree.popups[0]);

		rebound(tree, held);
		mapped(tree, held);

		held.shows(mdd.view.overlay.Preferences.LOOK);
		tree.pressed(held.x - 20, held.y - 20, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(held.x - 20, held.y - 20, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);

		says("and a press beside it leaves it up", tree.sheet == held,
			"a sheet holding settings is not lost to a press a pixel beside it");

		tree.key(true, mdd.ui.Key.Escape, mdd.ui.Mod.None);

		says("and escape still closes it", tree.sheet == null,
			"escape is what closes a sheet that a press outside will not");

		final loose = new mdd.view.overlay.Naming();

		tree.raise(loose);
		tree.reshape();
		tree.pressed(4, 4, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(4, 4, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("and a sheet that is not modal still goes", tree.sheet == null,
			"the naming sheet closes on a press beside it as it always did");
	}

	static function mapped(tree:Root, held:mdd.view.overlay.Preferences):Void {
		final fresh = new mdd.app.Mapping();
		fresh.plain();

		final turns:Array<String> = [];

		for (slot in 0...mdd.app.Mapping.SLOTS) {
			if (!fresh.bound(slot)) continue;
			turns.push(fresh.controlOf(slot) + " to " + fresh.named(slot));
		}

		says("a keyboard arrives with something to turn",
			turns.length == mdd.app.Mapping.SLOTS,
			turns.length + " of " + mdd.app.Mapping.SLOTS + " slots are bound before anything"
			+ " has been saved: " + turns.join(", "));

		final mapping = new mdd.app.Mapping();
		final patch = new mdd.song.Patch();

		mapping.drives(0, mdd.app.Mapping.OPERATOR, 3, 0);
		mapping.hears(0, 74);

		final full = mapping.turns(patch, 0, 127);
		final half = mapping.turns(patch, 0, 64);
		final none = mapping.turns(patch, 0, 0);

		says("a control turns the field it is aimed at",
			full == 127 && half == 64 && none == 0 && patch.totalLevel[3] == 0,
			"a control at 127, 64 and 0 sets a total level of " + full + ", " + half
			+ " and " + none + ", where the field runs to " + mdd.song.Patch.mostOf(0));

		mapping.drives(1, mdd.app.Mapping.DIAL, 0, mdd.song.Patch.FEEDBACK);
		mapping.hears(1, 71);

		final turned = mapping.turns(patch, 1, 127);

		says("and a dial takes its own range", turned == 7 && patch.feedback == 7,
			"a control at 127 sets a feedback of " + turned + " where the dial runs to 7");

		mapping.hears(1, 74);

		says("and a control only drives one thing",
			mapping.slotFor(74) == 1 && !mapping.bound(0),
			"control 74 moved to the second slot and the first was left with "
			+ (mapping.bound(0) ? "one anyway" : "nothing"));

		final wrote = mapping.said();
		final other = new mdd.app.Mapping();

		other.reads(wrote);

		says("and a mapping is remembered", other.said() == wrote
			&& other.named(1) == mapping.named(1),
			"'" + wrote + "' reads back to the same, holding " + other.named(1));

		held.mapping = mapping;
		held.arrive();
		held.shows(mdd.view.overlay.Preferences.MIDI);

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		final row = held.rowsIn().length + 2;
		final top = held.y + held.head() + (row + 0.5) * held.rowTall();
		final at = held.fieldLeft() + held.fieldWide() * 0.5;

		says("a control row sits under the device rows", held.slotAt(top) == 2,
			"the row at that height is control " + (held.slotAt(top) + 1));

		held.listens(2);

		says("and it waits for one to be turned", held.learning == 2,
			"the third row is listening");

		final took = held.hears(20);

		says("and takes the next control that moves", took && mapping.slotFor(20) == 2
			&& held.learning < 0,
			"control 20 landed on slot " + (mapping.slotFor(20) + 1)
			+ " and the row stopped listening");

		held.cancels();

		says("and cancel gives the mapping back", mapping.said() == wrote,
			"the mapping reads '" + mapping.said() + "' again");

		tree.raise(held);
		held.arrive();
	}

	static function rebound(tree:Root, held:mdd.view.overlay.Preferences):Void {
		final bindings = new mdd.app.Bindings();

		held.bindings = bindings;
		held.arrive();
		held.shows(mdd.view.overlay.Preferences.KEYBOARD);

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		final action = mdd.app.Bindings.REDO;
		final was = bindings.shortcut(action);
		final top = held.y + held.head() + (action + 0.5) * held.rowTall();
		final at = held.fieldLeft() + held.fieldWide() * 0.5;

		tree.pressed(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("a shortcut row waits for a key", held.catching == action
			&& held.bindAt(top) == action,
			"the row for '" + tree.translate(mdd.app.Bindings.NAMES[action])
			+ "' is listening, reading " + was);

		tree.key(true, mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt);

		says("and the key it catches becomes the shortcut",
			bindings.shortcut(action) == "Ctrl+Alt+B" && held.catching < 0
			&& bindings.actionFor(mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt) == action,
			"'" + was + "' became '" + bindings.shortcut(action)
			+ "' and the table answers to it");

		tree.pressed(at, top, mdd.ui.Pointer.Right, mdd.ui.Mod.None);
		tree.released(at, top, mdd.ui.Pointer.Right, mdd.ui.Mod.None);

		says("and a right click puts the default back",
			bindings.shortcut(action) == was && held.catching < 0,
			"the row reads " + bindings.shortcut(action) + " again");

		tree.pressed(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.released(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		tree.key(true, mdd.ui.Key.B, mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt);

		final moved = bindings.shortcut(action);
		held.cancels();

		says("and cancel gives every shortcut back", bindings.shortcut(action) == was
			&& bindings.said() == "",
			"the row read " + moved + " and reads " + bindings.shortcut(action)
			+ " after cancelling, with nothing left over settings would keep");

		final most = held.content() - held.room();
		held.scrollTo(most);

		final last = mdd.app.Bindings.COUNT - 1;
		final floor = held.y + held.head() + held.room() - held.rowTall() * 0.5;

		says("and the list scrolls to the last shortcut",
			most > 0 && held.bindAt(floor) == last,
			mdd.app.Bindings.COUNT + " shortcuts in room for "
			+ Math.round(held.room() / held.rowTall()) + ", and the bottom row is "
			+ tree.translate(mdd.app.Bindings.NAMES[held.bindAt(floor) < 0 ? 0
				: held.bindAt(floor)]));

		held.scrollTo(0);

		tree.raise(held);
		held.arrive();
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

	static function noted(many:Int):String {
		return many + (many == 1 ? " note" : " notes");
	}

	static function wrote(tree:Root, widget:mdd.ui.Widget, said:String):Void {
		for (index in 0...said.length) {
			final event = new mdd.ui.Input();
			event.typed(said.charAt(index), mdd.ui.Mod.None);

			widget.took(event);
		}
	}

	static function entered(tree:Root, tracker:Tracker, lane:mdd.song.Lane):Void {
		says("a note spelt out reads as one",
			Tracker.pitched("C-4") == 60 && Tracker.pitched("C#4") == 61
			&& Tracker.pitched("Db4") == 61 && Tracker.pitched("c4") == 60
			&& Tracker.pitched("B-3") == 59 && Tracker.pitched("H-4") == -1
			&& Tracker.pitched("") == -1 && Tracker.louded("C-4 20") == 64,
			"C-4, C#4, Db4, c4 and B-3 read as 60, 61, 61, 60 and 59, H-4 reads as"
			+ " nothing, and a trailing 20 reads as a velocity of 64");

		lane.notes.resize(0);

		final part = mdd.song.Part.Fm3;
		final at = tracker.atColumn(part.index()) + tracker.columnWide() * 0.5;
		final top = tracker.y + tracker.head() + tracker.rowTall() * 2.5
			- tracker.offsetY;

		tree.focusOn(tracker);
		tracker.at(2, part.index());

		tree.pressed(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None, 2);
		tree.released(at, top, mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		says("a cell opens on a double click", tracker.entering && tracker.typing
			&& tracker.entered == "",
			"the cell under the pointer is taking characters and reads '"
			+ tracker.entered + "'");

		wrote(tree, tracker, "C#5 30");

		says("and what is typed lands in it", tracker.entered == "C#5 30",
			"the cell reads '" + tracker.entered + "'");

		tree.key(true, mdd.ui.Key.Return, mdd.ui.Mod.None);

		final made = tracker.noteAt(2, part.index());

		says("and return writes the note and steps on",
			made != null && made.pitch == 73 && made.velocity == 96
			&& !tracker.entering && tracker.row == 3,
			(made == null ? "nothing" : Tracker.spelt(made.pitch) + " at a velocity of "
			+ made.velocity) + " landed, and the cursor sits on row " + tracker.row);

		tracker.at(2, part.index());
		tracker.opens();

		says("and opening a written cell reads it back", tracker.entered == "C#5 30",
			"the cell reads '" + tracker.entered + "' where it wrote C#5 30");

		wrote(tree, tracker, "x");
		tree.key(true, mdd.ui.Key.Escape, mdd.ui.Mod.None);

		final kept = tracker.noteAt(2, part.index());

		says("and escape leaves the cell as it was", !tracker.entering && kept == made,
			"the note is still " + (kept == null ? "gone" : Tracker.spelt(kept.pitch))
			+ " after typing into it and pressing escape");

		tracker.at(2, part.index());
		tracker.opens();

		tree.key(true, mdd.ui.Key.Delete, mdd.ui.Mod.None);
		wrote(tree, tracker, "---");
		tree.key(true, mdd.ui.Key.Return, mdd.ui.Mod.None);

		says("and three dashes take the note away",
			tracker.noteAt(2, part.index()) == null && lane.notes.length == 0,
			lane.notes.length + " notes left in the lane");

		tracker.at(2, part.index());
		tracker.opens();

		wrote(tree, tracker, "D-4 20");
		tree.key(true, mdd.ui.Key.Return, mdd.ui.Mod.None);

		tracker.at(2, part.index());
		final copied = tracker.edited(mdd.ui.Edit.COPY);

		tracker.at(6, part.index());
		final put = tracker.edited(mdd.ui.Edit.PASTE);

		final over = tracker.noteAt(6, part.index());

		says("a cell copies and pastes", copied && put && over != null
			&& over.pitch == 62 && over.velocity == 64,
			"a cell holding " + (over == null ? "nothing" : Tracker.spelt(over.pitch)
			+ " at a velocity of " + over.velocity) + " came from a copy of D-4 20");

		lane.notes.resize(0);
	}

	static function sorted(tree:Root, presets:mdd.view.editor.Presets,
			session:mdd.app.Session):Void {
		presets.sorts(mdd.view.editor.Presets.BY_BANK);
		laid(tree);

		final banked = spelt(presets);

		presets.sorts(mdd.view.editor.Presets.BY_NAME);
		laid(tree);

		final named = spelt(presets);
		var rising = true;

		for (index in 1...named.length) {
			if (named[index].toLowerCase() < named[index - 1].toLowerCase()) rising = false;
		}

		says("presets sort by name", rising && named.length > 4
			&& named.join(",") != banked.join(","),
			named.length + " presets in a bank read " + named[0] + " to "
			+ named[named.length - 1] + " in order, where the bank had them as "
			+ banked[0] + " to " + banked[banked.length - 1]);

		presets.sorts(mdd.view.editor.Presets.BY_TAG);
		laid(tree);

		final tagged = spelt(presets);

		says("and by tag", tagged.length == named.length
			&& tagged.join(",") != named.join(","),
			tagged.length + " presets read " + tagged[0] + " first by tag against "
			+ named[0] + " by name");

		says("and the order is a chip in the header",
			presets.onOrder(presets.orderLeft() + presets.orderWide() * 0.5,
				presets.y + 4)
			&& !presets.onOrder(presets.x + 4, presets.y + 4),
			"the chip answers to a press on itself and not to the panel's title");

		presets.sorts(mdd.view.editor.Presets.BY_BANK);
		laid(tree);
	}

	static function spelt(presets:mdd.view.editor.Presets):Array<String> {
		final out:Array<String> = [];

		for (top in presets.tree.roots) {
			for (group in top.children) {
				if (group.children.length < 5) continue;

				for (child in group.children) out.push(child.label);
				return out;
			}
		}

		return out;
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

	static function moveAt(px:Float, py:Float):mdd.ui.Input {
		final event = new mdd.ui.Input();
		event.pointer(mdd.ui.Kind.PointerMove, px, py, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);
		return event;
	}

	static function releaseAt(px:Float, py:Float):mdd.ui.Input {
		final event = new mdd.ui.Input();
		event.pointer(mdd.ui.Kind.PointerUp, px, py, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);
		return event;
	}

	static function keyAt(code:mdd.ui.Key):mdd.ui.Input {
		final event = new mdd.ui.Input();
		event.keyed(mdd.ui.Kind.KeyDown, code, mdd.ui.Mod.None, false);
		return event;
	}

	static function banded(tree:Root, widget:mdd.ui.Widget, fromX:Float, fromY:Float,
			toX:Float, toY:Float, mods:mdd.ui.Mod):Void {
		final press = new mdd.ui.Input();
		press.pointer(mdd.ui.Kind.PointerDown, fromX, fromY, mdd.ui.Pointer.Left, mods);
		widget.took(press);

		final move = new mdd.ui.Input();
		move.pointer(mdd.ui.Kind.PointerMove, toX, toY, mdd.ui.Pointer.Left, mods);
		widget.took(move);

		final lift = new mdd.ui.Input();
		lift.pointer(mdd.ui.Kind.PointerUp, toX, toY, mdd.ui.Pointer.Left, mods);
		widget.took(lift);
	}

	static function grouped(tree:Root, session:mdd.app.Session, centre:Centre, paint:Paint,
			renderer:cpp.Star<Canvas>):Void {
		centre.show(Centre.ROLL);

		final roll = centre.roll;
		final pattern = session.current();
		if (pattern == null) return;

		final beat = session.song.tempo.ppqn;
		final lane = pattern.lane(session.part);

		lane.notes.resize(0);
		for (step in 0...4) lane.add(new Note(beat * (step + 1), Std.int(beat / 2), 60, 100));

		session.history.clear();
		roll.choose(null);
		roll.reveal(0, 60);

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		tree.focusOn(roll);

		says("everything in a lane can be selected at once",
			tree.edits(mdd.ui.Edit.ALL) && roll.picked.count == 4,
			roll.picked.count + " of " + lane.notes.length + " notes selected by one shortcut");

		final field = new mdd.ui.control.Field("120");

		roll.add(field);
		tree.focusOn(field);

		roll.choose(null);

		final blocked = tree.edits(mdd.ui.Edit.ALL);

		tree.focusOn(roll);
		roll.remove(field);

		says("and a shortcut that would edit leaves a field alone",
			!blocked && roll.picked.count == 0,
			"select everything reached " + roll.picked.count + " notes while a field was"
			+ " being typed into");

		tree.edits(mdd.ui.Edit.ALL);

		session.uses(mdd.app.Session.SELECT);

		banded(tree, roll, roll.atTick(Std.int(beat / 4)), roll.atPitch(61),
			roll.atTick(Std.int(beat * 2.25)), roll.atPitch(59), mdd.ui.Mod.None);

		final two = roll.picked.count == 2 && roll.picked.holds(lane.notes[0])
			&& roll.picked.holds(lane.notes[1]);

		says("and a band takes only what it covers", two,
			roll.picked.count + " notes under a band across two beats of four, holding the "
			+ "first " + (two ? "two" : "of something else"));

		final third = lane.notes[2];
		final press = new mdd.ui.Input();
		final seat = roll.atPitch(60) + roll.rowTall * 0.5;

		clicked(roll, press, roll.atTick(third.at) + 2, seat, mdd.ui.Mod.Shift);

		final ranged = roll.picked.count == 2 && roll.picked.holds(third)
			&& roll.picked.holds(lane.notes[1]);

		clicked(roll, press, roll.atTick(lane.notes[0].at) + 2, seat, mdd.ui.Mod.Shift);

		final wider = roll.picked.count == 3;

		press.pointer(mdd.ui.Kind.PointerDown, roll.atTick(third.at) + 2, seat,
			mdd.ui.Pointer.Left, mdd.ui.Mod.Ctrl);
		roll.took(press);

		final without = roll.picked.count == 2 && !roll.picked.holds(third);

		press.pointer(mdd.ui.Kind.PointerDown, roll.atTick(third.at) + 2, seat,
			mdd.ui.Pointer.Left, mdd.ui.Mod.Ctrl);
		roll.took(press);

		says("and shift takes a range where ctrl takes one out of it",
			ranged && wider && without && roll.picked.count == 3
			&& roll.picked.holds(third),
			"shift on the third note of a band of two reaches " + (ranged ? "2" : "something"
			+ " else") + ", shift back to the first reaches " + (wider ? "3" : "something else")
			+ ", and a ctrl click drops it to " + (without ? "2" : "something else")
			+ " and puts it back at " + roll.picked.count);

		roll.edited(mdd.ui.Edit.ALL);

		final were:Array<Int> = [];
		for (note in lane.notes) were.push(note.at);

		final depth = session.history.depth();
		final grab = roll.atTick(lane.notes[0].at
			+ Std.int(lane.notes[0].length / 2));
		final row = roll.atPitch(60) + roll.rowTall * 0.5;

		session.uses(mdd.app.Session.DRAW);
		banded(tree, roll, grab, row, grab + beat * roll.perTick, row, mdd.ui.Mod.None);

		var moved = 0;
		for (index in 0...lane.notes.length) {
			if (lane.notes[index].at == were[index] + beat) moved++;
		}

		says("and dragging one of them carries the rest",
			moved == 4 && session.history.depth() == depth + 1,
			moved + " of 4 notes moved a beat later, in "
			+ (session.history.depth() - depth) + " step of history");

		session.undo();

		var back = 0;
		for (index in 0...lane.notes.length) if (lane.notes[index].at == were[index]) back++;

		says("and one undo puts them all back", back == 4 && session.history.depth() == depth,
			back + " of 4 notes at the tick they started from after a single undo");

		roll.edited(mdd.ui.Edit.ALL);
		roll.edited(mdd.ui.Edit.COPY);

		final was = lane.notes.length;
		roll.edited(mdd.ui.Edit.PASTE);

		final gap = lane.notes.length >= was + 4
			? lane.notes[1].at - lane.notes[0].at : -1;

		says("and a copy keeps the spacing when it is pasted",
			lane.notes.length == was + 4 && gap == beat,
			lane.notes.length + " notes after pasting four, the first two " + gap
			+ " ticks apart against " + beat);

		session.undo();

		says("and that paste undoes in one step", lane.notes.length == was,
			lane.notes.length + " notes after one undo, from " + (was + 4));

		roll.edited(mdd.ui.Edit.ALL);
		roll.took(keyAt(mdd.ui.Key.Delete));

		says("and delete clears the whole selection", lane.notes.length == 0
			&& roll.picked.count == 0,
			lane.notes.length + " notes left and " + roll.picked.count + " still selected");

		session.undo();

		says("and one undo brings every one of them back", lane.notes.length == was,
			lane.notes.length + " notes back from a single undo");

		roll.edited(mdd.ui.Edit.ALL);

		final chosen = roll.picked.count;
		lane.notes.resize(0);

		roll.took(keyAt(mdd.ui.Key.Delete));

		says("and a selection left behind by an undo acts on nothing",
			chosen > 0 && lane.notes.length == 0 && session.history.last() != "remove "
			+ noted(chosen),
			chosen + " notes were selected when the lane was emptied under them, and delete"
			+ " wrote '" + session.history.last() + "' rather than a removal that would come"
			+ " back on undo");

		session.undo();

		says("and undoing after that puts nothing back", lane.notes.length == 0,
			lane.notes.length + " notes in a lane that was emptied");

		freed(tree, session, roll, beat);
		levelled(tree, session, roll, beat);
		stepped(tree, session, roll, beat);
		clipped(session, centre);
		brushed(tree, session, centre);
		cornered(tree, session, centre);
		numbered(session);
		gathered(tree, session, centre.roll);
	}

	/**
		A new pattern's name carries a number, and the number is one nothing in the song is already
		called by, where counting the patterns alone repeats a name once one has been removed.
	**/
	static function numbered(session:mdd.app.Session):Void {
		final patterns = new mdd.app.Patterns(session);
		final song = session.song;
		final next = song.patterns.length + 1;
		final names:Array<String> = [for (pattern in song.patterns) pattern.name];

		for (index in 0...song.patterns.length) song.patterns[index].name = "Pattern " + (index + 1);

		final plain = patterns.numbered("Pattern");

		song.patterns[0].name = "Pattern " + next;
		final moved = patterns.numbered("Pattern");

		for (index in 0...song.patterns.length) song.patterns[index].name = names[index];

		says("a new pattern takes a free number", plain == "Pattern " + next
			&& moved == "Pattern " + (next + 1),
			"'" + plain + "' beside " + song.patterns.length + " patterns, and '" + moved
			+ "' once one of them is already called 'Pattern " + next + "'");
	}

	static function stepped(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll, beat:Int):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);

		lane.notes.resize(0);
		for (step in 0...3) lane.add(new Note(step * beat, 24, 60 + step, 100));

		session.snapping = 2;
		session.history.clear();

		roll.choose(lane.notes[0]);
		tree.focusOn(roll);

		tree.key(true, mdd.ui.Key.Right, mdd.ui.Mod.None);

		var ordered = true;
		final places:Array<Int> = [];

		for (index in 0...lane.notes.length) {
			places.push(lane.notes[index].at);
			if (index > 0 && lane.notes[index].at < lane.notes[index - 1].at) ordered = false;
		}

		says("a note stepped past its neighbours keeps the lane in order",
			ordered && session.history.depth() == 1,
			"the lane reads " + places.join(", ") + " after one note was stepped "
			+ (beat * 2) + " ticks later, in " + session.history.depth()
			+ " step of history");

		session.undo();

		says("and one undo puts it back", lane.notes[0].at == 0
			&& lane.notes.length == 3,
			"the lane reads " + lane.notes[0].at + ", " + lane.notes[1].at + ", "
			+ lane.notes[2].at + " again");

		session.snapping = mdd.app.Session.SIXTEENTH;
		lane.notes.resize(0);
		session.history.clear();
	}

	static function freed(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll, beat:Int):Void {
		final pattern = session.current();
		if (pattern == null) return;

		final lane = pattern.lane(session.part);

		lane.notes.resize(0);
		lane.add(new Note(beat, Std.int(beat / 2), 60, 100));

		roll.choose(null);
		session.snapping = mdd.app.Session.SIXTEENTH;
		session.uses(mdd.app.Session.DRAW);

		final note = lane.notes[0];
		final row = roll.atPitch(60) + roll.rowTall * 0.5;
		final by = roll.perTick * 7;

		banded(tree, roll, roll.atTick(note.at) + 2, row, roll.atTick(note.at) + 2 + by, row,
			mdd.ui.Mod.None);

		final snapped = note.at;

		session.undo();

		banded(tree, roll, roll.atTick(note.at) + 2, row, roll.atTick(note.at) + 2 + by, row,
			mdd.ui.Mod.Alt);

		final free = note.at;
		session.undo();

		says("alt drops the grid while dragging",
			snapped % session.snap == 0 && free % session.snap != 0
			&& free != snapped,
			"a drag of 7 ticks landed on " + snapped + ", a multiple of " + session.snap
			+ ", and on " + free + " with alt held");

		lane.notes.resize(0);
	}

	static function levelled(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll, beat:Int):Void {
		final pattern = session.current();
		if (pattern == null) return;

		roll.showLanes = true;
		roll.shows(0);

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		if (roll.velocityTall() <= 0) return;

		final lane = pattern.lane(session.part);

		lane.notes.resize(0);
		lane.add(new Note(beat, Std.int(beat / 2), 60, 100));

		roll.choose(null);
		session.history.clear();

		final note = lane.notes[0];
		final was = note.velocity;

		final top = roll.y + roll.height - roll.lanes() + roll.stripHead()
			+ roll.velocityTall() * 0.2;
		final floor = roll.y + roll.height - roll.lanes() + roll.velocityTall() * 0.9;
		final at = roll.atTick(note.at);

		final press = new mdd.ui.Input();
		press.pointer(mdd.ui.Kind.PointerDown, at, top, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);
		roll.took(press);

		for (step in 0...16) {
			final move = new mdd.ui.Input();
			move.pointer(mdd.ui.Kind.PointerMove, at,
				top + (floor - top) * (step + 1) / 16, mdd.ui.Pointer.Left,
				mdd.ui.Mod.None);

			roll.took(move);
		}

		final during = session.history.depth();
		final pulled = note.velocity;

		final lift = new mdd.ui.Input();
		lift.pointer(mdd.ui.Kind.PointerUp, at, floor, mdd.ui.Pointer.Left, mdd.ui.Mod.None);
		roll.took(lift);

		says("leaning on a velocity is one step of history",
			pulled != was && during == 0 && session.history.depth() == 1,
			"the velocity went from " + was + " to " + pulled + " across 16 moves that left "
			+ during + " steps, and " + session.history.depth() + " once the button came up");

		session.undo();

		says("and it undoes", note.velocity == was,
			"the velocity reads " + note.velocity + " again");

		lane.notes.resize(0);
		session.history.clear();
	}

	static function clipped(session:mdd.app.Session, centre:Centre):Void {
		final playlist = centre.playlist;
		final tracks = session.song.tracks;

		for (track in tracks) track.clips.resize(0);

		final beat = session.song.tempo.ppqn;

		for (index in 0...3) {
			tracks[index % tracks.length].add(new mdd.song.Clip(session.pattern,
				beat * 4 * index, beat * 4));
		}

		session.history.clear();

		says("every clip on the playlist selects at once",
			playlist.edited(mdd.ui.Edit.ALL) && playlist.picked.count == 3,
			playlist.picked.count + " of 3 clips selected by one shortcut");

		final depth = session.history.depth();
		playlist.took(keyAt(mdd.ui.Key.Delete));

		var left = 0;
		for (track in tracks) left += track.clips.length;

		says("and they delete in one step", left == 0
			&& session.history.depth() == depth + 1,
			left + " clips left in " + (session.history.depth() - depth) + " step");

		session.undo();

		var again = 0;
		for (track in tracks) again += track.clips.length;

		says("and one undo restores all three", again == 3,
			again + " clips back from a single undo");

		for (track in tracks) track.clips.resize(0);
	}

	/**
		The pencil on the playlist lays a run of clips across a drag.

		A press laid one clip and the drag that followed resized it, so laying four bars of a
		pattern meant four presses. The drag now lays a copy for every length of the clip it
		crosses, and the whole run is one step on the undo stack.

		@param tree The shell.
		@param session The piece.
		@param centre The tabs.
	**/
	static function brushed(tree:Root, session:mdd.app.Session, centre:Centre):Void {
		centre.show(Centre.PLAYLIST);
		laid(tree);

		final playlist = centre.playlist;
		final tracks = session.song.tracks;
		final pattern = session.current();

		if (pattern == null) return;

		for (track in tracks) track.clips.resize(0);

		final was = pattern.length;
		final long = session.song.tempo.ppqn * 4;

		pattern.length = long;

		playlist.fit();
		laid(tree);

		while (long * playlist.perTick < 40 && playlist.perTick < 1) {
			playlist.zoom(2, playlist.x + playlist.names());
			laid(tree);
		}

		playlist.scrollTo(0);
		laid(tree);

		session.history.clear();
		session.tool = Session.DRAW;

		final row = playlist.atTrack(0) + 4;

		swept(playlist, [playlist.atTick(0), row, playlist.atTick(long), row,
			playlist.atTick(long * 2), row, playlist.atTick(long * 3), row],
			mdd.ui.Pointer.Left, mdd.ui.Mod.None);

		final clips = tracks[0].clips;
		var inLine = 0;

		for (index in 0...clips.length) {
			if (clips[index].at == index * long && clips[index].length == long) inLine++;
		}

		says("the pencil lays a clip for every length the drag crosses",
			clips.length == 4 && inLine == 4 && session.history.depth() == 1,
			clips.length + " clips of " + long + " ticks, " + inLine
			+ " of them end to end from tick 0 across a drag of three lengths, in "
			+ session.history.depth() + " step of history");

		session.undo();

		says("and the whole run comes off in one undo", tracks[0].clips.length == 0,
			tracks[0].clips.length + " clips left after a single undo");

		for (track in tracks) track.clips.resize(0);

		pattern.length = was;

		session.history.clear();
		session.tool = Session.SELECT;
	}

	static function cornered(tree:Root, session:mdd.app.Session, centre:Centre):Void {
		centre.show(Centre.PLAYLIST);
		laid(tree);

		final playlist = centre.playlist;
		final tracks = session.song.tracks;

		for (track in tracks) track.clips.resize(0);

		final beat = session.song.tempo.ppqn;
		final clip = new mdd.song.Clip(session.pattern, 0, beat * 16);

		tracks[0].add(clip);

		playlist.fit();
		laid(tree);

		while (clip.length * playlist.perTick < playlist.cornerSize() * 4) {
			playlist.zoom(2, playlist.x + playlist.names());
			laid(tree);
		}

		final size = playlist.cornerSize();
		final at = playlist.atTick(clip.at);
		final row = playlist.atTrack(0) + 2;

		final inside = playlist.onCorner(clip, 0, at + size * 0.5, row + size * 0.5);
		final outside = playlist.onCorner(clip, 0, at + size * 3, row + size * 0.5);

		says("a clip carries a corner to press", inside && !outside,
			"the top left " + Math.round(size) + " pixels of a clip "
			+ Math.round(clip.length * playlist.perTick) + " wide answer, and the body"
			+ " beside them does not");

		final metrics = tree.metrics;
		final arrow = size - metrics.whole(3);
		final named = playlist.labelAt(clip.length * playlist.perTick, metrics);
		final narrow = playlist.labelAt(size, metrics);

		says("and its name starts clear of it", named >= arrow + metrics.whole(3) && narrow < arrow,
			"the name starts " + Math.round(named - arrow) + " px after the arrow's edge at "
			+ Math.round(arrow) + ", and at " + Math.round(narrow) + " px on a clip too narrow to"
			+ " carry the arrow");

		final word = tree.translate(mdd.app.Locale.PATTERN_RENAME);
		final wasRenaming = playlist.onRenamePattern;
		var asked = -1;
		var offered = -1;

		playlist.onRenamePattern = function(which:Int):Void asked = which;

		tree.dismiss();
		tree.pressed(at + size * 0.5, row + size * 0.5, mdd.ui.Pointer.Left,
			mdd.ui.Mod.None);

		final many = tree.popups.length == 0 ? 0 : tree.popups[0].commands();

		says("and pressing it offers what to do with the clip", many >= 7
			&& playlist.picked.holds(clip),
			many + " commands under the corner, and the clip it belongs to is the one"
			+ " selected");

		if (tree.popups.length > 0) {
			final menu = tree.popups[0];

			for (index in 0...menu.choices.length) {
				if (menu.choices[index].label == word) offered = index;
			}

			if (offered >= 0) menu.fire(offered);
		}

		says("and one renames its pattern", offered >= 0 && asked == clip.pattern,
			offered < 0 ? "no '" + word + "' under the corner"
			: (asked < 0 ? "'" + word + "' is under the corner and asks for nothing"
			: "'" + word + "' asks to rename pattern " + asked + ", which the clip plays "
			+ clip.pattern));

		playlist.onRenamePattern = wasRenaming;

		tree.dismiss();
		for (track in tracks) track.clips.resize(0);
	}

	static function gathered(tree:Root, session:mdd.app.Session,
			roll:mdd.view.editor.PianoRoll):Void {
		final stack = roll.stack;
		final held = mdd.view.Parameter.of(session.part);

		session.uses(mdd.app.Session.DRAW);

		for (index in 0...held.length) {
			if (held[index].target != mdd.song.Automation.LEVEL) continue;

			roll.shows(index + 1);
			break;
		}

		tree.reshape();
		tree.top.measure(tree.width, tree.height);
		tree.top.arrange(0, 0, tree.width, tree.height);

		if (stack.rows() == 0) return;

		final beat = session.song.tempo.ppqn;
		final one = stack.parameterOf(0);
		if (one == null) return;

		session.history.clear();

		final started = stack.lineOf(0);
		final before = started == null ? 0 : started.points.length;

		for (step in 0...3) {
			session.does(new mdd.song.edit.AddPoint(session.pattern, session.part,
				stack.targetOf(0), stack.slotOf(0),
				new mdd.song.Point(beat * (step + 1) + 3, one.low + step)));
		}

		final line = stack.lineOf(0);
		final many = line == null ? 0 : line.points.length;

		if (line != null && many > 0) stack.picks(line.points[0], 0);

		final took = stack.edited(mdd.ui.Edit.ALL);

		says("every point in a lane selects at once", many == before + 3 && took
			&& stack.picked.count == many,
			stack.picked.count + " of " + many + " points selected by one shortcut");

		final depth = session.history.depth();
		stack.took(keyAt(mdd.ui.Key.Delete));

		final after = stack.lineOf(0);
		final rest = after == null ? 0 : after.points.length;

		says("and they delete in one step", rest == 0
			&& session.history.depth() == depth + 1,
			rest + " points left in " + (session.history.depth() - depth) + " step");

		session.undo();

		final again = stack.lineOf(0);

		says("and one undo restores every one of them",
			again != null && again.points.length == many,
			(again == null ? 0 : again.points.length) + " of " + many
			+ " points back from a single undo");

		while (session.history.depth() > 0) session.undo();
		roll.shows(0);
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
		final renderer = Sdl.createRenderer(window, 0, mdd.App.PINNED);

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
		metrics.dress(body, small, mono, mono, small);

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
			+ " ms over " + mdd.view.monitor.Scope.BARS + " bands of " + centre.scope.window()
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
		session.snapping = mdd.app.Session.SIXTEENTH;

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

		final stacked = tracker.noteAt(4, Part.Fm3.index());

		says("and a cell holds one note", third.notes.length == 2 && stacked != null
			&& stacked.pitch == 62,
			"typing into a row that already sounds replaced it with "
			+ Tracker.spelt(stacked.pitch) + " rather than stacking on it");

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

		entered(tree, tracker, third);

		centre.show(Centre.ROLL);
		session.snapping = mdd.app.Session.SIXTEENTH;

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

		cpp.vm.Gc.run(true);
		cpp.vm.Gc.enable(false);

		final before = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);

		for (frame in 0...120) {
			roll.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);
		}

		final grew = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT) - before;
		cpp.vm.Gc.enable(true);

		says("a frame allocates nothing", grew == 0,
			Math.round(grew / 120) + " bytes a frame across 120 frames of the whole shell,"
			+ " measured from a swept heap with the collector off");

		spared(tree, centre, paint, renderer);

		final middle = median(times, rolls) * 1000;

		says("it holds sixty a second", middle < 16.67,
			"median " + round(middle, 3) + " ms a frame while scrolling, mean "
			+ round(mean, 3) + ", worst " + round(worst * 1000, 3) + " at frame " + worstAt
			+ ", " + over + " frames of " + rolls + " over 16.67, first frame "
			+ round(first * 1000, 1));

		menued(tree);
		collected();
		fitted(tree);
		aligned(tree);
		laned(tree, session, centre.roll);
		grouped(tree, session, centre, paint, renderer);
		tagged(tree, editor.presets, session);
		tabbed(tree, centre, paint, renderer);
		sheeted(tree, session);
		buttoned(tree, session, centre);
		reopened(tree, session, centre);
		synthed(tree, session, editor);
		sought(tree, session, editor);
		commanded(tree, session, centre);
		rubbed(tree, session, centre);
		zoomed(tree, session, centre);
		tooled(tree, session, centre);
		swiped(tree, session, centre);
		chorded(tree, session, centre);
		filmed(tree, session, centre, paint);
		shaped(tree, session, centre.roll);
		racked(tree, session, rack);
		budgeted(tree, session, budget, centre.roll);
		chased(tree, session, centre, paint, renderer);
		restarted(tree, session, centre.roll);

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

		final held = session.current();
		final was = held.length;
		final depth = session.history.depth();
		final resized:Array<String> = [];

		for (field in bar.fields()) {
			final value = field.value;

			field.set(value + 1);
			if (session.history.last() == "resize a pattern") resized.push(field.label);

			field.set(value - 1);
			if (session.history.last() == "resize a pattern") resized.push(field.label);

			field.set(value);
		}

		while (session.history.depth() > depth) session.history.undo(session.song);

		says("no field on the transport bar sets a pattern's length", resized.length == 0,
			bar.fields().length + " fields driven either way and " + resized.length
			+ " reached for a resize" + (resized.length == 0 ? "" : ": " + resized.join(", "))
			+ ", with the pattern holding " + held.notes() + " notes across " + was + " ticks");

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
