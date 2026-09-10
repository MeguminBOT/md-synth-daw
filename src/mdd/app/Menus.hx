package mdd.app;

import mdd.Config;
import mdd.song.Part;
import mdd.ui.Shell;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.control.MenuBar;
import mdd.view.Centre;
import mdd.view.Inspector;
import mdd.view.Tools;
import mdd.view.TransportBar;

@:unreflective

/**
	The menu bar: every entry, what it is called, what chord reaches it, and what it
	does.

	An entry that is off says why rather than only being grey, and everything here is
	named through the string table so a menu reads in the language in force.
**/
final class Menus {
	/**
		The bar these entries are built into.
	**/
	public var bar:Null<MenuBar> = null;

	/**
		The updater, so the help menu can say why looking is disabled.
	**/
	public var update:Null<Update> = null;

	/**
		Called to open a file dialog.
	**/
	public var onAsk:Null<Int -> Void> = null;

	/**
		Called to save.
	**/
	public var onSave:Null<Void -> Void> = null;

	/**
		Called to quit.
	**/
	public var onQuit:Null<Void -> Void> = null;

	/**
		Called to undo.
	**/
	public var onUndo:Null<Void -> Void> = null;

	/**
		Called to redo.
	**/
	public var onRedo:Null<Void -> Void> = null;

	/**
		Called when the entries have to be built again, which changing language does.
	**/
	public var onRelabel:Null<Void -> Void> = null;

	final stage:Stage;
	final panels:Panels;

	var session:Null<Session> = null;

	/**
		Which chord reaches which action, for the labels.
	**/
	public var bindings:Null<Bindings> = null;

	/**
		Builds the menus over a window and its panels.

		@param stage The window.
		@param panels The panels the entries act on.
	**/
	public function new(stage:Stage, panels:Panels) {
		this.stage = stage;
		this.panels = panels;
	}

	/**
		Builds every menu again, in the language in force. Called at start and whenever
		the language changes.

		@param session The session the entries act on.
	**/
	public function dress(session:Session):Void {
		this.session = session;

		final zone = stage.shell.zone(Shell.MENU);
		while (zone.children.length > 0) zone.remove(zone.children[0]);

		bar = new MenuBar();
		zone.add(bar);

		commands();
	}

	/**
		@param key A string key.
		@return What it says in the language in force.
	**/
	inline function said(key:Locale):String {
		return stage.root.translate(key);
	}

	/**
		Builds the file and edit menus.
	**/
	function commands():Void {
		final file = new Menu();

		fired(file.offer(new Choice(said(Locale.FILE_NEW), Bindings.of(bindings, Bindings.NEW))), function():Void
			if (onNew != null) onNew());
		fired(file.offer(new Choice(said(Locale.FILE_OPEN), Bindings.of(bindings, Bindings.OPEN))), function():Void
			asks(Files.OPEN));
		fired(file.offer(new Choice(said(Locale.FILE_SAVE), Bindings.of(bindings, Bindings.SAVE))), function():Void
			saves());
		fired(file.offer(new Choice(said(Locale.FILE_SAVE_AS))), function():Void
			asks(Files.SAVE));
		file.divide();

		final looking = file.offer(new Choice(said(Locale.FILE_UPDATE)));

		if (update.possible()) fired(looking, function():Void looks());
		else {
			looking.enabled = false;
			looking.reason = said(Locale.FILE_NO_UPDATE);
		}

		file.divide();
		fired(file.offer(new Choice(said(Locale.FILE_PREFERENCES), Bindings.of(bindings, Bindings.PREFERENCES))),
			function():Void panels.opened());
		file.divide();
		fired(file.offer(new Choice(said(Locale.FILE_QUIT), "Alt+F4")), function():Void
			quits());

		final edit = new Menu();

		fired(edit.offer(new Choice(said(Locale.EDIT_UNDO), Bindings.of(bindings, Bindings.UNDO))), function():Void
			undoes());
		fired(edit.offer(new Choice(said(Locale.EDIT_REDO), Bindings.of(bindings, Bindings.REDO))), function():Void
			redoes());
		edit.divide();
		fired(edit.offer(new Choice(said(Locale.BIND_ALL), Bindings.of(bindings, Bindings.ALL))),
			function():Void edits(mdd.ui.Edit.ALL));
		fired(edit.offer(new Choice(said(Locale.BIND_COPY), Bindings.of(bindings, Bindings.COPY))),
			function():Void edits(mdd.ui.Edit.COPY));
		fired(edit.offer(new Choice(said(Locale.BIND_CUT), Bindings.of(bindings, Bindings.CUT))),
			function():Void edits(mdd.ui.Edit.CUT));
		fired(edit.offer(new Choice(said(Locale.BIND_PASTE), Bindings.of(bindings, Bindings.PASTE))),
			function():Void edits(mdd.ui.Edit.PASTE));
		edit.divide();
		fired(edit.offer(new Choice(said(Locale.EDIT_EARLIER), Bindings.of(bindings, Bindings.EARLIER))),
			function():Void nudges(-1));
		fired(edit.offer(new Choice(said(Locale.EDIT_LATER), Bindings.of(bindings, Bindings.LATER))),
			function():Void nudges(1));
		edit.divide();

		fired(edit.offer(new Choice(said(Locale.EDIT_PLAY), Bindings.of(bindings, Bindings.PLAY))), function():Void
			panels.bar.press(TransportBar.PLAY));
		fired(edit.offer(new Choice(said(Locale.EDIT_STOP), Bindings.of(bindings, Bindings.STOP))),
			function():Void panels.bar.press(TransportBar.STOP));

		bar.offer(said(Locale.MENU_FILE), file);
		bar.offer(said(Locale.MENU_EDIT), edit);
		bar.offer(said(Locale.MENU_PATTERN), patternMenu());
		bar.offer(said(Locale.MENU_CHANNELS), channelsMenu());
		bar.offer(said(Locale.MENU_INSTRUMENT), instrumentMenu());
		bar.offer(said(Locale.MENU_IMPORT), importMenu());
		bar.offer(said(Locale.MENU_EXPORT), exportMenu());
		bar.offer(said(Locale.MENU_VIEW), viewMenu());
		bar.offer(said(Locale.MENU_HELP), helpMenu());

		bar.trailing.resize(0);
		bar.trailing.push(said(Locale.FILE_OPEN));
		bar.trailing.push(said(Locale.FILE_SAVE));
		bar.trailing.push(said(Locale.FILE_PREFERENCES));

		bar.onTrailing = function(which:Int):Void {
			switch (which) {
				case 0: asks(Files.OPEN);
				case 1: saves();
				case _: panels.opened();
			}
		};
	}

	/**
		@return The pattern menu.
	**/
	function patternMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.PATTERN_ADD))), function():Void
			panels.patterns.added(panels.namedPattern()));
		fired(held.offer(new Choice(said(Locale.PATTERN_DUPLICATE))), function():Void
			panels.patterns.duplicated(session.pattern));
		fired(held.offer(new Choice(said(Locale.PATTERN_RENAME))), function():Void
			panels.renamedPattern(session.pattern));
		fired(held.offer(new Choice(said(Locale.PATTERN_INSERT))), function():Void
			panels.patterns.inserted(session.pattern));
		fired(held.offer(new Choice(said(Locale.PATTERN_DELETE))), function():Void
			panels.patterns.dropped(session.pattern));
		held.divide();
		held.offer(new Choice(said(Locale.PATTERN_PART))).submenu = parted();
		held.divide();
		fired(held.offer(new Choice(said(Locale.PATTERN_CLEAR))), function():Void
			emptied());

		return held;
	}

	/**
		@return The menu of parts, for choosing one.
	**/
	function parted():Menu {
		final out = new Menu();

		final now = session.song.patterns[session.pattern];

		for (index in 0...mdd.song.Part.COUNT) {
			final part:mdd.song.Part = index;
			final choice = out.offer(new Choice(part.name()));

			choice.enabled = now == null || now.part != index;
			fires(choice, index);
		}

		return out;
	}

	/**
		Wires a part entry to choosing that part.

		@param choice The entry.
		@param part Which part.
	**/
	function fires(choice:Choice, part:Int):Void {
		choice.onFire = function(from:Choice):Void {
			if (onPart != null) onPart(part);
		};
	}

	/**
		@return The channels menu.
	**/
	function channelsMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.CHANNELS_UNMUTE))), function():Void {
			final group = new mdd.song.edit.Together("unmute every channel");

			for (index in 0...Part.COUNT) {
				if (!session.song.muted[index]) continue;
				group.also(new mdd.song.edit.MutePart(index, false));
			}

			session.does(group);
		});

		fired(held.offer(new Choice(said(Locale.CHANNELS_UNSOLO))), function():Void {
			final group = new mdd.song.edit.Together("unsolo every channel");

			for (index in 0...Part.COUNT) {
				if (!session.song.soloed[index]) continue;
				group.also(new mdd.song.edit.SoloPart(index, false));
			}

			session.does(group);
		});

		held.divide();

		fired(held.offer(new Choice(said(Locale.CHANNELS_MUTE_REST))), function():Void {
			final which = session.part.index();
			final group = new mdd.song.edit.Together("mute the other channels");

			for (index in 0...Part.COUNT) {
				if (session.song.muted[index] == (index != which)) continue;
				group.also(new mdd.song.edit.MutePart(index, index != which));
			}

			session.does(group);
		});

		held.divide();
		fired(held.offer(new Choice(said(Locale.CHANNELS_CLEAR))), function():Void
			cleared());

		return held;
	}

	/**
		@return The instrument menu.
	**/
	function instrumentMenu():Menu {
		final held = new Menu();

		final copy = held.offer(new Choice(said(Locale.RACK_COPY_PRESET)));
		final paste = held.offer(new Choice(said(Locale.RACK_PASTE_PRESET)));
		final reset = held.offer(new Choice(said(Locale.RACK_RESET_PRESET)));

		fired(copy, function():Void copiedPatch());
		fired(paste, function():Void pastedPatch());
		fired(reset, function():Void resetPatch());

		paste.enabled = session.copiedPatch != null;
		if (!paste.enabled) paste.reason = said(Locale.RACK_NONE_COPIED);

		held.divide();
		fired(held.offer(new Choice(said(Locale.PRESET_SAVE))), function():Void
			panels.savedPreset());
		fired(held.offer(new Choice(said(Locale.PANEL_PRESETS))), function():Void
			panels.inspector.show(Inspector.PRESETS));

		return held;
	}

	/**
		@return The import menu.
	**/
	function importMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.FILE_READ_VGM))), function():Void
			asks(Files.READ_VGM));
		fired(held.offer(new Choice(said(Locale.FILE_READ_XGM))), function():Void
			asks(Files.READ_XGM));
		fired(held.offer(new Choice(said(Locale.FILE_READ_MIDI))), function():Void
			asks(Files.READ_MIDI));
		fired(held.offer(new Choice(said(Locale.FILE_READ_WAV))), function():Void
			asks(Files.READ_WAV));

		held.divide();

		fired(held.offer(new Choice(said(Locale.FILE_READ_TFI))), function():Void
			asks(Files.READ_TFI));

		fired(held.offer(new Choice(said(Locale.PRESET_LIFT))), function():Void lifted());

		return held;
	}

	/**
		Called to read every patch file in the presets folder into the library.
	**/
	public var onLift:Null<Void -> Int> = null;

	/**
		Called to start a new piece.
	**/
	public var onNew:Null<Void -> Void> = null;

	/**
		Called to move the piece in time.
	**/
	public var onNudge:Null<Int -> Void> = null;

	/**
		Called with an editing command.
	**/
	public var onEdit:Null<Int -> Void> = null;

	/**
		Called to choose a part.
	**/
	public var onPart:Null<Int -> Void> = null;

	/**
		Reads every patch file in the presets folder and says how many were new.
	**/
	function lifted():Void {
		final many = onLift == null ? 0 : onLift();

		session.say(many == 0 ? said(Locale.PRESET_NONE_LIFTED)
			: many + " " + said(Locale.PRESET_LIFTED));

		session.changed();
	}

	/**
		@return The export menu.
	**/
	function exportMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.FILE_TFI))), function():Void
			asks(Files.TFI));

		held.divide();

		fired(held.offer(new Choice(said(Locale.FILE_VGM), Bindings.of(bindings, Bindings.WRITE_VGM))), function():Void
			asks(Files.VGM));
		fired(held.offer(new Choice(said(Locale.FILE_AUDIO), Bindings.of(bindings, Bindings.WRITE_AUDIO))),
			function():Void panels.sounded());
		fired(held.offer(new Choice(said(Locale.FILE_XGM))), function():Void
			asks(Files.XGM));
		fired(held.offer(new Choice(said(Locale.FILE_MIDI))), function():Void
			asks(Files.MIDI));

		return held;
	}

	/**
		@return The view menu.
	**/
	function viewMenu():Menu {
		final held = new Menu();

		final driving = held.offer(new Choice(said(session.song.driving
			? Locale.VIEW_UNDRIVEN : Locale.VIEW_DRIVEN)));

		driving.reason = said(Locale.VIEW_DRIVEN_WHY);

		fired(driving, function():Void {
			session.does(new mdd.song.edit.DriveSong(!session.song.driving));
			session.transport.silence();

			session.say(said(session.song.driving ? Locale.VIEW_DRIVEN_ON
				: Locale.VIEW_DRIVEN_OFF));

			if (onRelabel != null) onRelabel();
		});

		return held;
	}

	/**
		Opens or closes a panel from the view menu.
	**/
	function shows():Void {
		if (panels.about == null || panels.stage == null) return;

		panels.stage.root.raise(panels.about);
		panels.about.arrive();
	}

	/**
		@return The help menu.
	**/
	function helpMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.HELP_ABOUT))), function():Void shows());

		final source = held.offer(new Choice(said(Locale.HELP_SOURCE)));

		if (update.possible()) {
			fired(source, function():Void session.say("https://github.com/" + Config.GITHUB));
		} else {
			source.enabled = false;
			source.reason = said(Locale.FILE_NO_UPDATE);
		}

		return held;
	}

	/**
		Asks the updater to look now, saying why where it cannot.
	**/
	function looks():Void {
		if (!update.look()) {
			session.says(update.state() == Update.LOOKING
				? Locale.SAID_LOOKING_ALREADY : Locale.SAID_NO_UPDATE_ADDRESS);
			session.changed();
			return;
		}

		session.say(said(Locale.UPDATE_LOOKING));
		session.changed();
	}

	/**
		Clears every note out of the chosen pattern.
	**/
	function emptied():Void {
		final held = session.current();
		if (held == null) return;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = held.lane(part);

			while (lane.notes.length > 0) {
				session.does(new mdd.song.edit.RemoveNote(session.pattern, part, lane.notes[0]));
			}
		}
	}

	/**
		Clears the chosen channel.
	**/
	function cleared():Void {
		final held = session.current();
		if (held == null) return;

		final lane = held.lane(session.part);

		while (lane.notes.length > 0) {
			session.does(new mdd.song.edit.RemoveNote(session.pattern, session.part,
				lane.notes[0]));
		}
	}

	/**
		Copies the chosen patch.
	**/
	function copiedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || held.patch == null) return;

		session.copiedPatch = held.patch.copy();
		session.say(said(Locale.RACK_COPY_PRESET));
		session.changed();
	}

	/**
		Pastes a patch onto the chosen channel.
	**/
	function pastedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || session.copiedPatch == null) return;

		held.patch = session.copiedPatch.copy();
		session.changed();
	}

	/**
		Puts the chosen patch back to silence.
	**/
	function resetPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null) return;

		held.patch = new mdd.song.Patch();
		session.changed();
	}

	/**
		Moves the whole piece in time.

		@param way How far, in ticks.
	**/
	inline function nudges(way:Int):Void {
		if (onNudge != null) onNudge(way);
	}

	/**
		Sends an editing command to whatever has the keyboard.

		@param what One of the `Edit` values.
	**/
	inline function edits(what:Int):Void {
		if (onEdit != null) onEdit(what);
	}

	/**
		Opens a file dialog.

		@param which Which dialog.
	**/
	inline function asks(which:Int):Void {
		if (onAsk != null) onAsk(which);
	}

	/**
		Saves the piece.
	**/
	inline function saves():Void {
		if (onSave != null) onSave();
	}

	inline function quits():Void {
		if (onQuit != null) onQuit();
	}

	inline function undoes():Void {
		if (onUndo != null) onUndo();
	}

	inline function redoes():Void {
		if (onRedo != null) onRedo();
	}

	function fired(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void what();
	}
}
