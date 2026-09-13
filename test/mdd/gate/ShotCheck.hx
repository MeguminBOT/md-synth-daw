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
import mdd.view.Status;
import mdd.view.Inspector;
import mdd.view.Rail;
import mdd.app.Session;
import mdd.view.TransportBar;
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

		var into = root + "/export/shot.png";
		var wide = 1600;
		var tall = 1000;
		var centreTab = Centre.PLAYLIST;
		var drives = false;
		var drums = false;
		var dockTab = 0;
		var inspectorTab = Inspector.CHANNEL;
		var theme = Theme.MIDNIGHT;
		var part = 0;
		var vgm = "";
		var lang = "en-GB";
		var sheet = "";
		var lane = 0;
		var group = 0;
		var menu = -1;
		var rows = 0;
		var icons = false;
		var point = false;
		var typing = false;
		var traced = false;
		var direct = false;
		var backend = mdd.App.PINNED;
		var frames = 1;

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
				case "--lang": lang = held; at++;
				case "--drives": drives = true;
				case "--drums": drums = true;
				case "--sheet": sheet = held; at++;
				case "--lane": lane = whole(held, lane); at++;
				case "--group": group = whole(held, group); at++;
				case "--menu": menu = whole(held, menu); at++;
				case "--rows": rows = whole(held, rows); at++;
				case "--icons": icons = true;
				case "--point": point = true;
				case "--typing": typing = true;
				case "--traced": traced = true;
				case "--direct": direct = true;
				case "--renderer": backend = held; at++;
				case "--frames": frames = whole(held, frames); at++;
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
		final renderer = Sdl.createRenderer(window, 0, backend);

		if (renderer != null && backend != "") {
			final got = (Sdl.rendererName(renderer) : String);
			if (got != backend) {
				Sys.println("  shot          asked for " + backend + " and got " + got);
			}
		}

		final body = Font.bake(renderer, face, 15);
		final small = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 14);

		final condensed = mdd.Typeface.CONDENSED == "" ? null
			: Font.bake(renderer, root + "/vendor/fonts/" + mdd.Typeface.CONDENSED, 13);

		if (body == null || small == null || mono == null) {
			Sys.println("  shot          the fonts would not bake");
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			Sdl.quit();
			return 1;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, small, mono, mono, condensed);

		final session = vgm == "" ? Session.started(mdd.song.Library.embedded()) : imported(root, vgm);

		if (drums) {
			final song = session.song;
			song.drums = true;

			for (at in 0...song.banks.length) {
				final bank = song.banks[at];
				if (bank.instruments.length < 2) continue;

				final first = bank.instruments[0];
				final held = song.instrumentAt(first);

				if (held == null || !held.kind.sampled()) continue;

				song.rack[mdd.song.Part.Dac.index()] = first;
				break;
			}
		}

		if (icons) {
			for (index in 0...session.song.instruments.length) {
				session.song.instruments[index].icon = index % mdd.Icon.COUNT;
			}
		}

		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme(theme));

		mdd.app.Languages.speak(tree.translation, lang);
		tree.icons = mdd.ui.Icons.read(renderer, root + "/export/icons/icons-16.atlas");

		tree.flow = Flow.None;
		tree.resize(wide, tall);
		shell.fit(metrics);

		final bar = new TransportBar(session);
		final rail = new Rail(session);
		final centre = new Centre(session);
		final editor = new Inspector(session);
		final dock = new Status(session, centre.warnings);
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());

		budget.overSong(session.song);

		centre.roll.budget = budget;
		if (drums) centre.roll.offsetY = 48 * centre.roll.rowTall;
		rail.hardware.budget = budget;
		rail.hardware.levels = rail.rack.levels;
		editor.samples.budget = budget;
		centre.warnings.budget = budget;

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rail);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(editor);
		shell.zone(Shell.STATUS).add(dock);

		final menus = new mdd.ui.control.MenuBar();

		final entries:Array<Array<String>> = [
			["New project|Ctrl+N", "Open a song|Ctrl+O", "Save|Ctrl+S", "Save as", "-",
				"Look for an update",
				"-", "Preferences|Ctrl+,", "-", "Quit|Alt+F4"],
			["Undo|Ctrl+Z", "Redo|Ctrl+Y", "-", "Nudge everything earlier|Ctrl+Left",
				"Nudge everything later|Ctrl+Right", "-", "Play|Space", "Stop|Ctrl+Space"],
			["Add a pattern", "Duplicate this pattern", "Rename this pattern",
				"Put it on the playlist", "Delete this pattern", "-", "Play it on",
				"-", "Empty this pattern",
				"-", "Patterns"],
			["Unmute every channel", "Unsolo every channel", "-", "Mute the rest",
				"-", "Clear this channel"],
			["Copy this patch", "Paste a patch", "Reset this patch", "-",
				"Save this channel as a preset", "Bank"],
			["Read a vgm", "Read a midi file", "Read a wav"],
			["Write a vgm|Ctrl+E", "Render a wav", "Write a midi file"],
			["Play through a driver"],
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

		if (lane > 0) centre.roll.shows(lane);

		centre.playlist.rowTall = rows;
		if (drives) driving(session);


		if (centreTab == Centre.AUTOMATION) {
			for (track in session.song.tracks) {
				for (found in track.clips) {
					if (found.automates()) centre.automation.follows(found);
				}
			}
		}

		centre.show(centreTab);
		editor.show(inspectorTab);

		if (dockTab > 0) centre.show(mdd.view.Centre.WARNINGS);
		dock.said = "ready";
		dock.usage = "cpu 4%   ram 182 MB   gpu 2%   ring 69 ms";

		for (index in 0...mdd.song.Part.COUNT) {
			rail.rack.levels[index] = 0.15 + (index % 5) * 0.17;
		}

		if (sheet == "preferences") {
			final held = new mdd.view.overlay.Preferences(session);

			held.speaks(mdd.app.Languages.shipped(), "en-GB");

			held.keyboards.push("None");
			held.keyboards.push("Microsoft GS Wavetable Synth");
			held.bindings = new mdd.app.Bindings();

			final controls = new mdd.app.Mapping();

			controls.drives(0, mdd.app.Mapping.OPERATOR, 3, 0);
			controls.hears(0, 74);
			controls.drives(1, mdd.app.Mapping.DIAL, 0, mdd.song.Patch.FEEDBACK);
			controls.hears(1, 71);

			held.mapping = controls;
			held.shows(group);
			tree.raise(held);
			held.arrive();
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "kitting") {
			final held = new mdd.view.overlay.Kitting();
			final kit = new mdd.format.Kit();

			kit.reads(vgm == "" ? root + "/vendor/drum kits/Metal Kit" : vgm);
			kit.detects();
			kit.converts();

			tree.raise(held);
			held.ask(kit);
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "welcome") {
			final held = new mdd.view.overlay.Welcome(session);

			tree.raise(held);
			held.arrive(lang);
			held.rise.hold(1);
			held.fade.hold(1);
		} else if (sheet == "export" || sheet == "export-opus" || sheet == "export-webm") {
			final held = new mdd.view.overlay.Export(session, sheet == "export-webm");

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
		} else if (sheet == "about") {
			final held = new mdd.view.overlay.About();

			tree.raise(held);
			held.arrive();
			held.rise.hold(1);
			held.fade.hold(1);
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

		if (traced && centreTab == Centre.SCOPE) {
			for (index in 0...6) {
				for (step in 0...mdd.view.monitor.Scope.SPAN) {
					centre.scope.feed(index, Math.sin(step * (index + 1) * 0.05)
						* (0.2 + index * 0.1));
				}

				centre.scope.sang(index, 48 + index * 5);
			}
		}

		if (typing && centreTab == Centre.TRACKER) {
			final pattern = session.current();

			if (pattern != null && session.song.ends() < pattern.length) {
				session.song.tracks[0].add(new mdd.song.Clip(session.pattern, 0,
					pattern.length));
			}

			tree.reshape();
			tree.top.measure(tree.width, tree.height);
			tree.top.arrange(0, 0, tree.width, tree.height);

			centre.tracker.at(6, mdd.song.Part.Fm3.index());
			centre.tracker.opens();

			for (index in 0..."C#5 3".length) {
				final event = new mdd.ui.Input();
				event.typed("C#5 3".charAt(index), mdd.ui.Mod.None);

				centre.tracker.took(event);
			}
		}

		if (point) {
			tree.reshape();
			tree.top.measure(tree.width, tree.height);
			tree.top.arrange(0, 0, tree.width, tree.height);

			final stack = centre.roll.stack;

			for (row in 0...stack.rows()) {
				final line = stack.lineOf(row);
				if (line == null || line.points.length < 1) continue;

				stack.picks(line.points[line.points.length > 1 ? 1 : 0], row);
				break;
			}
		}

		final film = sheet == "film" || sheet == "film-spectrum" ? filmed(tree, session, wide, tall)
			: null;

		if (film != null && sheet == "film-spectrum") film.shows(Scope.SPECTRUM);

		if (!direct) Draw.setTarget(renderer, texture);

		final ground = tree.theme.ground;

		for (pass in 0...frames) {
			if (film != null) {
				Sdl.renderClear(renderer, 0, 0, 0, 1);

				paint.reset();
				film.films(paint, FILMED);
				paint.flush();

				continue;
			}

			Sdl.renderClear(renderer, ground.red / 255, ground.green / 255,
				ground.blue / 255, 1);

			tree.reshape();
			tree.soil();
			tree.frame(paint);
			paint.flush();

			if (direct && pass < frames - 1) Sdl.renderPresent(renderer);
		}

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

	/**
		Every part, in the order a video lays them out.
	**/
	static final FILMED:Array<Int> = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

	/**
		A scope the size of the shot, for the film sheet, which draws it the way a video does.
		Every part is fed a wave of its own, sine, square or saw at its own pitch and loudness,
		except the last, which is left silent to show the flat line a quiet lane keeps.

		@param tree The root the scope borrows its theme and sizes from.
		@param session The session the scope reads.
		@param wide The shot's width.
		@param tall The shot's height.
		@return The scope, hidden, so the tree does not draw it as well.
	**/
	static function filmed(tree:Root, session:Session, wide:Int, tall:Int):Scope {
		final scope = new Scope(session);

		scope.visible = false;
		tree.top.add(scope);
		scope.arrange(0, 0, wide, tall);

		for (part in 0...mdd.song.Part.COUNT - 1) {
			final turn = (part + 1) * 0.02;
			final loudness = 0.3 + part * 0.06;

			for (step in 0...Scope.SPAN) {
				final phase = step * turn;
				final cycle = (phase / (Math.PI * 2)) % 1;

				final value = switch (part % 3) {
					case 0: Math.sin(phase);
					case 1: cycle < 0.5 ? 1.0 : -1.0;
					case _: cycle * 2 - 1;
				}

				scope.feed(part, value * loudness);
			}
		}

		return scope;
	}

	static function whole(said:String, fallback:Int):Int {
		final held = Std.parseInt(said);
		return held == null ? fallback : held;
	}

	static function imported(root:String, name:String):Session {
		final held = Fixtures.found(name);
		if (held == "") return Session.started(mdd.song.Library.embedded());

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(held), stream);

		return new Session(mdd.format.Transcription.of(stream, vgm.rate,
			Fixtures.titled(held)).song);
	}
}
