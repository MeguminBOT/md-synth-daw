package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.host.Audio;
import mdd.host.Device;
import mdd.host.Sdl;
import mdd.song.Tempo;

@:unreflective
final class Render {
	public static inline final BLOCK = 128;
	public static inline final COUPLING = 0.9975;
	public static inline final FULL_SCALE = 2560.0;
	public static inline final SCALE = 1.0 / FULL_SCALE;
	public static inline final PRIMED = 0.100;

	public static inline final TAPS = 2048;
	public static inline final TAP_EVERY = 4;
	public static inline final FM_TAP = 1.0 / 200.0;
	public static inline final PSG_TAP = 1.0 / 340.0;

	public final taps:haxe.ds.Vector<cpp.Float32> =
		new haxe.ds.Vector<cpp.Float32>(mdd.song.Part.COUNT * TAPS);

	public var tapped(default, null):Int = 0;
	public var cushion(default, null):Int = 0;
	public var dropped(default, null):Int = 0;
	public var leastHeld(default, null):Int = 0;
	var tapNext:Int = 0;

	public final ym:Ym2612 = new Ym2612();
	public final psg:Sn76489 = new Sn76489();
	public final queue:Queue;

	public var rate(default, null):Int;
	public var frames(default, null):Int;

	public var made(default, null):Int = 0;
	public var writes(default, null):Int = 0;

	public final block:Vector<cpp.Float32>;

	final fmStep:Float;
	final psgStep:Float;

	var fmAt:Float = 0;
	var psgAt:Float = 0;

	var fmLeft:Float = 0;
	var fmRight:Float = 0;

	var wentLeft:Float = 0;
	var wentRight:Float = 0;
	var heldLeft:Float = 0;
	var heldRight:Float = 0;

	public var transport:Null<Transport> = null;

	var device:cpp.Star<Device> = null;
	var alive:Bool = false;

	public var running(default, null):Bool = false;
	public var blocks(default, null):Int = 0;
	public var worstHeld(default, null):Int = 0;

	public function new(rate:Int, frames:Int = BLOCK, queue:Null<Queue> = null) {
		this.rate = rate <= 0 ? 48000 : rate;
		this.frames = frames <= 0 ? BLOCK : frames;
		this.queue = queue == null ? new Queue() : queue;

		block = new Vector<cpp.Float32>(this.frames * 2);

		fmStep = Ym2612.CLOCK / (Ym2612.PER_SAMPLE * this.rate);
		psgStep = Sn76489.CLOCK / this.rate;
	}

	public function reset():Void {
		ym.reset();
		psg.reset();
		queue.clear();

		fmAt = 0;
		psgAt = 0;
		fmLeft = 0;
		fmRight = 0;
		wentLeft = 0;
		wentRight = 0;
		heldLeft = 0;
		heldRight = 0;
		made = 0;
		writes = 0;
	}

	public function drain():Int {
		var took = 0;

		while (true) {
			final word = queue.pull();
			if (word < 0) break;

			if (Queue.kindOf(word) == Stream.PSG) psg.write(Queue.valueOf(word));
			else ym.write(Queue.portOf(word), Queue.valueOf(word));

			took++;
		}

		writes += took;
		return took;
	}

	public function fill(count:Int):Int {
		return serve(null, 0, count);
	}

	public function serve(stream:Null<Stream>, from:Int, count:Int, carry:Int = 0):Int {
		final many = count > frames ? frames : count;

		var next = 0;
		var tick = from;
		var held = carry;

		for (frame in 0...many) {
			if (stream != null) {
				while (next < stream.count && stream.tickAt(next) <= tick) {
					pour(stream, next);
					next++;
				}
			}

			fmAt += fmStep;

			var tookLeft = 0;
			var tookRight = 0;
			var took = 0;

			while (fmAt >= 1) {
				fmAt -= 1;
				ym.sample();

				tookLeft += ym.left;
				tookRight += ym.right;
				took++;
			}

			if (took > 0) {
				fmLeft = tookLeft / took;
				fmRight = tookRight / took;
			}

			psgAt += psgStep;
			final clocks = Std.int(psgAt);
			psgAt -= clocks;
			psg.run(clocks);

			final other = psg.taken();

			final left = fmLeft + other;
			final right = fmRight + other;

			heldLeft = (left - wentLeft) + COUPLING * heldLeft;
			heldRight = (right - wentRight) + COUPLING * heldRight;
			wentLeft = left;
			wentRight = right;

			tapNext++;

			if (tapNext >= TAP_EVERY) {
				tapNext = 0;
				tapping();
			}

			block[frame * 2] = clamped(heldLeft * SCALE);
			block[frame * 2 + 1] = clamped(heldRight * SCALE);

			held += Tempo.TICKS;
			while (held >= rate) {
				held -= rate;
				tick++;
			}
		}

		if (stream != null) {
			while (next < stream.count) {
				pour(stream, next);
				next++;
			}
		}

		made += many;
		return many;
	}

	inline function pour(stream:Stream, index:Int):Void {
		if (stream.kindAt(index) == Stream.PSG) psg.write(stream.valueAt(index));
		else ym.write(stream.portAt(index), stream.valueAt(index));

		writes++;
	}

	inline function tapping():Void {
		final slot = tapped % TAPS;

		for (index in 0...6) {
			taps[index * TAPS + slot] = ym.channels[index].delivered * FM_TAP;
		}

		for (index in 0...4) {
			taps[(6 + index) * TAPS + slot] = psg.voice(index) * PSG_TAP;
		}

		taps[10 * TAPS + slot] = ym.dacOn ? ((ym.dac - 0x80) << 1) * PSG_TAP : 0;
		tapped++;
	}

	static inline function clamped(value:Float):cpp.Float32 {
		return value > 1 ? 1 : (value < -1 ? -1 : value);
	}

	public inline function pointer():cpp.RawConstPointer<cpp.Float32> {
		return cpp.Pointer.arrayElem(block.toData(), 0).constRaw;
	}

	public function start(device:cpp.Star<Device>):Bool {
		if (running || device == null) return false;

		this.device = device;
		blocks = 0;
		worstHeld = 0;

		final buffer = Audio.buffer(device);
		final least = buffer > 0 ? buffer : Audio.period(device) * 2;
		final primed = Std.int(rate * PRIMED);
		final aim = primed > least ? primed : least;

		cushion = aim;
		dropped = 0;
		leastHeld = aim;

		while (Audio.held(device) < aim) deliver();

		if (Audio.start(device) == 0) {
			this.device = null;
			return false;
		}

		alive = true;
		running = true;

		sys.thread.Thread.create(function():Void feed());
		return true;
	}

	public function stop():Void {
		alive = false;
		while (running) Sdl.sleep(0.0005);

		if (device != null) Audio.stop(device);
		device = null;
	}

	function deliver():Void {
		final held = transport;

		if (held == null) {
			drain();
			fill(frames);
		} else {
			final from = held.advance(frames, rate);
			drain();
			serve(held.stream, from, frames, held.entering);
		}

		final took = Audio.write(device, pointer(), frames);
		if (took < frames) dropped += frames - took;

		blocks++;
	}

	function feed():Void {
		final aim = cushion > 0 ? cushion : Audio.period(device) * 2;

		while (alive) {
			final held = Audio.held(device);

			if (held > worstHeld) worstHeld = held;
			if (held < leastHeld) leastHeld = held;

			if (held >= aim) {
				Sdl.sleep(0.0005);
				continue;
			}

			deliver();
		}

		running = false;
	}
}
