package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.ui.Flow;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.view.Centre;
import mdd.view.Dock;
import mdd.view.Inspector;
import mdd.view.Rail;
import mdd.app.Session;
import mdd.view.TransportBar;
import mdd.view.editor.Patterns;
import mdd.view.editor.Playlist;
import mdd.view.editor.Tracker;
import mdd.view.monitor.Registers;
import mdd.view.monitor.Scope;
import mdd.view.monitor.Warnings;
import mdd.view.overlay.Export;
import mdd.view.overlay.Preferences;

@:unreflective
class ShotCheck {
	public static function run(args:Array<String>):Int {
		final root = Gate.root;

		var into = "R:/tmp/shot.png";
		var wide = 1600;
		var tall = 1000;
		var centreTab = Centre.PLAYLIST;
		var drives = false;
		var dockTab = 0;
		var inspectorTab = Inspector.CHANNEL;
		var theme = Theme.MIDNIGHT;
		var part = 0;
		var vgm = "";
		var sheet = "";
		var lane = 0;
		var menu = -1;
		var rows = 0;
		var icons = false;

		var at = 0;

		while (at < args.length) {
			final name = args[at];
			final held = at + 1 < args.length ? args[at + 1] : "";

			switch (name) {
				case "--out": into = held; at++;
				case "--width": wide = whole(held, wide); at++;
				case "--height": tall = whole(held, tall); at++;
				case "--centre": centreTab = whole(held, centreTab); at++;
				case "--dock": dockTab = whole(held, dockTab); at++;
				case "--inspector": inspectorTab = whole(held, inspectorTab); at++;
				case "--theme": theme = whole(held, theme); at++;
				case "--part": part = whole(held, part); at++;
				case "--vgm": vgm = held; at++;
				case "--drives": drives = true;
				case "--sheet": sheet = held; at++;
				case "--lane": lane = whole(held, lane); at++;
				case "--menu": menu = whole(held, menu); at++;
				case "--rows": rows = whole(held, rows); at++;
				case "--icons": icons = true;
				case _:
			}

			at++;
		}

		Native.ready();

		if (Sdl.init() == 0) {
			Sys.println("  shot          SDL would not start: " + Sdl.error());
			return 1;
		}

		final face = root + "/vendor/fonts/Go-Regular.ttf";
		final monoFace = root + "/vendor/fonts/Go-Mono.ttf";

		final window = Sdl.createWindow("mdd shot", wide, tall, 0, 0);
		final renderer = Sdl.createRenderer(window, 0);

		final body = Font.bake(renderer, face, 15);
		final small = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 14);

		if (body == null || small == null || mono == null) {
			Sys.println("  shot          the fonts would not bake");
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			Sdl.quit();
			return 1;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, small, mono, mono);

		final session = vgm == "" ? Session.started() : imported(root, vgm);

		if (icons) {
			for (index in 0...session.song.instruments.length) {
				session.song.instruments[index].icon = index % mdd.Icon.COUNT;
			}
		}

		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme(theme));

		mdd.app.Languages.speak(tree.translation, "en-GB");
		tree.icons = mdd.ui.Icons.read(renderer, root + "/export/icons/icons-16.atlas");

		tree.flow = Flow.None;
		tree.resize(wide, tall);
		shell.fit(metrics);

		final bar = new TransportBar(session);
		final rail = new Rail(session);
		final centre = new Centre(session);
		final editor = new Inspector(session);
		final dock = new Dock(session);
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());

		budget.overSong(session.song);

		centre.roll.budget = budget;
		rail.hardware.budget = budget;
		rail.hardware.levels = rail.rack.levels;
		editor.samples.budget = budget;
		dock.warnings.budget = budget;

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(editor);
		shell.zone(Shell.DOCK).add(dock);

		final menus = new mdd.ui.control.MenuBar();

		final entries:Array<Array<String>> = [
			["Open a song|Ctrl+O", "Save|Ctrl+S", "Save as", "-", "Look for an update",
				"-", "Preferences|Ctrl+,", "-", "Quit|Alt+F4"],
			["Undo|Ctrl+Z", "Redo|Ctrl+Y", "-", "Play|Space", "Stop|Ctrl+Space"],
			["Add a pattern", "Duplicate this pattern", "Rename this pattern",
				"Put it on the playlist", "Delete this pattern", "-", "Empty this pattern",
				"-", "Patterns"],
			["Unmute every channel", "Unsolo every channel", "-", "Mute the rest",
				"-", "Clear this channel"],
			["Copy this patch", "Paste a patch", "Reset this patch", "-",
				"Save this channel as a preset", "Bank"],
			["Read a vgm", "Read a midi file", "Read a wav"],
			["Write a vgm|Ctrl+E", "Render a wav", "Write a midi file"],
			["Piano roll", "Scope", "Tracker", "Playlist", "Registers", "-", "Patterns",
				"Warnings", "-", "Snap to the grid", "Show other channels"],
			["About", "Source"]
		];

		final titles = ["File", "Edit", "Pattern", "Channels", "Instrument", "Import",
			"Export", "View", "Help"];

		for (index in 0...titles.length) {
			final held = new mdd.ui.control.Menu();

			for (line in entries[index]) {
				if (line == "-") {
					held.divide();
					continue;
				}

				final split = line.split("|");
				held.offer(new mdd.ui.control.Choice(split[0],
					split.length > 1 ? split[1] : ""));
			}

			menus.offer(titles[index], held);
		}

		menus.trailing.push("Open");
		menus.trailing.push("Save");
		menus.trailing.push("Preferences");
		shell.zone(Shell.MENU).add(menus);

		session.choose(part);

		for (index in 0...lane) {
			final held = mdd.view.Parameter.of(session.part);
			if (index >= held.length) break;

			centre.roll.stack.show(held[index].target, 0);
		}

		centre.playlist.rowTall = rows;
		if (drives) driving(session);

		if (centreTab == Centre.AUTOMATION) {
			for (track in session.song.tracks) {
				for (found in track.clips) {
					if (found.drawn()) centre.automation.follows(found);
				}
			}
		}

		centre.show(centreTab);
		editor.show(inspectorTab);
		dock.show(dockTab);
		dock.said = "ready";

		for (index in 0...mdd.song.Part.COUNT) {
			rail.rack.levels[index] = 0.15 + (index % 5) * 0.17;
		}

		if (sheet == "preferences") {
			final held = new mdd.view.overlay.Preferences(session);

			held.speaks(mdd.app.Languages.shipped(), "en-GB");
			tree.raise(held);
			held.arrive();
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "welcome") {
			final held = new mdd.view.overlay.Welcome(session);

			tree.raise(held);
			held.arrive("en-GB");
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "export" || sheet == "export-opus") {
			final held = new mdd.view.overlay.Export(session);

			if (sheet == "export-opus") {
				held.mixing.kind = mdd.play.Mixing.OPUS;
				held.mixing.rate = 48000;
			}

			held.mixing.artist = "MeguminBOT";
			held.mixing.album = "Mega Drive";
			held.mixing.year = "2026";

			tree.raise(held);
			held.ask();
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "working" || sheet == "working-bar") {
			final held = new mdd.view.overlay.Working();
			final task = new mdd.app.Task();

			task.begins(mdd.app.Locale.WORKING_RENDERING, "green hill zone.wav", true);
			if (sheet == "working-bar") task.holds(0.42);

			tree.raise(held);
			held.arrive(task);
			held.fade.hold(1);
			held.rise.hold(1);
		} else if (sheet == "naming") {
			final held = new mdd.view.overlay.Naming();

			held.ask("Preset name", "Brass section");
			tree.raise(held);
		}

		final texture = Draw.createTarget(renderer, wide, tall);
		final paint = Paint.on(renderer, body);

		if (menu >= 0) {
			tree.frame(paint);
			menus.open(menu);

			for (step in 0...12) {
				tree.advance(0.05);
				tree.frame(paint);
			}
		}

		Draw.setTarget(renderer, texture);

		final ground = tree.theme.ground;
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);

		tree.reshape();
		tree.frame(paint);
		paint.flush();

		final pixels = new Vector<cpp.UInt8>(wide * tall * 4);

		Draw.readPixels(renderer, 0, 0, wide, tall,
			cpp.Pointer.arrayElem(pixels.toData(), 0).raw);

		Draw.setTarget(renderer, null);

		sys.io.File.saveBytes(into, Png.write(pixels, wide, tall));
		Sys.println("  shot          " + wide + "x" + tall + " to " + into);

		body.shut();
		small.shut();
		mono.shut();

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();

		return 0;
	}

	static function driving(session:mdd.app.Session):Void {
		final song = session.song;
		final bar = song.tempo.ppqn * 4;

		final shapes = [mdd.song.Automation.LINEAR, mdd.song.Automation.WAVE,
			mdd.song.Automation.STAIRS];

		final drives = [mdd.song.Automation.LEVEL, mdd.song.Automation.TUNE,
			mdd.song.Automation.LEVEL];

		final parts = [mdd.song.Part.Fm1, mdd.song.Part.Psg1, mdd.song.Part.Fm3];

		for (index in 0...3) {
			final track = song.track(new mdd.song.Track("automation"));
			final clip = mdd.song.Clip.drives(parts[index], drives[index], 0,
				bar * (index + 1), bar * 6);

			final line = clip.line;
			if (line == null) continue;

			final held = mdd.view.Parameter.found(parts[index], drives[index], 0);
			final low = held == null ? -40 : Std.int(held.low * 0.4);
			final high = held == null ? 40 : Std.int(held.high * 0.4);

			final from = new mdd.song.Point(0, low);
			from.shape = shapes[index];
			from.steps = 5;

			final middle = new mdd.song.Point(bar * 3, high);
			middle.shape = shapes[index];
			middle.steps = 5;

			line.add(from);
			line.add(middle);
			line.add(new mdd.song.Point(bar * 6, low));

			track.add(clip);
		}

		session.changed();
	}

	static function whole(said:String, fallback:Int):Int {
		final held = Std.parseInt(said);
		return held == null ? fallback : held;
	}

	static function imported(root:String, name:String):Session {
		final where = root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return Session.started();

		for (held in sys.FileSystem.readDirectory(where)) {
			if (held.indexOf(name) < 0) continue;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + held), stream);

			return new Session(mdd.format.Transcription.of(stream, vgm.rate, held).song);
		}

		return Session.started();
	}
}
