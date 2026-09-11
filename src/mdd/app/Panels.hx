package mdd.app;

import mdd.check.Budget;
import mdd.check.Profile;
import mdd.song.Part;
import mdd.ui.Shell;
import mdd.view.Centre;
import mdd.view.Status;
import mdd.view.Inspector;
import mdd.view.Rail;
import mdd.view.TransportBar;
import mdd.view.editor.ChannelRack;
import mdd.view.overlay.Export;
import mdd.view.overlay.Naming;
import mdd.view.overlay.Notice;
import mdd.view.overlay.Preferences;
import mdd.view.overlay.Welcome;
import mdd.view.overlay.Working;

@:unreflective

/**
	Every panel the window holds, and the wiring between them.

	It builds them, points them at a session, and passes what one does to whichever
	others have to know. Loading a piece calls `follows` rather than building them
	again, so no callback is dropped.
**/
final class Panels {
	static final ZONES:Array<Int> = [Shell.TRANSPORT, Shell.RAIL, Shell.CENTRE, Shell.INSPECTOR,
		Shell.STATUS];

	/**
		The session every panel reads.
	**/
	public var session:Null<Session> = null;

	/**
		Called when the monitoring volume moves.
	**/
	public var onMaster:Null<Int -> Void> = null;

	/**
		What the warnings panel shows.
	**/
	public var budget:Null<Budget> = null;

	/**
		The transport bar.
	**/
	public var bar:Null<TransportBar> = null;

	/**
		The rail down the left.
	**/
	public var rail:Null<Rail> = null;

	/**
		The channel rack.
	**/
	public var rack:Null<ChannelRack> = null;

	/**
		The working area.
	**/
	public var centre:Null<Centre> = null;

	/**
		The inspector down the right.
	**/
	public var inspector:Null<Inspector> = null;

	/**
		The status bar.
	**/
	public var status:Null<Status> = null;

	/**
		What the pattern list buttons do.
	**/
	public var patterns:Patterns = null;

	/**
		The preferences sheet.
	**/
	public var preferences:Null<Preferences> = null;

	/**
		The export sheet.
	**/
	public var exporting:Null<Export> = null;

	/**
		The sheet that says what a MIDI file holds and takes the choice of what to
		import out of it.
	**/
	public var importing:Null<mdd.view.overlay.Importing> = null;

	/**
		The update notice.
	**/
	public var notice:Null<Notice> = null;

	/**
		The first run sheet.
	**/
	public var welcome:Null<Welcome> = null;

	/**
		The sheet that asks for a name.
	**/
	public var naming:Null<Naming> = null;

	/**
		The about sheet.
	**/
	public var about:Null<mdd.view.overlay.About> = null;

	/**
		The progress bar.
	**/
	public var working:Null<Working> = null;

	/**
		Called when a panel asks for a sample to be imported.
	**/
	public var onImportSample:Null<Void -> Void> = null;

	/**
		The window these panels are in.
	**/
	public final stage:Stage;

	/**
		Builds an empty set of panels.

		@param stage The window they go in.
	**/
	public function new(stage:Stage) {
		this.stage = stage;
	}

	/**
		Builds every panel and wires them to each other and to a session.

		@param session The session they read.
	**/
	public function dress(session:Session):Void {
		this.session = session;

		bar = new TransportBar(session);
		rail = new Rail(session);
		rack = rail.rack;
		centre = new Centre(session);
		inspector = new Inspector(session);
		status = new Status(session, centre.warnings);
		patterns = new Patterns(session);

		final shell = stage.shell;

		for (which in ZONES) {
			final zone = shell.zone(which);
			while (zone.children.length > 0) zone.remove(zone.children[0]);
		}

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.STATUS).add(status);

		if (budget == null) budget = new Budget(Profile.megaDrive());

		centre.roll.budget = budget;
		centre.roll.onAudition = function(part:Part, pitch:Int):Void
			session.transport.auditions(part, pitch);
		centre.roll.onAutomate = function(target:Int, slot:Int):Void {
			centre.automation.shows(target, slot);
			centre.show(Centre.AUTOMATION);
		};
		centre.playlist.onRename = function(which:Int):Void renamedTrack(which);
		centre.playlist.onOpen = function(clip:mdd.song.Clip):Void {
			centre.automation.follows(clip);
			centre.show(Centre.AUTOMATION);
		};
		centre.tracker.onAudition = function(part:Part, pitch:Int):Void
			session.transport.auditions(part, pitch);
		rail.hardware.budget = budget;
		rail.hardware.levels = rack.levels;
		inspector.samples.onImport = function():Void if (onImportSample != null) onImportSample();
		inspector.samples.budget = budget;
		inspector.presets.onRename = function(which:Int):Void renamedPreset(which);
		inspector.presets.onTags = function(which:Int):Void taggedPreset(which);
		inspector.presets.onSave = function():Void savedPreset();
		centre.warnings.budget = budget;
		bar.onMaster = function(much:Int):Void if (onMaster != null) onMaster(much);
		bar.onPatterns = function(which:Int):Void commanded(which);

		follows(session);
	}

	/**
		Points every panel at another session, which loading a piece needs.

		@param session The session to follow.
	**/
	public function follows(session:Session):Void {
		if (exporting != null) exporting.session = session;
		if (preferences != null) preferences.session = session;
		if (notice != null) notice.session = session;
		if (welcome != null) welcome.session = session;
	}

	/**
		Tells every panel the piece changed, so they read it again.
	**/
	public function opened():Void {
		stage.root.raise(preferences);
		preferences.arrive();
	}

	/**
		Raises the export sheet.
	**/
	public function sounded():Void {
		stage.root.raise(exporting);
		exporting.ask();
	}

	/**
		Raises the import sheet for a file that has been surveyed.

		@param called What the file is called.
		@param strands What the survey found in it.
	**/
	public function surveyed(called:String,
			strands:Array<mdd.format.Strand>):Void {
		if (importing == null) return;

		stage.root.raise(importing);
		importing.ask(called, strands);
	}

	/**
		Acts on a button in the pattern list.

		@param which Which button.
	**/
	function commanded(which:Int):Void {
		switch (which) {
			case TransportBar.ADD: patterns.added(namedPattern());
			case TransportBar.DUPLICATE: patterns.duplicated(session.pattern);
			case TransportBar.RENAME: renamedPattern(session.pattern);
			case TransportBar.DELETE: patterns.dropped(session.pattern);
			case _:
		}
	}

	/**
		@return A name for a new pattern that nothing else already has.
	**/
	public function namedPattern():String {
		return stage.root.translate(Locale.PATTERN) + " " + (session.song.patterns.length + 1);
	}

	/**
		Asks for a new name for a pattern and applies it.

		@param which Which pattern, by index.
	**/
	public function renamedPattern(which:Int):Void {
		final held = session.song.patternAt(which);
		if (held == null || naming == null) return;

		naming.ask(stage.root.translate(Locale.TRACK_NAME), held.name);
		naming.onName = function(said:String):Void patterns.renamed(which, said);

		stage.root.raise(naming);
	}

	/**
		Asks for the tags of a preset and applies them.

		@param which Which preset, by index.
	**/
	function taggedPreset(which:Int):Void {
		final held = session.song.instrumentAt(which);
		if (held == null || naming == null) return;

		naming.ask(stage.root.translate(Locale.PRESET_TAGS), held.tags.join(", "));

		naming.onName = function(said:String):Void {
			held.tags.resize(0);

			for (one in said.split(",")) {
				final tag = StringTools.trim(one);
				if (tag != "" && held.tags.indexOf(tag) < 0) held.tags.push(tag);
			}

			session.changed();
		};

		stage.root.raise(naming);
	}

	/**
		Asks for a new name for a preset and applies it.

		@param which Which preset, by index.
	**/
	function renamedPreset(which:Int):Void {
		final held = session.song.instrumentAt(which);
		if (held == null || naming == null) return;

		naming.ask(stage.root.translate(Locale.PRESET_NAME), held.name);
		naming.onName = function(said:String):Void {
			held.name = said;
			session.changed();
		};

		stage.root.raise(naming);
	}

	/**
		Asks for a new name for a track and applies it.

		@param which Which track, by index.
	**/
	function renamedTrack(which:Int):Void {
		if (naming == null || which < 0 || which >= session.song.tracks.length) return;

		final held = session.song.tracks[which];

		naming.ask(stage.root.translate(Locale.TRACK_NAME), held.name);
		naming.onName = function(said:String):Void {
			session.does(new mdd.song.edit.RenameTrack(which, said));
		};

		stage.root.raise(naming);
	}

	/**
		Lifts the chosen patch into the library under a name the reader is asked for.
	**/
	public function savedPreset():Void {
		if (naming == null) return;

		final part = session.part;
		final from = session.song.instrumentAt(session.song.rack[part.index()]);
		if (from == null) return;

		naming.ask(stage.root.translate(Locale.PRESET_NAME), from.name);
		naming.onName = function(said:String):Void {
			final made = from.copy();
			made.name = said;

			session.holds();
			session.song.instrument(made);
			session.song.rack[part.index()] = session.song.instruments.length - 1;
			session.frees();
			session.say(said);
			session.changed();
		};

		stage.root.raise(naming);
	}
}
