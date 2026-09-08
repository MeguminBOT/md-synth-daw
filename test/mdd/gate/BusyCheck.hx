package mdd.gate;

import mdd.app.Files;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.app.Task;
import mdd.host.Collector;
import mdd.host.Sdl;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.song.Song;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.view.overlay.Working;

@:unreflective
class BusyCheck {
	static inline final PATIENCE = 180.0;
	static inline final ALLOWED = 0.100;
	static inline final LITTER = 4000;
	static inline final SETTLED = 250;
	static inline final GROWTH = 40;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  busy");

		final root = args.length > 0 ? args[0] : Gate.root;
		final song = imported(root);

		if (song == null) {
			Sys.println("    no vgm to import, run: mdd setup");
			Sys.println("    passed");
			return 0;
		}

		if (Sdl.init() == 0) {
			Sys.println("    SDL would not start: " + Sdl.error());
			return 1;
		}

		final window = Sdl.createWindow("mdd gate busy", 1280, 800, 0, 0);
		final renderer = Sdl.createRenderer(window, 0, mdd.App.PINNED);
		final face = root + "/vendor/fonts/Go-Regular.ttf";

		if (!sys.FileSystem.exists(face)) {
			Sys.println("    no font at " + face + ", run: mdd setup");
			Sdl.quit();
			return 1;
		}

		final body = Font.bake(renderer, face, 15);

		if (body == null) {
			Sys.println("    the font would not bake");
			Sdl.quit();
			return 1;
		}

		exported(root, song, renderer, body);

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();

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
		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function imported(root:String):Null<Song> {
		final where = root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return null;

		final name = Fixtures.found("Green Hill");
		if (name == "") return null;

		final source = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);

		return mdd.format.Transcription.of(source, vgm.rate, name).song;
	}

	static function phased(reach:Float, done:Bool):String {
		if (done) return "writing the file";
		if (reach <= 0) return "the register stream";
		if (reach >= 1) return "the fade and the level pass";

		return "the render, " + Math.round(reach * 100) + " per cent in";
	}

	static function exported(root:String, song:Song, renderer:cpp.Star<Canvas>,
			body:Font):Void {
		final session = new Session(song);
		final files = new Files(session);

		final mixing = new Mixing();

		mixing.kind = Mixing.WAV;
		mixing.rate = 44100;
		mixing.padStart = 0;
		mixing.padEnd = 0;
		mixing.normalise = true;

		files.mixing = mixing;

		final into = root + "/export/gate-busy.wav";
		final task = new Task();
		final ballast:Array<Array<mdd.song.Point>> = [];

		for (index in 0...SETTLED) {
			final held:Array<mdd.song.Point> = [];
			for (one in 0...LITTER) held.push(new mdd.song.Point(one, one));

			ballast.push(held);
		}

		final metrics = new Metrics(1);

		metrics.dress(body, body, body, body);

		final held = new Root(new Shell(), metrics, new Theme());
		final paint = Paint.on(renderer, body);
		final working = new Working();
		final collector = new Collector();

		held.resize(1280, 800);

		cpp.vm.Gc.run(true);

		collector.minds();

		final rendering = files.renders(into);

		task.begins(Locale.WORKING_RENDERING, "gate", true);
		held.raise(working);
		working.arrive(task);
		held.soil();

		final began = Sdl.ticks();

		var last = began;
		var worst = 0.0;
		var worstAt = 0.0;
		var worstDone = false;
		var frames = 0;
		var peak = 0.0;
		var raised = true;
		var moved = false;
		var was = 0.0;
		var lastRaw = 0;
		var lowest = 0;
		var slipped = 0;
		final kept:Array<Array<mdd.song.Point>> = [];

		while (Sdl.ticks() - began < PATIENCE) {
			final now = Sdl.ticks();
			final since = now - last;
			last = now;

			if (frames > 0 && since > worst) {
				worst = since;
				worstAt = rendering.reach();
				worstDone = files.wroteYet();
			}

			frames++;

			held.advance(since);

			final reach = rendering.reach();
			task.holds(reach);
			working.advance(since);

			if (reach > was) {
				moved = true;
				was = reach;
			}

			final raw = rendering.reached.load();

			if (raw < lowest) lowest = raw;
			if (raw < lastRaw) slipped++;

			lastRaw = raw;

			if (held.sheet != working) raised = false;
			if (working.fade.value > peak) peak = working.fade.value;

			final litter:Array<mdd.song.Point> = [];
			for (index in 0...LITTER) litter.push(new mdd.song.Point(index, index));
			if (litter.length == 0) return;

			if (kept.length < GROWTH) kept.push(litter);

			Sdl.renderClear(renderer, 0.1, 0.1, 0.1, 1);
			held.frame(paint);
			Sdl.renderPresent(renderer);

			collector.rests(since, true);

			if (files.wroteYet()) break;

			Sdl.sleep(0.001);
		}

		final ended = rendering.reached.load();
		final over = Sdl.ticks() - began;

		says("a bounce leaves the window drawing", worst <= ALLOWED,
			"worst gap between frames " + round(worst * 1000, 1) + " ms across " + frames
			+ " frames of " + round(over, 2) + " s, during " + phased(worstAt, worstDone)
			+ "; the collector " + collector.said());

		says("and the modal is on screen while it works", peak > 0.9,
			"the sheet faded to " + round(peak, 3) + " of 1"
			+ (raised ? "" : ", and it was not the raised sheet throughout"));

		says("and the bar fills without going backwards", moved && was >= 1 && lowest >= 0
			&& slipped == 0,
			"progress ran " + lowest + " to " + ended + " of " + Mixdown.WHOLE
			+ ", " + slipped + " steps backwards"
			+ (lowest < 0 ? ", which reads as unknown and leaves the bar sweeping" : ""));

		says("and the file is written", files.wroteYet() && files.wroteWrong == ""
			&& ballast.length == SETTLED && kept.length > 0,
			files.wroteWrong == "" ? "wrote " + Math.round(size(into) / 1024) + " kb"
				: files.wroteWrong);
	}

	static function size(where:String):Float {
		return sys.FileSystem.exists(where) ? sys.FileSystem.stat(where).size : 0;
	}

	static function round(value:Float, places:Int):Float {
		final by = Math.pow(10, places);
		return Math.round(value * by) / by;
	}
}
