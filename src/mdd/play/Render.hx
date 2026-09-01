package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.host.Audio;
import mdd.host.Device;
import mdd.host.Sdl;

@:unreflective
final class Render {
	public static inline final BLOCK = 128;
	public static inline final COUPLING = 0.9975;
	public static inline final SCALE = 1.0 / 32768.0;
	public static inline final PRIMED = 0.100;

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

	var fmLeft:Int = 0;
	var fmRight:Int = 0;
	var olderLeft:Int = 0;
	var olderRight:Int = 0;

	var wentLeft:Float = 0;
	var wentRight:Float = 0;
	var heldLeft:Float = 0;
	var heldRight:Float = 0;

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
		olderLeft = 0;
		olderRight = 0;
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
		final many = count > frames ? frames : count;

		for (frame in 0...many) {
			fmAt += fmStep;

			while (fmAt >= 1) {
				fmAt -= 1;
				olderLeft = fmLeft;
				olderRight = fmRight;
				ym.sample();
				fmLeft = ym.left;
				fmRight = ym.right;
			}

			psgAt += psgStep;
			final clocks = Std.int(psgAt);
			psgAt -= clocks;
			psg.run(clocks);

			final other = psg.taken();

			final left = olderLeft + (fmLeft - olderLeft) * fmAt + other;
			final right = olderRight + (fmRight - olderRight) * fmAt + other;

			heldLeft = (left - wentLeft) + COUPLING * heldLeft;
			heldRight = (right - wentRight) + COUPLING * heldRight;
			wentLeft = left;
			wentRight = right;

			block[frame * 2] = clamped(heldLeft * SCALE);
			block[frame * 2 + 1] = clamped(heldRight * SCALE);
		}

		made += many;
		return many;
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
		final cushion = Std.int(rate * PRIMED);
		final aim = cushion > least ? cushion : least;

		while (Audio.held(device) < aim) {
			fill(frames);
			Audio.write(device, pointer(), frames);
			blocks++;
		}

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

	function feed():Void {
		final aim = Audio.period(device);

		while (alive) {
			drain();

			final held = Audio.held(device);
			if (held > worstHeld) worstHeld = held;

			if (held >= aim) {
				Sdl.sleep(0.0005);
				continue;
			}

			fill(frames);
			Audio.write(device, pointer(), frames);
			blocks++;
		}

		running = false;
	}
}
