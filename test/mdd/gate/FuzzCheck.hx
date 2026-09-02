package mdd.gate;

import mdd.host.Native;
import mdd.host.Sdl;
import mdd.song.Note;
import mdd.song.Part;
import mdd.ui.Font;
import mdd.ui.Key;
import mdd.ui.Metrics;
import mdd.ui.Mod;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.view.Centre;
import mdd.view.ChannelRack;
import mdd.view.Dock;
import mdd.view.Inspector;
import mdd.view.Session;
import mdd.view.TransportBar;

@:unreflective
class FuzzCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  fuzz");

		final at = args.indexOf("--rounds");
		final rounds = at >= 0 && at + 1 < args.length
			? Std.parseInt(args[at + 1]) : 40000;

		final sown = args.indexOf("--seed");
		if (sown >= 0 && sown + 1 < args.length) {
			final held = Std.parseInt(args[sown + 1]);
			if (held != null) seed = held;
		}

		hammered(rounds == null ? 40000 : rounds, args);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static var seed:Int = 0x2F19;

	static function next(most:Int):Int {
		seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
		return most <= 0 ? 0 : (seed >> 7) % most;
	}

	static function seeded(root:String):Session {
		final where = root + "vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return Session.started();

		for (name in sys.FileSystem.readDirectory(where)) {
			if (name.indexOf("Green Hill") < 0) continue;

			final stream = new mdd.play.Stream(1 << 22);
			final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(where + "/" + name),
				stream);

			return new Session(mdd.format.Transcription.of(stream, vgm.rate, name).song);
		}

		return Session.started();
	}

	static function hammered(rounds:Int, args:Array<String>):Void {
		Native.ready();

		if (Sdl.init() == 0) {
			says("the roll survives being used", false, "SDL would not start: " + Sdl.error());
			return;
		}

		final root = Sys.getCwd();
		final face = root + "vendor/fonts/Go-Regular.ttf";
		final monoFace = root + "vendor/fonts/Go-Mono.ttf";

		if (!sys.FileSystem.exists(face)) {
			says("the roll survives being used", false, "no font at " + face);
			Sdl.quit();
			return;
		}

		final window = Sdl.createWindow("mdd gate fuzz", 1440, 900, 0, 0);
		final renderer = Sdl.createRenderer(window, 0);

		final body = Font.bake(renderer, face, 15);
		final small = Font.bake(renderer, face, 13);
		final mono = Font.bake(renderer, monoFace, 14);

		if (body == null || small == null || mono == null) {
			says("the roll survives being used", false, "the fonts would not bake");
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			Sdl.quit();
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, small, mono, mono);

		final session = seeded(root);
		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme());

		tree.flow = mdd.ui.Flow.None;
		tree.resize(1440, 900);
		shell.fit(metrics);

		final centre = new Centre(session);
		final roll = centre.roll;
		final budget = new mdd.check.Budget(mdd.check.Profile.megaDrive());

		roll.budget = budget;

		shell.zone(Shell.TRANSPORT).add(new TransportBar(session));
		shell.zone(Shell.RAIL).add(new ChannelRack(session));
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(new Inspector(session));
		shell.zone(Shell.DOCK).add(new Dock(session));

		final menus = new mdd.ui.control.MenuBar();
		final file = new mdd.ui.control.Menu();

		file.offer(new mdd.ui.control.Choice("One"));
		file.offer(new mdd.ui.control.Choice("Two"));
		file.divide();
		file.offer(new mdd.ui.control.Choice("Three"));

		menus.offer("File", file);
		menus.trailing.push("Open");
		shell.zone(Shell.MENU).add(menus);

		final pattern = session.current();

		if (pattern.notes() == 0) {
			pattern.length = 96 * 4 * 32;

			for (index in 0...Part.COUNT) {
				final part:Part = index;
				var when = index * 9;

				while (when < pattern.length - 48) {
					pattern.lane(part).add(new Note(when, 24 + next(72), 36 + next(48),
						40 + next(80)));
					when += 24 + next(96);
				}
			}
		}

		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
		final alive = new haxe.atomic.AtomicInt(1);
		final blocks = new haxe.atomic.AtomicInt(0);

		render.transport = session.transport;
		session.transport.play();

		final threaded = args.indexOf("--still") < 0;

		final quiet = args.indexOf("--silent") >= 0;

		if (threaded) sys.thread.Thread.create(function():Void {
			while (alive.load() == 1) {
				if (quiet) {
					render.fill(mdd.play.Render.BLOCK);
					blocks.add(1);
					continue;
				}

				final at = session.transport.advance(mdd.play.Render.BLOCK, 44100);
				render.serve(session.transport.stream, at, mdd.play.Render.BLOCK,
					session.transport.entering);
				blocks.add(1);
			}
		});

		final paint = Paint.on(renderer, body);
		final keys:Array<Key> = [Key.Left, Key.Right, Key.Up, Key.Down, Key.Delete, Key.Return,
			Key.Escape, Key.Home, Key.End, Key.Space];

		var painted = 0;
		var events = 0;

		final loud = args.indexOf("--say") >= 0;
		final held = args.indexOf("--tab");
		final pinned = held >= 0 && held + 1 < args.length
			? Std.parseInt(args[held + 1]) : -1;

		if (pinned != null && pinned >= 0) centre.show(pinned);

		for (round in 0...rounds) {
			final px = next(1440);
			final py = next(900);
			final kind = next(14);

			if (loud && round + 8 >= rounds) {
				Sys.println("      round " + round + " kind " + kind + " at " + px + "," + py
					+ " tab " + centre.showing + " part " + session.part.index()
					+ " pattern " + session.pattern);
			}

			switch (kind) {
				case 0:
					tree.turned(px, py, next(4) == 0 ? Mod.Ctrl
						: (next(3) == 0 ? Mod.Shift : Mod.None));

				case 1, 2, 3:
					tree.pressed(px, py, Pointer.Left, Mod.None, next(8) == 0 ? 2 : 1);

					var atX = px;
					var atY = py;

					for (step in 0...2 + next(30)) {
						atX += next(40) - 20;
						atY += next(30) - 15;
						tree.moved(atX, atY, next(6) == 0 ? Mod.Shift : Mod.None);
					}

					tree.released(atX, atY, Pointer.Left, Mod.None);

				case 4:
					tree.pressed(px, py, Pointer.Right, Mod.None);
					tree.released(px, py, Pointer.Right, Mod.None);
					tree.dismiss();

				case 5:
					tree.pressed(px, py, Pointer.Middle, Mod.None);
					tree.moved(px + next(300) - 150, py + next(200) - 100, Mod.None);
					tree.released(px, py, Pointer.Middle, Mod.None);

				case 6:
					tree.moved(px, py, Mod.None);

				case 7:
					final code = keys[next(keys.length)];
					tree.key(true, code, next(5) == 0 ? Mod.Ctrl : Mod.None);
					tree.key(false, code, Mod.None);

				case 8:
					centre.show(pinned >= 0 ? pinned : next(Centre.TABS));

				case 9:
					session.choose(next(Part.COUNT));

				case 10:
					tree.resize(900 + next(700), 620 + next(500));
					shell.fit(metrics);

				case 11:
					tree.said(String.fromCharCode(48 + next(10)), Mod.None);

				case 12:
					session.chooses(next(session.song.patterns.length));

				case _:
					if (next(2) == 0) session.transport.play();
					else session.transport.stop();
			}

			events++;

			if (round % 7 != 0) continue;

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			painted++;
		}

		alive.store(0);
		Sys.sleep(0.05);

		final nested = paint.nesting();
		var notes = 0;

		for (index in 0...Part.COUNT) notes += pattern.lane(index).notes.length;

		says("the roll survives being used", nested == 0,
			events + " random events over the shell with " + notes + " notes in the pattern, "
			+ painted + " frames drawn while the render thread served " + blocks.load()
			+ " blocks, " + nested + " clips left on the stack");

		paint.flush();

		body.shut();
		small.shut();
		mono.shut();

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();
	}
}
