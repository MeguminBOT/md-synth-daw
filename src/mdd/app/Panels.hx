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
		The video export sheet.
	**/
	public var exportingVideo:Null<Export> = null;

	/**
		The sheet that says what a MIDI file holds and takes the choice of what to
		import out of it.
	**/
	public var importing:Null<mdd.view.overlay.Importing> = null;

	/**
		The sheet that makes a kit out of a folder of recordings.
	**/
	public var kitting:Null<mdd.view.overlay.Kitting> = null;

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
		The sheet that describes the piece: title, artist, composer and the rest of its tags.
	**/
	public var describing:Null<mdd.view.overlay.Describing> = null;

	/**
		The sheet that asks a question and takes one of up to three answers.
	**/
	public var asking:Null<mdd.view.overlay.Asking> = null;

	/**
		The about sheet.
	**/
	public var about:Null<mdd.view.overlay.About> = null;

	/**
		The console limits sheet.
	**/
	public var limits:Null<mdd.view.overlay.Limits> = null;

	/**
		The progress bar.
	**/
	public var working:Null<Working> = null;

	/**
		Called when a panel asks for a sample to be imported.
	**/
	public var onImportSample:Null<Void -> Void> = null;

	/**
		Called with a preset just saved from the browser and the sample it plays, so it
		can be written into the presets folder and offered in every other piece.
	**/
	public var onPreset:Null<(mdd.song.Instrument, Null<mdd.song.Sample>) -> Void> = null;

	/**
		Called when the browser asks for the presets folder to be opened in the file
		manager.
	**/
	public var onPresetFolder:Null<Void -> Void> = null;

	/**
		Called when the browser asks for one preset to be written out as a patch file.
	**/
	public var onWritePatch:Null<(mdd.song.Instrument, Null<mdd.song.Sample>) -> Void> = null;

	/**
		Called when the browser asks for what one preset plays to be written out as a wave file.
	**/
	public var onWriteSample:Null<(mdd.song.Instrument, Null<mdd.song.Sample>) -> Void> = null;

	/**
		Called when the browser asks for a whole bank to be written out as one file: its name, its
		presets and what each plays.
	**/
	public var onWriteBank:Null<(String, Array<mdd.song.Instrument>, Array<Null<mdd.song.Sample>>)
		-> Void> = null;

	/**
		The presets the reader has starred, which the browser marks and can list on its own. It is
		set before `dress` and kept for the life of the application, so loading a piece leaves it
		alone.
	**/
	public var favourites:Null<mdd.app.Favourites> = null;

	/**
		When each installed preset was added, which the browser sorts and groups by. Set before
		`dress` and kept for the life of the application.
	**/
	public var added:Null<mdd.app.Added> = null;

	/**
		How the browser groups, sorts and filters, as its `spelt` line, which outlives the
		browser: loading a piece builds a new one and hands it this.
	**/
	public var presetView:String = "";

	/**
		Called with the browser's view whenever it changes, so it can be kept in the settings.
	**/
	public var onPresetView:Null<String -> Void> = null;

	/**
		The presets folder, which the browser changes a preset or a category in through this. Set
		before `dress`.
	**/
	public var presetFolder:Null<mdd.app.PresetFolder> = null;

	/**
		Called once the browser has changed files in the presets folder, so it is read again.
	**/
	public var onPresetsChanged:Null<Void -> Void> = null;

	/**
		Every file in the presets folder written from a shipped bank, which the browser lists as
		shipped.
	**/
	public var planted:Array<String> = [];

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
		centre.playlist.onRenamePattern = function(which:Int):Void renamedPattern(which);
		centre.tracker.onAudition = function(part:Part, pitch:Int):Void
			session.transport.auditions(part, pitch);
		rail.hardware.budget = budget;
		rail.hardware.levels = rack.levels;
		inspector.samples.onImport = function():Void if (onImportSample != null) onImportSample();
		inspector.samples.budget = budget;
		inspector.presets.favourites = favourites;
		inspector.presets.added = added;
		inspector.presets.reads(presetView);
		inspector.presets.onView = function():Void {
			presetView = inspector.presets.spelt();
			if (onPresetView != null) onPresetView(presetView);
		};

		inspector.presets.folder = presetFolder;
		inspector.presets.planted = planted;
		inspector.presets.onShelved = function():Void if (onPresetsChanged != null) onPresetsChanged();

		inspector.presets.onAsk = function(asked:Locale, said:String, then:String -> Void):Void {
			final sheet = naming;
			if (sheet == null) return;

			sheet.ask(stage.root.translate(asked), said);
			sheet.onName = function(answer:String):Void then(answer);
			stage.root.raise(sheet);
		};

		inspector.presets.onConfirm = function(question:String, going:String, then:Void -> Void):Void {
			final sheet = asking;
			if (sheet == null) return;

			stage.root.raise(sheet);
			sheet.ask(going, question, [going, sheet.translate(Locale.EXPORT_CANCEL)]);
			sheet.onAnswer = function(which:Int):Void if (which == 0) then();
		};
		inspector.presets.onRename = function(which:Int):Void renamedPreset(which);
		inspector.presets.onTags = function(which:Int):Void taggedPreset(which);
		inspector.presets.onSave = function():Void savedPreset();
		inspector.presets.onFolder = function():Void
			if (onPresetFolder != null) onPresetFolder();
		inspector.presets.onWritePatch = function(preset:mdd.song.Instrument,
				sample:Null<mdd.song.Sample>):Void
			if (onWritePatch != null) onWritePatch(preset, sample);
		inspector.presets.onWriteSample = function(preset:mdd.song.Instrument,
				sample:Null<mdd.song.Sample>):Void
			if (onWriteSample != null) onWriteSample(preset, sample);
		inspector.presets.onWriteBank = function(name:String, presets:Array<mdd.song.Instrument>,
				samples:Array<Null<mdd.song.Sample>>):Void
			if (onWriteBank != null) onWriteBank(name, presets, samples);
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
		if (exportingVideo != null) exportingVideo.session = session;
		if (preferences != null) preferences.session = session;
		if (notice != null) notice.session = session;
		if (welcome != null) welcome.session = session;
		if (describing != null) describing.session = session;
	}

	/**
		Raises the sheet that describes the piece, filled in with what it says now.
	**/
	public function described():Void {
		if (describing == null) return;

		describing.ask();
		stage.root.raise(describing);
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
		Raises the video export sheet.
	**/
	public function exportsVideo():Void {
		final scope = centre.scope;

		exportingVideo.scopes(scope.showing, scope.speed, scope.accuracy);
		stage.root.raise(exportingVideo);
		exportingVideo.ask();
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
		Raises the kit sheet for a folder that has been read.

		@param kit What the folder holds, already measured and converted.
	**/
	public function kitted(kit:mdd.format.Kit):Void {
		if (kitting == null) return;

		stage.root.raise(kitting);
		kitting.ask(kit);
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
		return patterns.numbered(stage.root.translate(Locale.PATTERN));
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
		Saves the chosen part's preset under a name the reader is asked for, out to the presets
		folder through `onPreset`, so every piece offers it. The channel keeps playing what it
		plays, now named for the preset it was saved as and counting that preset as where it came
		from.
	**/
	public function savedPreset():Void {
		if (naming == null) return;

		final part = session.part;
		final from = session.song.instrumentAt(session.song.rack[part.index()]);
		if (from == null) return;

		naming.ask(stage.root.translate(Locale.PRESET_NAME), from.name);
		naming.onName = function(said:String):Void {
			final song = session.song;
			final sample = song.sampleAt(from.sample);
			final made = from.copy();

			made.name = said;
			made.from = "";
			made.identifies(sample);

			from.name = said;
			from.from = made.id;

			if (onPreset != null) onPreset(made, sample);

			session.say(said);
			session.changed();
		};

		stage.root.raise(naming);
	}
}
