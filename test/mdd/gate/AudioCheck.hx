package mdd.gate;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.host.Audio;
import mdd.host.Device;
import mdd.host.Native;
import mdd.host.Sdl;
import mdd.play.Queue;
import mdd.play.Render;
import mdd.play.Stream;

@:unreflective
class AudioCheck {
	static inline final RATE = 48000;
	static inline final OFFLINE = 60.0;
	static inline final LIVE = 10.0;

	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		Native.ready();

		failed = 0;
		ran = 0;

		Sys.println("  audio");

		final at = args.indexOf("--wav");

		if (at >= 0 && at + 1 < args.length) {
			wav(args[at + 1]);
			args.splice(at, 2);
		}

		final live = args.length > 0 ? Std.parseFloat(args[0]) : LIVE;

		queueing();
		resampled();
		deep();
		sampling();
		kitted();
		offline();
		whistle();
		pitch();
		shape();
		auditioned();
		keyed();
		velocities();
		device(Math.isNaN(live) ? LIVE : live);
		played(8, Gate.root);

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	/**
		What a rate change keeps, and what it must not let back in.

		A tone under the new half rate has to come through where it was. A tone over it
		has to go, and the way to tell it went is that it did not come back somewhere
		else: taking one sample in four of 8000 Hz at 48000 lands it on 3025 Hz, which
		is a note nobody played.
	**/
	static function resampled():Void {
		final was = 48000;
		final want = 11025;

		says("a tone under the new half rate comes through",
			near(loudest(sined(was, 2000), want, was), 2000, 30),
			Math.round(loudest(sined(was, 2000), want, was))
				+ " Hz after 48000 becomes 11025, of the 2000 that went in");

		final over = strength(sined(was, 8000), want, was);
		final under = strength(sined(was, 2000), want, was);
		final down = under <= 0 || over <= 0 ? -99.0
			: 20 * Math.log(over / under) / Math.log(10);

		says("and one over it does not come back somewhere else", down < -40,
			round(down, 1) + " dB left of a tone at 8000 that 11025 cannot carry, against"
				+ " the nought a tone it can carry keeps");
	}

	/**
		A kit takes its keys from what the recordings are rather than from what they
		are called.

		The fixture is named wrongly on purpose, the way a downloaded kit often is: the
		hat that rings is called closed and the one that chokes is called open, and the
		toms are numbered against their pitch. What comes back has to be the general
		MIDI key each one belongs on regardless.
	**/
	static function kitted():Void {
		final where = Gate.root + "/export/kitting";
		mdd.host.Paths.make(where);

		hissed(where + "/Hat closed.wav", 1.6, 0);
		hissed(where + "/Hat open.wav", 0.09, 0);
		hissed(where + "/Tom 1.wav", 0.6, 200);
		hissed(where + "/Tom 2.wav", 0.6, 80);
		hissed(where + "/Kick.wav", 0.25, 50);

		final kit = new mdd.format.Kit();
		final many = kit.reads(where);

		kit.detects();

		says("a kit reads a folder of recordings", many == 5 && kit.slots.length == 5,
			many + " hits read out of " + where.split("/").pop());

		says("and a hat that rings is the open one whatever it is called",
			keyOf(kit, "Hat closed") == 46 && keyOf(kit, "Hat open") == 42,
			"the one called closed rings and landed on " + keyOf(kit, "Hat closed")
				+ ", the one called open chokes and landed on " + keyOf(kit, "Hat open"));

		says("and toms run low to high however they are numbered",
			keyOf(kit, "Tom 2") == 41 && keyOf(kit, "Tom 1") == 43,
			"the 80 Hz one landed on " + keyOf(kit, "Tom 2") + " and the 200 Hz one on "
				+ keyOf(kit, "Tom 1"));

		says("and a kick is a kick", keyOf(kit, "Kick") == 36,
			"it landed on " + keyOf(kit, "Kick"));

		kit.converts();

		final said = kit.written();
		final back = new mdd.song.Library();
		final read = back.reads(said);

		says("and what it writes is a bank that loads", read == 5 && kit.bytes() > 0,
			"" + read + " presets over " + kit.bytes() + " bytes, read back out of "
				+ said.length + " bytes of document");
	}

	/**
		Writes a hit to a file: a tone where one is asked for, and noise where it is
		not, decaying over the length given.

		@param path Where to write it.
		@param seconds How long the decay is.
		@param hertz The tone, or nought for noise.
	**/
	static function hissed(path:String, seconds:Float, hertz:Float):Void {
		final rate = 48000;
		final frames = Std.int(rate * (seconds + 0.4));
		final held = new Vector<cpp.Float32>(frames);

		var seed = 0x4D44;

		for (index in 0...frames) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

			final at = index / rate;
			final fall = Math.exp(-at * 3 / seconds);

			final one = hertz > 0 ? Math.sin(2 * Math.PI * hertz * at)
				: ((seed >> 8) % 2000 - 1000) / 1000.0;

			held[index] = 0.7 * one * fall;
		}

		sys.io.File.saveBytes(path,
			mdd.format.Wav.write(held, frames, 1, rate, 24, false));
	}

	/**
		@param kit The kit.
		@param called What a hit is called.
		@return Which key it landed on, or -1 where there is no such hit.
	**/
	static function keyOf(kit:mdd.format.Kit, called:String):Int {
		for (slot in kit.slots) if (slot.name == called) return slot.root;

		return -1;
	}

	/**
		Every depth a wave file can carry reads back as what was written.

		Twenty four bits had no case of its own and fell through to the one that reads
		four bytes, so every sample was built from three of its own bytes and one of
		the next one, and then divided by the wrong scale. It read as noise, and
		nothing here had ever asked, because the fixtures were all sixteen bit.
	**/
	static function deep():Void {
		final frames = 512;
		final held = new Vector<cpp.Float32>(frames);

		for (index in 0...frames) {
			held[index] = 0.8 * Math.sin(2 * Math.PI * 7 * index / frames)
				* (1 - index / frames);
		}

		for (depth in [16, 24, 32]) {
			final bytes = mdd.format.Wav.write(held, frames, 1, 22050, depth, false);
			final back = mdd.format.Wav.read(bytes);

			if (back.frames != frames) {
				says(depth + " bit reads back", false,
					back.frames + " frames of " + frames);
				continue;
			}

			final mono = back.mono();
			var worst = 0.0;

			for (index in 0...frames) {
				final apart = mono[index] - held[index];
				final size = apart < 0 ? -apart : apart;

				if (size > worst) worst = size;
			}

			final step = depth == 16 ? 1 / 32768.0 : (depth == 24 ? 1 / 8388608.0 : 1e-6);

			says(depth + " bit reads back as what was written", worst <= step * 2,
				"the worst sample is out by " + round(worst / step, 2)
					+ " of one step at that depth");
		}
	}

	/**
		What the conversion does to a recording on its way to being a sample.

		The fixture is what a badly prepared hit looks like: quiet, sitting off centre,
		with a long silence after it. Every stage has something to do.
	**/
	static function sampling():Void {
		final was = 48000;
		final held = new Vector<Float>(was);

		for (index in 0...was) {
			final at = index / was;

			if (at < 0.1 || at > 0.4) {
				held[index] = 0.2;
			} else {
				final since = at - 0.1;
				held[index] = 0.2 + 0.3 * Math.sin(2 * Math.PI * 200 * since)
					* Math.exp(-since * 12);
			}
		}

		final made = new mdd.format.Sampling();
		final sample = made.takes(held, was, "hit");

		says("a converted hit keeps only the hit", sample.length() > 0
			&& sample.length() < made.rate / 2,
			sample.length() + " bytes at " + made.rate + " Hz, of the " + made.rate
				+ " a whole second of the recording would have come to");

		var most = 0;
		var sum = 0.0;

		for (index in 0...sample.length()) {
			final off = sample.bytes[index] - 128;
			final size = off < 0 ? -off : off;

			if (size > most) most = size;
			sum += off;
		}

		says("and brings it up to full", most == 127,
			most + " of 127, from a recording peaking at three tenths");

		final middle = sample.length() == 0 ? 0.0 : sum / sample.length();

		says("and takes the offset out", middle > -4 && middle < 4,
			round(middle, 2) + " away from the middle, from a recording sitting a fifth"
				+ " of full above it");

		final first = sample.bytes[0] - 128;
		final last = sample.bytes[sample.length() - 1] - 128;

		says("and begins and ends at rest",
			first > -6 && first < 6 && last > -6 && last < 6,
				"it opens at " + first + " and closes at " + last + ", either side of the"
				+ " middle, so there is no step at either end");
	}

	/**
		@param rate The rate to build it at.
		@param hertz The tone.
		@return One second of it, at plus or minus one.
	**/
	static function sined(rate:Int, hertz:Float):Vector<Float> {
		final out = new Vector<Float>(rate);
		for (index in 0...rate) out[index] = Math.sin(2 * Math.PI * hertz * index / rate);

		return out;
	}

	/**
		@param held The audio.
		@param want The rate to bring it to.
		@param was The rate it is at.
		@return The loudest frequency left in it afterwards, in hertz.
	**/
	static function loudest(held:Vector<Float>, want:Int, was:Int):Float {
		final out = mdd.format.Resampler.into(held, was, want);
		final size = 8192;

		if (out.length < size) return 0;

		final fourier = new Fourier(size);
		fourier.clear();

		for (index in 0...size) fourier.real[index] = out[index];

		fourier.forward();

		final sizes = new Vector<Float>(size >> 1);
		fourier.magnitudes(sizes);

		var at = 0;
		for (index in 1...sizes.length) if (sizes[index] > sizes[at]) at = index;

		return at * want / size;
	}

	/**
		How loud the loudest thing left is, with a tenth off either end.

		The ends are left out because a window reaching past the run has only half of
		itself to work with there and rejects far less, which is a property of every
		filter at a boundary rather than anything folding back. `Resampler` says what
		that costs a caller.

		@param held The audio.
		@param want The rate to bring it to.
		@param was The rate it is at.
		@return How loud the loudest thing left in the middle of it is.
	**/
	static function strength(held:Vector<Float>, want:Int, was:Int):Float {
		final out = mdd.format.Resampler.into(held, was, want);
		final edge = Std.int(out.length / 10);

		var most = 0.0;
		for (index in edge...out.length - edge) {
			final size = out[index] < 0 ? -out[index] : out[index];
			if (size > most) most = size;
		}

		return most;
	}

	static function near(value:Float, want:Float, room:Float):Bool {
		final apart = value - want;
		return (apart < 0 ? -apart : apart) <= room;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 22) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	static function wav(path:String):Void {
		final seconds = 3.0;
		final render = new Render(RATE, Render.BLOCK);

		voiced(render);
		render.drain();

		final frames = Std.int(seconds * RATE);
		final held = new haxe.ds.Vector<cpp.Float32>(frames * 2);

		var done = 0;

		while (done < frames) {
			final many = render.fill(Render.BLOCK);

			for (i in 0...many) {
				if ((done + i) * 2 + 1 >= held.length) break;
				held[(done + i) * 2] = render.block[i * 2];
				held[(done + i) * 2 + 1] = render.block[i * 2 + 1];
			}

			done += many;
		}

		sys.io.File.saveBytes(path, mdd.format.Wav.write(held, frames, 2, RATE));

		Sys.println("    " + StringTools.rpad("wrote", " ", 22) + Std.int(seconds)
			+ " s of the test voice to " + path);
	}

	static function queueing():Void {
		final queue = new Queue(64);

		for (i in 0...64) queue.push(Stream.YM, i & 3, i & 0xFF);
		final full = queue.waiting();

		final refused = queue.push(Stream.YM, 0, 0);
		final dropped = queue.dropped;

		var read = 0;
		var right = true;

		while (true) {
			final word = queue.pull();
			if (word < 0) break;

			if (Queue.kindOf(word) != Stream.YM) right = false;
			if (Queue.portOf(word) != (read & 3)) right = false;
			if (Queue.valueOf(word) != (read & 0xFF)) right = false;

			read++;
		}

		says("queue holds", full == 64 && read == 64 && right,
			"64 writes in and " + read + " out, in order");
		says("queue refuses", !refused && dropped == 1,
			"a full queue drops rather than blocking, " + dropped + " dropped");
	}

	static function voiced(render:Render):Void {
		push(render, 0x30, 0x71);
		push(render, 0x34, 0x0D);
		push(render, 0x38, 0x33);
		push(render, 0x3C, 0x01);
		push(render, 0x40, 0x23);
		push(render, 0x44, 0x2D);
		push(render, 0x48, 0x26);
		push(render, 0x4C, 0x00);
		push(render, 0x50, 0x5F);
		push(render, 0x54, 0x99);
		push(render, 0x58, 0x5F);
		push(render, 0x5C, 0x94);
		push(render, 0x60, 0x05);
		push(render, 0x64, 0x05);
		push(render, 0x68, 0x05);
		push(render, 0x6C, 0x07);
		push(render, 0x70, 0x02);
		push(render, 0x74, 0x02);
		push(render, 0x78, 0x02);
		push(render, 0x7C, 0x02);
		push(render, 0x80, 0x11);
		push(render, 0x84, 0x11);
		push(render, 0x88, 0x11);
		push(render, 0x8C, 0xA6);
		push(render, 0xB0, 0x32);
		push(render, 0xB4, 0xC0);
		push(render, 0xA4, 0x22);
		push(render, 0xA0, 0x69);
		push(render, 0x28, 0xF0);

		render.queue.push(Stream.PSG, 0, 0x80 | 0x00 | 0x0E);
		render.queue.push(Stream.PSG, 0, 0x08);
		render.queue.push(Stream.PSG, 0, 0x80 | 0x10 | 0x04);
	}

	static function push(render:Render, at:Int, value:Int):Void {
		render.queue.push(Stream.YM, 0, at);
		render.queue.push(Stream.YM, 1, value);
	}

	static function offline():Void {
		final render = new Render(RATE, Render.BLOCK);
		voiced(render);
		render.drain();

		render.fill(Render.BLOCK);

		var loudest = 0.0;
		for (i in 0...Render.BLOCK * 2) {
			final value = render.block[i] < 0 ? -render.block[i] : render.block[i];
			if (value > loudest) loudest = value;
		}

		says("it makes a sound", loudest > 0.001,
			"the loudest sample of the first block is " + round(loudest, 4));

		final wanted = Std.int(OFFLINE * RATE);
		var done = 0;

		cpp.vm.Gc.enable(false);
		final before = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
		final began = Sdl.ticks();

		while (done < wanted) done += render.fill(Render.BLOCK);

		final spent = Sdl.ticks() - began;
		final after = cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
		cpp.vm.Gc.enable(true);

		final grown = after - before;

		says("the render allocates", grown == 0,
			grown + " bytes across " + Std.int(OFFLINE) + " s of audio, with the collector off");

		says("the render keeps up", spent < OFFLINE,
			Std.int(OFFLINE) + " s of audio rendered in " + round(spent, 2) + " s, "
			+ round(OFFLINE / spent, 1) + " times faster than real time");
	}

	/**
		Pressing a key on the converter sounds the recording that key holds.

		A note placed on a key sounds the recording rooted there, and pressing the key
		itself has to sound the same thing or the keyboard is lying about what the note
		will be. Two recordings are put on two keys and each key is pressed, and the
		bytes that reach the converter are what says which one sounded.
	**/
	static function keyed():Void {
		final song = new mdd.song.Song("keys", 96, 120);

		for (index in 0...mdd.song.Part.COUNT) {
			final part:mdd.song.Part = index;
			song.instrument(new mdd.song.Instrument(part.name().toLowerCase(), part));
			song.rack[index] = index;
		}

		final low = laid(song, "low", 60, 40);
		final high = laid(song, "high", 62, 200);

		song.rack[mdd.song.Part.Dac.index()] = low;

		says("two recordings sit on two keys",
			song.drumAt(60) == low && song.drumAt(62) == high,
			"the lower key holds " + song.drumAt(60) + " and the upper "
				+ song.drumAt(62) + ", against " + low + " and " + high);

		for (kit in [false, true]) {
			song.drums = kit;

			final said = kit ? "as a kit" : "as one instrument";

			final one = pressed(song, 60);
			final two = pressed(song, 62);

			says("pressing a key on the converter sounds what it holds, " + said,
				one != "" && two != "" && one != two,
				one == two ? "both keys wrote " + one
					: "the lower key wrote " + one + " and the upper " + two);
		}

		song.drums = false;
	}

	/**
		Puts a sampled instrument in a song, its bytes a flat level so two are told
		apart by which reaches the converter rather than by how much of it there is.

		@param song The song.
		@param name What to call it.
		@param root Which key it sits on.
		@param level The byte it holds.
		@return Its index.
	**/
	static function laid(song:mdd.song.Song, name:String, root:Int, level:Int):Int {
		final sample = new mdd.song.Sample(name, 8000, root);
		final bytes = new haxe.ds.Vector<Int>(64);

		for (at in 0...bytes.length) bytes[at] = level;
		sample.hold(bytes);

		song.sample(sample);

		final made = new mdd.song.Instrument(name, mdd.song.Part.Dac);
		made.sample = song.samples.length - 1;

		song.instrument(made);

		return song.instruments.length - 1;
	}

	/**
		Presses one key and reads back what reached the converter.

		@param song The song.
		@param note Which key.
		@return The distinct bytes the converter was given, or an empty string where it
			was given none.
	**/
	static function pressed(song:mdd.song.Song, note:Int):String {
		final transport = new mdd.play.Transport(song, 1 << 16);

		transport.auditions(mdd.song.Part.Dac, note);

		final held:Array<String> = [];
		var want = false;

		for (block in 0...60) {
			transport.advance(Render.BLOCK, RATE);

			final stream = transport.stream;

			for (index in 0...stream.count) {
				if (stream.kindAt(index) != mdd.play.Stream.YM) continue;

				if (stream.portAt(index) == 0) {
					want = stream.valueAt(index) == 0x2A;
					continue;
				}

				if (!want) continue;

				final said = "" + stream.valueAt(index);
				if (held.indexOf(said) < 0) held.push(said);
			}
		}

		return held.join(" ");
	}

	static function auditioned():Void {
		final session = mdd.app.Session.started(mdd.song.Library.embedded());
		final render = new Render(RATE, Render.BLOCK);

		render.transport = session.transport;

		var before = 0.0;

		for (block in 0...40) {
			final from = session.transport.advance(Render.BLOCK, RATE);
			final many = render.serve(session.transport.stream, from, Render.BLOCK,
				session.transport.entering, true);

			if (block < 30) continue;

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > before) before = much;
			}
		}

		session.transport.auditions(mdd.song.Part.Fm1, 60);

		var after = 0.0;

		for (block in 0...40) {
			final from = session.transport.advance(Render.BLOCK, RATE);
			final many = render.serve(session.transport.stream, from, Render.BLOCK,
				session.transport.entering, true);

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > after) after = much;
			}
		}

		says("a key sounds without playing", after > before * 5,
			"the transport stopped and settled renders " + round(before, 5)
			+ ", and a key on FM1"
			+ " asked for through the stream renders " + round(after, 4));

		session.transport.auditions(mdd.song.Part.Dac, 60);

		var struck = 0.0;
		var bytes = 0;

		for (block in 0...200) {
			final from = session.transport.advance(Render.BLOCK, RATE);
			final held = session.transport.stream;

			for (index in 0...held.count) {
				if (held.kindAt(index) != mdd.play.Stream.YM) continue;
				if ((held.portAt(index) & 1) != 0) continue;
				if (held.valueAt(index) == 0x2A) bytes++;
			}

			final many = render.serve(held, from, Render.BLOCK,
				session.transport.entering, true);

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > struck) struck = much;
			}
		}

		says("and so does a sample", bytes > 100 && struck > before * 5,
			bytes + " converter bytes reached the chip and the strike renders "
			+ round(struck, 4));
	}

	static function level(velocity:Int):Float {
		final render = new Render(RATE, Render.BLOCK);
		final stream = new Stream(1024);
		final patch = new mdd.song.Patch();

		stream.patch(0, mdd.song.Part.Fm1, patch, velocity);
		stream.sides(0, mdd.song.Part.Fm1, 0xC0);
		stream.tune(0, mdd.song.Part.Fm1, 60);
		stream.keyOn(0, mdd.song.Part.Fm1);

		var most = 0.0;
		var done = 0;

		while (done < RATE) {
			final many = render.serve(stream, 0, Render.BLOCK, 0, done == 0);

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > most) most = much;
			}

			done += many;
		}

		return most;
	}

	static function quiet(velocity:Int):Float {
		final render = new Render(RATE, Render.BLOCK);
		final stream = new Stream(1024);

		stream.square(0, mdd.song.Part.Psg1, 60);
		stream.loudness(0, mdd.song.Part.Psg1, null, velocity, 0);

		var most = 0.0;
		var done = 0;

		while (done < Std.int(RATE / 4)) {
			final many = render.serve(stream, 0, Render.BLOCK, 0, done == 0);

			for (i in 0...many) {
				final value = render.block[i * 2];
				final much = value < 0 ? -value : value;
				if (much > most) most = much;
			}

			done += many;
		}

		return most;
	}

	static function decibels(much:Float, than:Float):Float {
		if (much <= 0 || than <= 0) return -99;
		return 20 * Math.log(much / than) / Math.log(10);
	}

	static function velocities():Void {
		final full = level(127);

		for (velocity in [127, 110, 100, 80, 64, 32]) {
			final held = level(velocity);
			Sys.println("      fm       velocity " + StringTools.lpad("" + velocity, " ", 3)
				+ "   peak " + round(held, 5) + "   " + round(decibels(held, full), 2) + " dB");
		}

		final loudest = quiet(127);

		for (velocity in [127, 110, 100, 80, 64, 32]) {
			final held = quiet(velocity);
			Sys.println("      square   velocity " + StringTools.lpad("" + velocity, " ", 3)
				+ "   peak " + round(held, 5) + "   " + round(decibels(held, loudest), 2) + " dB");
		}

		final hundred = level(100);

		says("a note at velocity 100 is close to a note at 127",
			decibels(hundred, full) > -6,
			"velocity 100 renders " + round(decibels(hundred, full), 2)
			+ " dB against velocity 127, where a linear reading of velocity wants "
			+ round(20 * Math.log(100 / 127.0) / Math.log(10), 2) + " dB");
	}

	static function toned(render:Render):Void {
		for (at in 0...4) {
			push(render, 0x30 + at * 4, 0x01);
			push(render, 0x40 + at * 4, at == 3 ? 0x00 : 0x7F);
			push(render, 0x50 + at * 4, 0x1F);
			push(render, 0x60 + at * 4, 0x00);
			push(render, 0x70 + at * 4, 0x00);
			push(render, 0x80 + at * 4, 0x0F);
		}

		push(render, 0xB0, 0x07);
		push(render, 0xB4, 0xC0);
		push(render, 0xA4, 0x22);
		push(render, 0xA0, 0x69);
		push(render, 0x28, 0xF0);

		render.drain();
	}

	static function shape():Void {
		final render = new Render(RATE, Render.BLOCK);
		toned(render);

		final held = new haxe.ds.Vector<Float>(16384);
		var done = 0;

		while (done < held.length) {
			final many = render.fill(Render.BLOCK);
			for (i in 0...many) {
				if (done + i >= held.length) break;
				held[done + i] = render.block[i * 2];
			}
			done += many;
		}

		final from = 4096;
		final window = 8192;
		final hz = 250.75;

		var total = 0.0;

		for (i in 0...window) total += held[from + i] * held[from + i];

		total = Math.sqrt(total / window);

		var real = 0.0;
		var imaginary = 0.0;

		for (i in 0...window) {
			final turn = 2 * Math.PI * hz * i / RATE;
			real += held[from + i] * Math.cos(turn);
			imaginary += held[from + i] * Math.sin(turn);
		}

		final fundamental = 2 * Math.sqrt(real * real + imaginary * imaginary) / window
			/ Math.sqrt(2);

		final rest = total * total - fundamental * fundamental;
		final distortion = fundamental <= 0 ? 1.0
			: Math.sqrt(rest < 0 ? 0 : rest) / fundamental;

		says("one operator is a sine", distortion < 0.25,
			"a single carrier at full level renders " + round(distortion * 100, 1)
			+ " per cent of its energy away from the fundamental, at "
			+ round(fundamental, 4) + " against " + round(total, 4) + " overall");
	}

	static function whistle():Void {
		final render = new Render(RATE, Render.BLOCK);
		final period = 45;

		render.psg.write(0x80 | (0 << 5) | (period & 0x0F));
		render.psg.write((period >> 4) & 0x3F);
		render.psg.write(0x80 | (0 << 5) | 0x10 | 0x00);

		final held = new haxe.ds.Vector<Float>(16384);
		var done = 0;

		while (done < held.length) {
			final many = render.fill(Render.BLOCK);

			for (i in 0...many) {
				if (done + i >= held.length) break;
				held[done + i] = render.block[i * 2];
			}

			done += many;
		}

		final from = 4096;
		final window = 8192;
		final hz = Sn76489.CLOCK / (32.0 * period);

		var total = 0.0;
		for (i in 0...window) total += held[from + i] * held[from + i];

		total = Math.sqrt(total / window);

		var wanted = 0.0;
		var partials = 0;
		var harmonic = 1;

		while (hz * harmonic < RATE * 0.5) {
			var real = 0.0;
			var imaginary = 0.0;

			for (i in 0...window) {
				final turn = 2 * Math.PI * hz * harmonic * i / RATE;
				real += held[from + i] * Math.cos(turn);
				imaginary += held[from + i] * Math.sin(turn);
			}

			final much = 2 * Math.sqrt(real * real + imaginary * imaginary) / window
				/ Math.sqrt(2);

			wanted += much * much;
			partials++;
			harmonic += 2;
		}

		final rest = total * total - wanted;
		final noise = total <= 0 ? 1.0 : Math.sqrt(rest < 0 ? 0 : rest) / total;

		says("a square is odd harmonics and nothing else", noise < 0.35,
			"a square at " + round(hz, 1) + " Hz renders " + round(noise * 100, 1)
			+ " per cent of its energy away from its " + partials + " odd harmonics, at "
			+ round(Math.sqrt(wanted), 4) + " against " + round(total, 4) + " overall");
	}

	static function pitch():Void {
		final render = new Render(RATE, Render.BLOCK);

		for (at in 0...4) {
			push(render, 0x30 + at * 4, 0x01);
			push(render, 0x40 + at * 4, at == 3 ? 0x00 : 0x7F);
			push(render, 0x50 + at * 4, 0x1F);
			push(render, 0x60 + at * 4, 0x00);
			push(render, 0x70 + at * 4, 0x00);
			push(render, 0x80 + at * 4, 0x0F);
		}

		push(render, 0xB0, 0x07);
		push(render, 0xB4, 0xC0);
		push(render, 0xA4, 0x22);
		push(render, 0xA0, 0x69);
		push(render, 0x28, 0xF0);

		render.drain();

		final held = new haxe.ds.Vector<Float>(32768);
		var done = 0;

		while (done < held.length) {
			final many = render.fill(Render.BLOCK);
			for (i in 0...many) {
				if (done + i >= held.length) break;
				held[done + i] = render.block[i * 2];
			}
			done += many;
		}

		final window = 16384;
		final from = 8192;

		var mean = 0.0;
		for (i in 0...window) mean += held[from + i];
		mean /= window;

		var best = -1e30;

		for (lag in 60...900) {
			final sum = agrees(held, from, window, lag, mean);
			if (sum > best) best = sum;
		}

		var bestLag = 0;

		for (lag in 61...899) {
			final sum = agrees(held, from, window, lag, mean);
			if (sum < best * 0.9) continue;
			if (sum < agrees(held, from, window, lag - 1, mean)) continue;
			if (sum < agrees(held, from, window, lag + 1, mean)) continue;

			bestLag = lag;
			break;
		}

		if (bestLag == 0) {
			says("the pitch is the note", false, "no periodicity in the rendered waveform");
			return;
		}

		final under = agrees(held, from, window, bestLag - 1, mean);
		final over = agrees(held, from, window, bestLag + 1, mean);
		final bend = under - 2 * best + over;
		final shift = bend == 0 ? 0.0 : 0.5 * (under - over) / bend;

		final measured = RATE / (bestLag + shift);
		final want = 617 * (Ym2612.CLOCK / Ym2612.PER_SAMPLE) / 1048576.0 * 8;
		final cents = 1200 * Math.log(measured / want) / Math.log(2);

		says("the pitch is the note", Math.abs(cents) < 1,
			"F number 617 at block 4 wants " + round(want, 2) + " Hz, the render gives "
			+ round(measured, 2) + ", " + round(cents, 3) + " cents apart");
	}

	static function agrees(held:haxe.ds.Vector<Float>, from:Int, window:Int, lag:Int,
			mean:Float):Float {
		var sum = 0.0;
		final many = window - lag;

		for (i in 0...many) sum += (held[from + i] - mean) * (held[from + i + lag] - mean);
		return sum / many;
	}

	static function played(seconds:Float, root:String):Void {
		final where = root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		var name = "";

		name = Fixtures.found("Green Hill");

		if (name == "") return;

		final stream = new mdd.play.Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), stream);
		final song = mdd.format.Transcription.of(stream, vgm.rate, name).song;

		final handle = Audio.open(0, Render.BLOCK);

		if (handle == null) {
			says("an imported song plays live", false, "no playback device");
			return;
		}

		final rate = Audio.rate(handle);
		final render = new Render(rate, Render.BLOCK);
		final transport = new mdd.play.Transport(song, 1 << 18);

		render.transport = transport;
		transport.play();

		Audio.forget(handle);
		render.start(handle);

		final began = Sdl.ticks();
		final litter:Array<haxe.ds.Vector<Float>> = [];

		var swept = 0;
		var worstSweep = 0.0;

		while (Sdl.ticks() - began < seconds) {
			for (round in 0...200) litter.push(new haxe.ds.Vector<Float>(1024));

			if (litter.length > 4000) {
				final mark = Sdl.ticks();

				litter.resize(0);
				cpp.vm.Gc.run(true);

				final took = Sdl.ticks() - mark;

				if (took > worstSweep) worstSweep = took;
				swept++;
			}

			Sdl.sleep(0.002);
		}

		final underruns = Audio.underruns(handle);
		final taken = Audio.taken(handle);
		final thinnest = render.leastHeld;
		final blocks = render.blocks;

		render.stop();
		Audio.close(handle);

		says("an imported song plays live", underruns == 0 && render.dropped == 0,
			round(taken / rate, 1) + " s of Green Hill through the device in " + blocks
			+ " blocks: " + underruns + " underruns, " + render.dropped
			+ " frames dropped for want of room, and the ring never fell below "
			+ round(thinnest * 1000.0 / rate, 1) + " ms of a "
			+ round(render.cushion * 1000.0 / rate, 1) + " ms cushion");

		says("and a collector sweeping does not reach it", underruns == 0,
			swept + " collections forced while it played, worst "
			+ round(worstSweep * 1000, 1) + " ms, and the device took every frame it asked"
			+ " for");
	}

	static function device(seconds:Float):Void {
		final handle = Audio.open(0, Render.BLOCK);

		if (handle == null) {
			says("the device opens", false, "miniaudio would not open a playback device");
			return;
		}

		final rate = Audio.rate(handle);
		final period = Audio.period(handle);

		says("the device opens", rate > 0 && period > 0,
			Audio.name(handle) + ", " + rate + " Hz, " + period + " frame period, "
			+ Audio.periods(handle) + " of them, " + Audio.buffer(handle) + " frame buffer");

		final render = new Render(rate, Render.BLOCK);
		voiced(render);

		Audio.forget(handle);
		render.start(handle);

		Sdl.sleep(0.25);
		final early = Audio.underruns(handle);

		final began = Sdl.ticks();
		var worst = 0;
		var total = 0.0;
		var looks = 0;

		while (Sdl.ticks() - began < seconds) {
			Sdl.sleep(0.002);

			final now = Audio.held(handle);
			if (now > worst) worst = now;
			total += now;
			looks++;
		}

		final underruns = Audio.underruns(handle);
		final taken = Audio.taken(handle);
		final buffer = Audio.buffer(handle);

		render.stop();
		Audio.close(handle);

		final mean = looks == 0 ? 0.0 : total / looks;
		final ceiling = render.cushion + Render.BLOCK;

		says("the ring holds its cushion", worst <= ceiling
			&& mean > render.cushion * 0.5,
			"mean " + round(mean * 1000 / rate, 2) + " ms held against a cushion of "
			+ round(render.cushion * 1000.0 / rate, 2) + " ms, worst "
			+ round(worst * 1000.0 / rate, 2) + " ms");

		says("and never runs it down", render.leastHeld > period && render.dropped == 0,
			"the thinnest the ring ever got was "
			+ round(render.leastHeld * 1000.0 / rate, 2) + " ms, against a driver period of "
			+ round(period * 1000.0 / rate, 2) + " ms, and " + render.dropped
			+ " frames were dropped for want of room");

		says("no underruns", underruns == 0,
			early + " in the first 250 ms, " + underruns + " across " + round(taken / rate, 1) + " s the device drained");

		says("the device holds", buffer > 0,
			"the driver takes " + round(period * 1000.0 / rate, 2) + " ms at a time and buffers "
			+ round(buffer * 1000.0 / rate, 2) + " ms, which is the driver's latency, not this one's");

	}
}
