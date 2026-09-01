package mdd.gate;

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
		pitch();
		device(Math.isNaN(live) ? LIVE : live);

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
		final out = new haxe.io.BytesOutput();
		final body = frames * 4;

		out.writeString("RIFF");
		out.writeInt32(36 + body);
		out.writeString("WAVE");
		out.writeString("fmt ");
		out.writeInt32(16);
		out.writeUInt16(1);
		out.writeUInt16(2);
		out.writeInt32(RATE);
		out.writeInt32(RATE * 4);
		out.writeUInt16(4);
		out.writeUInt16(16);
		out.writeString("data");
		out.writeInt32(body);

		var done = 0;

		while (done < frames) {
			final many = render.fill(Render.BLOCK);

			for (i in 0...many) {
				if (done + i >= frames) break;
				out.writeInt16(whole(render.block[i * 2]));
				out.writeInt16(whole(render.block[i * 2 + 1]));
			}

			done += many;
		}

		sys.io.File.saveBytes(path, out.getBytes());
		Sys.println("    " + StringTools.rpad("wrote", " ", 22) + Std.int(seconds)
			+ " s of the test voice to " + path);
	}

	static inline function whole(value:cpp.Float32):Int {
		final scaled = Math.round(value * 32767);
		return scaled > 32767 ? 32767 : (scaled < -32768 ? -32768 : scaled);
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
		final ceiling = period + Render.BLOCK;

		says("the ring adds", worst <= ceiling,
			"mean " + round(mean * 1000 / rate, 2) + " ms, worst " + round(worst * 1000.0 / rate, 2)
			+ " ms, of one period and one block");

		says("no underruns", underruns == 0,
			early + " in the first 250 ms, " + underruns + " across " + round(taken / rate, 1) + " s the device drained");

		says("the device holds", buffer > 0,
			"the driver takes " + round(period * 1000.0 / rate, 2) + " ms at a time and buffers "
			+ round(buffer * 1000.0 / rate, 2) + " ms, which is the driver's latency, not this one's");

	}
}
