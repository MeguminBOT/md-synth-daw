package mdd.app;

import mdd.check.Budget;
import mdd.check.Profile;
import mdd.song.Part;
import mdd.ui.Shell;
import mdd.view.Centre;
import mdd.view.Dock;
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
final class Panels {
	static final ZONES:Array<Int> = [Shell.TRANSPORT, Shell.RAIL, Shell.CENTRE, Shell.INSPECTOR,
		Shell.DOCK];

	public var session:Null<Session> = null;
	public var budget:Null<Budget> = null;

	public var bar:Null<TransportBar> = null;
	public var rail:Null<Rail> = null;
	public var rack:Null<ChannelRack> = null;
	public var centre:Null<Centre> = null;
	public var inspector:Null<Inspector> = null;
	public var dock:Null<Dock> = null;

	public var preferences:Null<Preferences> = null;
	public var exporting:Null<Export> = null;
	public var notice:Null<Notice> = null;
	public var welcome:Null<Welcome> = null;
	public var naming:Null<Naming> = null;
	public var working:Null<Working> = null;

	public var onImportSample:Null<Void -> Void> = null;

	final stage:Stage;

	public function new(stage:Stage) {
		this.stage = stage;
	}

	public function dress(session:Session):Void {
		this.session = session;

		bar = new TransportBar(session);
		rail = new Rail(session);
		rack = rail.rack;
		centre = new Centre(session);
		inspector = new Inspector(session);
		dock = new Dock(session);

		final shell = stage.shell;

		for (which in ZONES) {
			final zone = shell.zone(which);
			while (zone.children.length > 0) zone.remove(zone.children[0]);
		}

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(inspector);
		shell.zone(Shell.DOCK).add(dock);

		if (budget == null) budget = new Budget(Profile.megaDrive());

		centre.roll.budget = budget;
		centre.roll.onAudition = function(part:Part, pitch:Int):Void
			session.transport.auditions(part, pitch);
		centre.playlist.onRename = function(which:Int):Void renamedTrack(which);
		centre.tracker.onAudition = function(part:Part, pitch:Int):Void
			session.transport.auditions(part, pitch);
		rail.hardware.budget = budget;
		rail.hardware.levels = rack.levels;
		inspector.samples.onImport = function():Void if (onImportSample != null) onImportSample();
		inspector.samples.budget = budget;
		inspector.presets.onRename = function(which:Int):Void renamedPreset(which);
		inspector.presets.onSave = function():Void savedPreset();
		dock.warnings.budget = budget;

		follows(session);
	}

	public function follows(session:Session):Void {
		if (exporting != null) exporting.session = session;
		if (preferences != null) preferences.session = session;
		if (notice != null) notice.session = session;
		if (welcome != null) welcome.session = session;
	}

	public function opened():Void {
		stage.root.raise(preferences);
		preferences.arrive();
	}

	public function sounded():Void {
		stage.root.raise(exporting);
		exporting.ask();
	}

	public function renamedPreset(which:Int):Void {
		final held = session.song.instrumentAt(which);
		if (held == null || naming == null) return;

		naming.ask(stage.root.translate(Locale.PRESET_NAME), held.name);
		naming.onName = function(said:String):Void {
			held.name = said;
			session.changed();
		};

		stage.root.raise(naming);
	}

	public function renamedTrack(which:Int):Void {
		if (naming == null || which < 0 || which >= session.song.tracks.length) return;

		final held = session.song.tracks[which];

		naming.ask(stage.root.translate(Locale.TRACK_NAME), held.name);
		naming.onName = function(said:String):Void {
			session.does(new mdd.song.edit.RenameTrack(which, said));
		};

		stage.root.raise(naming);
	}

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
			session.frees();

			session.song.rack[part.index()] = session.song.instruments.length - 1;
			session.say(said);
			session.changed();
		};

		stage.root.raise(naming);
	}
}
