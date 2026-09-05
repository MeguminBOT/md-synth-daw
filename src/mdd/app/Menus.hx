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
final class Menus {
	public var bar:Null<MenuBar> = null;
	public var update:Null<Update> = null;

	public var onAsk:Null<Int -> Void> = null;
	public var onSave:Null<Void -> Void> = null;
	public var onQuit:Null<Void -> Void> = null;
	public var onUndo:Null<Void -> Void> = null;
	public var onRedo:Null<Void -> Void> = null;
	public var onRelabel:Null<Void -> Void> = null;

	final stage:Stage;
	final panels:Panels;

	var session:Null<Session> = null;

	public function new(stage:Stage, panels:Panels) {
		this.stage = stage;
		this.panels = panels;
	}

	public function dress(session:Session):Void {
		this.session = session;

		final zone = stage.shell.zone(Shell.MENU);
		while (zone.children.length > 0) zone.remove(zone.children[0]);

		bar = new MenuBar();
		zone.add(bar);

		commands();
	}

	inline function said(key:String):String {
		return stage.root.translate(key);
	}

	function commands():Void {
		final file = new Menu();

		fired(file.offer(new Choice(said(Locale.FILE_OPEN), "Ctrl+O")), function():Void
			asks(Files.OPEN));
		fired(file.offer(new Choice(said(Locale.FILE_SAVE), "Ctrl+S")), function():Void
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
		fired(file.offer(new Choice(said(Locale.FILE_PREFERENCES), "Ctrl+,")),
			function():Void panels.opened());
		file.divide();
		fired(file.offer(new Choice(said(Locale.FILE_QUIT), "Alt+F4")), function():Void
			quits());

		final edit = new Menu();

		fired(edit.offer(new Choice(said(Locale.EDIT_UNDO), "Ctrl+Z")), function():Void
			undoes());
		fired(edit.offer(new Choice(said(Locale.EDIT_REDO), "Ctrl+Y")), function():Void
			redoes());
		edit.divide();
		fired(edit.offer(new Choice(said(Locale.EDIT_PLAY), "Space")), function():Void
			panels.bar.press(TransportBar.PLAY));
		fired(edit.offer(new Choice(said(Locale.EDIT_STOP), "Ctrl+Space")),
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
		fired(held.offer(new Choice(said(Locale.PATTERN_CLEAR))), function():Void
			emptied());

		return held;
	}

	function channelsMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.CHANNELS_UNMUTE))), function():Void {
			for (index in 0...Part.COUNT) session.song.muted[index] = false;
			session.changed();
		});

		fired(held.offer(new Choice(said(Locale.CHANNELS_UNSOLO))), function():Void {
			for (index in 0...Part.COUNT) session.song.soloed[index] = false;
			session.changed();
		});

		held.divide();

		fired(held.offer(new Choice(said(Locale.CHANNELS_MUTE_REST))), function():Void {
			final which = session.part.index();
			for (index in 0...Part.COUNT) session.song.muted[index] = index != which;
			session.changed();
		});

		held.divide();
		fired(held.offer(new Choice(said(Locale.CHANNELS_CLEAR))), function():Void
			cleared());

		return held;
	}

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

	public var onLift:Null<Void -> Int> = null;

	function lifted():Void {
		final many = onLift == null ? 0 : onLift();

		session.say(many == 0 ? said(Locale.PRESET_NONE_LIFTED)
			: many + " " + said(Locale.PRESET_LIFTED));

		session.changed();
	}

	function exportMenu():Menu {
		final held = new Menu();

		fired(held.offer(new Choice(said(Locale.FILE_TFI))), function():Void
			asks(Files.TFI));

		held.divide();

		fired(held.offer(new Choice(said(Locale.FILE_VGM), "Ctrl+E")), function():Void
			asks(Files.VGM));
		fired(held.offer(new Choice(said(Locale.FILE_AUDIO), "Ctrl+Shift+E")),
			function():Void panels.sounded());
		fired(held.offer(new Choice(said(Locale.FILE_XGM))), function():Void
			asks(Files.XGM));
		fired(held.offer(new Choice(said(Locale.FILE_WAV))), function():Void
			asks(Files.WAV));
		fired(held.offer(new Choice(said(Locale.FILE_MIDI))), function():Void
			asks(Files.MIDI));

		return held;
	}

	function viewMenu():Menu {
		final held = new Menu();

		final driving = held.offer(new Choice(said(session.song.driving
			? Locale.VIEW_UNDRIVEN : Locale.VIEW_DRIVEN)));

		driving.reason = said(Locale.VIEW_DRIVEN_WHY);

		fired(driving, function():Void {
			session.song.driving = !session.song.driving;
			session.transport.silence();

			session.say(said(session.song.driving ? Locale.VIEW_DRIVEN_ON
				: Locale.VIEW_DRIVEN_OFF));

			session.changed();
			if (onRelabel != null) onRelabel();
		});

		return held;
	}

	function shows():Void {
		if (panels.about == null || panels.stage == null) return;

		panels.stage.root.raise(panels.about);
		panels.about.arrive();
	}

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

	function looks():Void {
		if (!update.look()) {
			session.say(update.state() == Update.LOOKING ? "already looking"
				: "no update address is configured");
			session.changed();
			return;
		}

		session.say(said(Locale.UPDATE_LOOKING));
		session.changed();
	}

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

	function cleared():Void {
		final held = session.current();
		if (held == null) return;

		final lane = held.lane(session.part);

		while (lane.notes.length > 0) {
			session.does(new mdd.song.edit.RemoveNote(session.pattern, session.part,
				lane.notes[0]));
		}
	}

	function copiedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || held.patch == null) return;

		session.copiedPatch = held.patch.copy();
		session.say(said(Locale.RACK_COPY_PRESET));
		session.changed();
	}

	function pastedPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null || session.copiedPatch == null) return;

		held.patch = session.copiedPatch.copy();
		session.changed();
	}

	function resetPatch():Void {
		final held = session.song.instrumentAt(session.song.rack[session.part.index()]);
		if (held == null) return;

		held.patch = new mdd.song.Patch();
		session.changed();
	}

	inline function asks(which:Int):Void {
		if (onAsk != null) onAsk(which);
	}

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
