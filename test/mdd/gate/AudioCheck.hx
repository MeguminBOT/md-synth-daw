package mdd.gate;

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
		offline();
		whistle();
		pitch();
		shape();
		auditioned();
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

		while (Sdl.ticks() - began < seconds) Sdl.sleep(0.002);

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
