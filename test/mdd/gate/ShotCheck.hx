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
import mdd.view.Session;
import mdd.view.TransportBar;

@:unreflective
class ShotCheck {
	public static function run(args:Array<String>):Int {
		final root = Gate.root;

		var into = "R:/tmp/shot.png";
		var wide = 1600;
		var tall = 1000;
		var centreTab = Centre.PLAYLIST;
		var dockTab = 0;
		var inspectorTab = Inspector.CHANNEL;
		var theme = Theme.MIDNIGHT;
		var part = 0;
		var vgm = "";
		var sheet = "";
		var lane = 0;
		var menu = -1;

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
				case "--sheet": sheet = held; at++;
				case "--lane": lane = whole(held, lane); at++;
				case "--menu": menu = whole(held, menu); at++;
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
		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme(theme));

		mdd.view.Languages.speak(tree.translation, "en-GB");

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
				"Mixer", "Warnings", "-", "Snap to the grid", "Show other channels"],
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
		centre.roll.showsLane(lane);
		centre.show(centreTab);
		editor.show(inspectorTab);
		dock.show(dockTab);
		dock.said = "ready";

		for (index in 0...mdd.song.Part.COUNT) {
			rail.rack.levels[index] = 0.15 + (index % 5) * 0.17;
		}

		if (sheet == "preferences") {
			final held = new mdd.view.Preferences(session);

			held.speaks(mdd.view.Languages.shipped(), "en-GB");
			tree.raise(held);
			held.arrive();
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "welcome") {
			final held = new mdd.view.Welcome(session);

			tree.raise(held);
			held.arrive("en-GB");
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "export") {
			final held = new mdd.view.Export(session);

			held.mixing.artist = "MeguminBOT";
			held.mixing.album = "Mega Drive";
			held.mixing.year = "2026";

			tree.raise(held);
			held.ask();
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "naming") {
			final held = new mdd.view.Naming();

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
