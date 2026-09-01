package mdd.gate;

import haxe.ds.Vector;
import mdd.host.Canvas;
import mdd.host.Draw;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.play.Render;
import mdd.play.Stream;
import mdd.play.Transport;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.ui.Font;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.ui.Shell;
import mdd.ui.Theme;
import mdd.view.Centre;
import mdd.view.ChannelRack;
import mdd.view.Inspector;
import mdd.view.PianoRoll;
import mdd.view.Session;
import mdd.view.TransportBar;

@:unreflective
class SpineCheck {
	static inline final RATE = 48000;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  spine");

		played();
		blocks();
		looping();
		drawn(args.length > 0 ? args[0] : Gate.root);

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
		Sys.println("    " + StringTools.rpad(name, " ", 30) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function drawn(root:String):Void {
		Native.ready();

		if (Sdl.init() == 0) {
			says("the spine draws", false, "SDL would not start: " + Sdl.error());
			return;
		}

		final face = root + "/vendor/fonts/Go-Regular.ttf";
		final monoFace = root + "/vendor/fonts/Go-Mono.ttf";

		if (!sys.FileSystem.exists(face)) {
			says("the spine draws", false, "no font at " + face);
			Sdl.quit();
			return;
		}

		final window = Sdl.createWindow("mdd gate spine", 1440, 900, 0, 0);
		final renderer = Sdl.createRenderer(window, 0);

		final body = Font.bake(renderer, face, 13);
		final small = Font.bake(renderer, face, 11);
		final mono = Font.bake(renderer, monoFace, 12);

		if (body == null || small == null || mono == null) {
			says("the spine draws", false, "the fonts would not bake");
			Sdl.destroyRenderer(renderer);
			Sdl.destroyWindow(window);
			Sdl.quit();
			return;
		}

		final metrics = new Metrics(1);
		metrics.dress(body, small, mono, mono);

		final session = Session.started();
		final shell = new Shell();
		final tree = new Root(shell, metrics, new Theme());

		tree.flow = mdd.ui.Flow.None;
		tree.resize(1440, 900);
		shell.fit(metrics);

		final bar = new TransportBar(session);
		final rack = new ChannelRack(session);
		final centre = new Centre(session);
		final roll = centre.roll;
		final editor = new Inspector(session);

		shell.zone(Shell.TRANSPORT).add(bar);
		shell.zone(Shell.RAIL).add(rack);
		shell.zone(Shell.CENTRE).add(centre);
		shell.zone(Shell.INSPECTOR).add(editor);

		final pattern = session.current();
		pattern.length = 96 * 4 * 64;

		var seed = 0x51DE;
		var placed = 0;

		for (index in 0...6) {
			final part:Part = index;
			var at = index * 12;

			while (at < pattern.length - 48) {
				seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

				pattern.lane(part).add(new Note(at, 24 + (seed % 48), 40 + (seed >> 8) % 40,
					60 + (seed >> 4) % 60));

				placed++;
				at += 24 + (seed >> 12) % 72;
			}
		}

		final paint = Paint.on(renderer, body);

		Sdl.renderClear(renderer, 0, 0, 0, 1);
		tree.frame(paint);
		Sdl.renderPresent(renderer);

		final rolls = 600;
		var worst = 0.0;
		var total = 0.0;
		var first = 0.0;
		var worstAt = 0;
		var over = 0;
		var drawnNotes = 0;
		var calls = 0;

		for (frame in 0...rolls) {
			roll.scrollTo(frame * 6, roll.offsetY);
			roll.playhead = frame * 24;
			roll.invalidate();
			rack.invalidate();

			Draw.resetCalls();
			final began = Sdl.ticks();
			Sdl.renderClear(renderer, 0, 0, 0, 1);
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final spent = Sdl.ticks() - began;

			calls = Draw.calls();
			drawnNotes = roll.painted;

			if (frame == 0) first = spent;
			else {
				if (spent > worst) {
					worst = spent;
					worstAt = frame;
				}
				if (spent * 1000 > 16.67) over++;
			}

			total += spent;
		}

		final mean = total / rolls * 1000;

		says("the spine draws", drawnNotes > 0 && calls > 0,
			placed + " notes on six channels, " + drawnNotes + " of them on screen, "
			+ calls + " draw calls a frame");

		editor.show(Inspector.SCOPE);

		for (index in 0...6) {
			for (step in 0...mdd.view.Scope.SPAN) {
				editor.scope.feed(index, Math.sin(step * (index + 1) * 0.05) * (0.2 + index * 0.1));
			}
			editor.scope.sang(index, 48 + index * 5);
		}

		var scopeWorst = 0.0;

		for (frame in 0...120) {
			editor.scope.invalidate();

			Sdl.renderClear(renderer, 0, 0, 0, 1);
			final began = Sdl.ticks();
			tree.frame(paint);
			Sdl.renderPresent(renderer);
			final took = Sdl.ticks() - began;

			if (took > scopeWorst) scopeWorst = took;
		}

		says("the scope draws its lanes", editor.scope.painted == 6 && scopeWorst * 1000 < 16.67,
			editor.scope.painted + " lanes traced, worst frame " + round(scopeWorst * 1000, 3)
			+ " ms with the scope in the inspector");

		editor.show(Inspector.CHANNEL);

		says("it holds sixty a second", mean < 16.67 && worst * 1000 < 16.67,
			"mean " + round(mean, 3) + " ms a frame while scrolling, worst "
			+ round(worst * 1000, 3) + " at frame " + worstAt + ", " + over
			+ " frames of " + rolls + " over 16.67, first frame " + round(first * 1000, 1));

		body.shut();
		small.shut();
		mono.shut();

		Sdl.destroyRenderer(renderer);
		Sdl.destroyWindow(window);
		Sdl.quit();
	}

	static function heard(song:Song, frames:Int, seconds:Float,
			into:Null<Vector<cpp.Float32>>):Int {
		final render = new Render(RATE, frames);
		final transport = new Transport(song, 65536);

		render.transport = transport;
		transport.rewind();
		transport.play();

		final want = Std.int(seconds * RATE);
		var done = 0;

		while (done < want) {
			final from = transport.advance(frames, RATE);
			final many = render.serve(transport.stream, from, frames, transport.entering);

			if (into != null) {
				for (i in 0...many) {
					if ((done + i) * 2 + 1 >= into.length) break;
					into[(done + i) * 2] = render.block[i * 2];
					into[(done + i) * 2 + 1] = render.block[i * 2 + 1];
				}
			}

			done += many;
		}

		return render.writes;
	}

	static function played():Void {
		final song = StreamCheck.written();
		final seconds = 2.0;

		final sound = new Vector<cpp.Float32>(Std.int(seconds * RATE) * 2);
		for (i in 0...sound.length) sound[i] = 0;

		final began = Sdl.ticks();
		final writes = heard(song, Render.BLOCK, seconds, sound);
		final spent = Sdl.ticks() - began;

		var loudest = 0.0;
		var moved = 0;

		for (i in 0...sound.length) {
			final value = sound[i] < 0 ? -sound[i] : sound[i];
			if (value > loudest) loudest = value;
			if (value > 0.0005) moved++;
		}

		says("the song sounds", loudest > 0.001,
			writes + " register writes reached the chips and the loudest sample is "
			+ round(loudest, 4));

		says("and keeps sounding", moved > sound.length / 4,
			round(100.0 * moved / sound.length, 1) + " per cent of the samples are away from zero");

		says("it plays ahead of time", spent < seconds,
			round(seconds, 1) + " s of song rendered in " + round(spent, 2) + " s, "
			+ round(seconds / spent, 1) + " times faster than real time");

		final offline = new Stream(262144);
		final sequencer = new mdd.play.Sequencer(song);
		sequencer.emit(offline, 0, Std.int(seconds * Tempo.TICKS));

		says("what is heard is exported", writes == offline.count,
			writes + " writes played against " + offline.count + " the same span exports");
	}

	static function blocks():Void {
		final song = StreamCheck.written();
		final seconds = 1.0;
		final length = Std.int(seconds * RATE) * 2;

		final small = new Vector<cpp.Float32>(length);
		final large = new Vector<cpp.Float32>(length);

		for (i in 0...length) {
			small[i] = 0;
			large[i] = 0;
		}

		heard(song, 128, seconds, small);
		heard(song, 512, seconds, large);

		var parted = -1;
		var worst = 0.0;

		for (i in 0...length) {
			final off = small[i] - large[i];
			final size = off < 0 ? -off : off;

			if (size > worst) worst = size;
			if (size != 0 && parted < 0) parted = i;
		}

		says("the block size is not heard", parted < 0,
			parted < 0 ? "128 and 512 frame blocks render the same "
				+ Std.int(length / 2) + " frames sample for sample"
				: "they part at sample " + Std.int(parted / 2) + ", worst " + round(worst, 6));
	}

	static function looping():Void {
		final song = new Song("a loop", 96, 120);
		final pattern = song.add(new mdd.song.Pattern("one", 384));

		pattern.lane(Part.Fm1).add(new Note(0, 48, 60, 100));
		song.instrument(new mdd.song.Instrument("lead", Part.Fm1));
		song.rack[0] = 0;

		final track = song.track(new mdd.song.Track("one"));
		track.add(new mdd.song.Clip(0, 0, 384));

		final transport = new Transport(song, 8192);
		transport.rewind();
		transport.loop(0, song.tempo.samplesAt(384));
		transport.play();

		var writes = 0;
		final want = song.tempo.samplesAt(384 * 3);
		final limit = Std.int(want * (RATE / Tempo.TICKS));
		var frames = 0;

		while (frames < limit) {
			transport.advance(128, RATE);
			writes += transport.stream.count;
			frames += 128;
		}

		says("a loop comes round", transport.wrapped >= 2 && writes > 0,
			"three bars of playing wrapped " + transport.wrapped
			+ " times and made " + writes + " writes");

		says("the playhead stays inside", transport.position >= transport.loopFrom
			&& transport.position <= transport.loopTo,
			"the playhead is at " + round(transport.position / Tempo.TICKS, 3)
			+ " s inside a " + round(transport.loopTo / Tempo.TICKS, 3) + " s loop");
	}
}
