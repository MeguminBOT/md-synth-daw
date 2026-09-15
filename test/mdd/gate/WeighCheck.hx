package mdd.gate;

import haxe.atomic.AtomicInt;
import mdd.format.Midi;
import mdd.format.Vgm;
import mdd.format.Xgm;
import mdd.host.Usage;
import mdd.play.Mixdown;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Automation;
import mdd.song.Clip;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Point;
import mdd.song.Shipped;
import mdd.song.Song;
import mdd.song.Track;

/**
	What the heavy paths cost, measured rather than reasoned about.

	The machines this has to fit on are the small ones: a Raspberry Pi, a phone, anything
	where a few hundred megabytes is the whole budget rather than a rounding error. Nothing
	else here measures that, because every other program works on a fixture a few seconds
	long, and the cost of an import or an export is not a constant. It grows with the length
	of the piece, and the two buffers that grow fastest are allocated whole rather than in
	pieces, so the peak is what decides whether a machine can run it at all.

	The figure that matters is the high water mark inside a phase, not what is held once the
	phase is over. A phase that reserves half a gigabyte and gives it back looks free from
	the outside and is not, so a thread samples the process while each one runs.
**/
@:unreflective
class WeighCheck {
	/**
		How long a piece to build when nothing says otherwise.
	**/
	static inline final MINUTES = 15.0;

	/**
		Beats a minute for the piece that gets built.
	**/
	static inline final BEATS = 150.0;

	/**
		How often a note lands on each part, in ticks. A sixteenth at 96 ppqn.
	**/
	static inline final EVERY = 24;

	/**
		How often an automation point lands, in ticks. A lane stops taking them at
		`Automation.ROOM`, so a long piece fills every lane it is given.
	**/
	static inline final POINT = 96;

	static var failed:Int = 0;
	static var ran:Int = 0;

	static var began:Float = 0;
	static var baseline:Float = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		final asked = number(args, "--minutes", MINUTES);
		final minutes = asked <= 0 ? MINUTES : asked;
		final ceiling = number(args, "--ceiling", 0);

		Sys.println("  weigh");

		baseline = settled();

		Sys.println("    " + say(minutes) + " minutes at " + Std.int(BEATS) + " bpm, "
			+ Part.COUNT + " parts, from a floor of " + say(baseline) + " MB");
		Sys.println("");
		Sys.println("    " + pad("phase", 28) + pad("time", 10) + pad("peak", 12)
			+ pad("held after", 12) + "what came out");

		final song = new Song("weigh", 96, BEATS);
		Shipped.into(song);

		final ticks = Std.int(minutes * BEATS * song.tempo.ppqn);

		var notes = 0;
		var lanes = 0;

		weighed("building the piece", function():String {
			notes = filled(song, ticks);
			lanes = lined(song, ticks);

			return notes + " notes, " + lanes + " automation lanes";
		});

		final span = song.tempo.samplesAt(ticks);
		final room = Mixdown.roomFor(span);

		var stream:Null<Stream> = null;

		weighed("reserving the stream", function():String {
			stream = new Stream(room);
			return room + " writes of room, " + say(room * 4 * 4 / 1048576) + " MB of vectors";
		});

		final made = stream;
		if (made == null) return 1;

		weighed("sequencing it", function():String {
			final lost = new Sequencer(song, null, Sequencer.CHUNK).spanned(made, 0, span);

			return made.count + " writes"
				+ (made.dropped > 0 ? ", " + made.dropped + " DROPPED for want of room" : "")
				+ (lost > 0 ? ", " + lost + " lost" : "");
		});

		says("the stream held every write it was given", made.dropped == 0,
			made.dropped == 0 ? made.count + " writes, none dropped"
				: made.dropped + " writes dropped: " + room + " was not enough room");

		weighed("writing a vgm", function():String {
			final out = Vgm.write(made, 0, span, song.tempo.rate, song.name, "");
			return out.length + " bytes";
		});

		weighed("writing an xgm", function():String {
			final out = Xgm.write(song, made, 0, span, song.tempo.rate).written;
			return out == null ? "nothing" : out.length + " bytes";
		});

		weighed("a midi round trip", function():String {
			final written = Midi.write(song);
			final back = Midi.read(written, "weigh");

			return written.length + " bytes out, " + counted(back) + " notes back";
		});

		if (args.indexOf("--bounce") >= 0) {
			weighed("the audio a bounce holds", function():String {
				final frames = span;
				final held = new haxe.ds.Vector<cpp.Float32>(frames * 2);

				held[0] = 1;
				held[held.length - 1] = 1;

				return frames + " frames, stereo, "
					+ say(held.length * 4 / 1048576) + " MB in one block";
			});
		}

		imported(args);

		if (args.indexOf("--video") >= 0) filmed(args);

		Sys.println("");
		Sys.println("    the most held at once was " + say(Usage.peak()) + " MB");

		if (ceiling > 0) {
			says("nothing went past the ceiling", Usage.peak() <= ceiling,
				say(Usage.peak()) + " MB against a ceiling of " + say(ceiling) + " MB");
		}

		Sys.println("");
		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		Encodes the same frames again at each thread count, to find where the encoder stops
		getting anything back for another processor.

		The picture is what a scope video actually is: thin bright traces on black, which is
		the case VP9 finds hardest and the case the tile columns are chosen for. Frames are
		drawn once and fed from memory, so what is being timed is the encoder rather than
		the drawing.

		@param args What the program was run with.
	**/
	static function filmed(args:Array<String>):Void {
		final wide = Std.int(number(args, "--wide", 1920));
		final tall = Std.int(number(args, "--tall", 1080));
		final many = Std.int(number(args, "--frames", 120));

		Sys.println("");
		Sys.println("    encoding " + many + " frames of " + wide + " by " + tall
			+ ", thin traces on black, at each thread count");
		Sys.println("");
		Sys.println("    " + pad("threads", 12) + pad("time", 12) + pad("frames a second", 18)
			+ "against one");

		final frames:Array<haxe.io.Bytes> = [];

		for (step in 0...8) {
			final held = haxe.io.Bytes.alloc(wide * tall * 4);
			traced(held, wide, tall, step);
			frames.push(held);
		}

		var alone = 0.0;

		for (count in [1, 2, 4, 8, 12, 16, 20, 24]) {
			final where = Gate.root + "/export/weigh-" + count + ".webm";
			final file = mdd.host.Video.open(where, wide, tall, 60, 6000, mdd.play.Mixing.VBR,
				30, 7, 120, 1, 0, 48000, 2, 96, count);

			if (file == null) {
				Sys.println("    " + pad("" + count, 12) + "the writer would not open");
				continue;
			}

			final began = haxe.Timer.stamp();

			for (index in 0...many) {
				final held = frames[index % frames.length];

				if (mdd.host.Video.frame(file,
					cpp.Pointer.arrayElem(held.getData(), 0).constRaw) != 0) break;
			}

			mdd.host.Video.close(file);

			final spent = haxe.Timer.stamp() - began;
			final rate = spent <= 0 ? 0 : many / spent;

			if (alone == 0) alone = rate;

			Sys.println("    " + pad("" + count, 12) + pad(round(spent, 2) + " s", 12)
				+ pad(round(rate, 1) + " fps", 18)
				+ (alone <= 0 ? "" : round(rate / alone, 2) + " times"));

			try {
				if (sys.FileSystem.exists(where)) sys.FileSystem.deleteFile(where);
			} catch (e:Dynamic) {}
		}
	}

	/**
		Draws thin bright traces on black, moved along by one step.

		@param into The frame, four bytes a pixel.
		@param wide How wide it is.
		@param tall How tall it is.
		@param step Which frame of the loop this is.
	**/
	static function traced(into:haxe.io.Bytes, wide:Int, tall:Int, step:Int):Void {
		for (index in 0...into.length) into.set(index, index % 4 == 3 ? 255 : 0);

		for (lane in 0...9) {
			final base = Std.int((lane + 0.5) * tall / 9);
			final hue = (lane * 40) % 256;

			for (x in 0...wide) {
				final wave = Math.sin((x + step * 24) * 0.01 + lane) * (tall / 24);
				final y = base + Std.int(wave);

				for (thick in 0...3) {
					final at = y + thick;
					if (at < 0 || at >= tall) continue;

					final pixel = (at * wide + x) * 4;

					into.set(pixel, 255 - hue);
					into.set(pixel + 1, hue);
					into.set(pixel + 2, 200);
				}
			}
		}
	}

	/**
		Reads the largest register log in the corpus, or every one of them where asked.

		@param args What the program was run with.
	**/
	static function imported(args:Array<String>):Void {
		final files = Fixtures.corpus();

		if (files.length == 0) {
			Sys.println("    " + pad("importing a log", 28) + "no corpus to read");
			return;
		}

		var biggest = files[0];

		for (name in files) {
			if (sys.FileSystem.stat(name).size > sys.FileSystem.stat(biggest).size) {
				biggest = name;
			}
		}

		weighed("the largest log imported", function():String return read(biggest));

		if (args.indexOf("--all") < 0) return;

		var worst = 0.0;
		var worstAt = "";

		for (name in files) {
			final was = settled();
			final gauge = new Gauge();

			read(name);

			final cost = gauge.stop() - was;

			if (cost <= worst) continue;

			worst = cost;
			worstAt = Fixtures.titled(name);
		}

		Sys.println("    " + pad("the whole corpus", 28) + pad("", 10)
			+ pad("+" + say(worst), 12) + pad("", 12) + files.length + " logs, worst " + worstAt);
	}

	/**
		@param where A register log.
		@return What reading and transcribing it produced.
	**/
	static function read(where:String):String {
		final stream = new Stream(1 << 22);
		final vgm = Vgm.read(mdd.format.Gzip.opened(sys.io.File.getBytes(where)), stream);
		final made = mdd.format.Transcription.of(stream, vgm.rate, where);

		return Fixtures.titled(where) + ", " + stream.count + " writes, " + made.notes + " notes";
	}

	/**
		Puts a note on every part, all the way through.

		@param song The piece.
		@param ticks How long it is.
		@return How many notes went in.
	**/
	static function filled(song:Song, ticks:Int):Int {
		final pattern = song.add(new Pattern("weigh", ticks));
		var many = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = pattern.lane(part);

			var at = index * 3;

			while (at < ticks - EVERY) {
				lane.add(new Note(at, EVERY - 2, 36 + (at >> 5) % 48, 64 + (at >> 3) % 60));
				at += EVERY;
				many++;
			}
		}

		final track = song.track(new Track("weigh"));
		track.add(new Clip(song.patterns.length - 1, 0, ticks));

		return many;
	}

	/**
		Puts automation on every part: every lane that writes a register, filled to the
		end of the piece or to whatever the lane will hold.

		@param song The piece.
		@param ticks How long it is.
		@return How many lanes were made.
	**/
	static function lined(song:Song, ticks:Int):Int {
		final pattern = song.patterns[song.patterns.length - 1];
		var many = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = pattern.lane(part);

			for (target in 0...Automation.BASES.length) {
				if (target == Automation.INSTRUMENT) continue;

				final line = new Automation(target, target % Automation.SLOTS);

				var at = 0;

				while (at < ticks && line.points.length < Automation.ROOM) {
					line.add(new Point(at, (at >> 4) % 100));
					at += POINT;
				}

				lane.automation.push(line);
				many++;
			}
		}

		return many;
	}

	/**
		@param song A piece read back.
		@return How many notes it carries, over every part of every pattern.
	**/
	static function counted(song:Song):Int {
		var many = 0;

		for (pattern in song.patterns) {
			for (index in 0...Part.COUNT) many += pattern.lane(index).notes.length;
		}

		return many;
	}

	/**
		Runs one phase with the process being sampled, and prints what it cost.

		@param name What to call it.
		@param body The phase. What it returns is printed as what came out of it.
	**/
	static function weighed(name:String, body:Void->String):Void {
		final was = settled();
		final gauge = new Gauge();

		began = haxe.Timer.stamp();

		final said = body();
		final spent = haxe.Timer.stamp() - began;
		final most = gauge.stop();

		final after = Usage.ram();

		Sys.println("    " + pad(name, 28) + pad(round(spent, 2) + " s", 10)
			+ pad("+" + say(most - was), 12) + pad(say(after), 12) + said);
	}

	/**
		@return What the process holds once the collector has had its say, in megabytes.
	**/
	static function settled():Float {
		cpp.vm.Gc.run(true);
		cpp.vm.Gc.compact();

		return Usage.ram();
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function pad(said:String, wide:Int):String {
		return StringTools.rpad(said, " ", wide);
	}

	static function say(value:Float):String {
		return "" + round(value, 1);
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	/**
		@param args What the program was run with.
		@param name The flag to look for.
		@param fallback What to answer where it is absent or unreadable.
		@return The number after the flag.
	**/
	static function number(args:Array<String>, name:String, fallback:Float):Float {
		final at = args.indexOf(name);
		if (at < 0 || at + 1 >= args.length) return fallback;

		final held = Std.parseFloat(args[at + 1]);
		return Math.isNaN(held) ? fallback : held;
	}
}

/**
	Samples what the process holds while something runs, and remembers the most it saw.

	`Usage.peak` is the whole process since it started, so it cannot say what one phase cost
	on its own. Reading before and after cannot either, because a phase that frees what it
	reserved reads as free. A thread looking often enough is the only one of the three that
	sees the middle.
**/
@:unreflective
private class Gauge {
	static inline final EVERY = 0.002;

	final most:AtomicInt;
	final alive:AtomicInt;

	public function new() {
		most = new AtomicInt(Std.int(Usage.ram() * 1024));
		alive = new AtomicInt(1);

		final held = this;

		sys.thread.Thread.create(function():Void {
			mdd.host.Crash.thread("the gauge thread");
			held.watches();
		});
	}

	function watches():Void {
		while (alive.load() == 1) {
			final now = Std.int(Usage.ram() * 1024);
			if (now > most.load()) most.store(now);

			Sys.sleep(EVERY);
		}
	}

	/**
		Stops sampling.

		@return The most the process held while it ran, in megabytes.
	**/
	public function stop():Float {
		final now = Std.int(Usage.ram() * 1024);
		if (now > most.load()) most.store(now);

		alive.store(0);
		return most.load() / 1024.0;
	}
}
