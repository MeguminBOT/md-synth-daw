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
	static inline final COUPLED = 17.569;

	public static inline final CHIP = 0;
	public static inline final MODEL_ONE = 1;
	public static inline final MODEL_TWO = 2;
	public static inline final CONSOLES = 3;

	static final CORNERS:Array<Float> = [0, 3300.0, 7100.0];

	static inline final MATCHED = 0.8;

	var coupling:Float = 0.9975;

	var rollPole:Float = 0;
	var rollZero:Float = 0;
	var rollGain:Float = 1;

	var rolledLeft:Float = 0;
	var rolledRight:Float = 0;
	var rawLeft:Float = 0;
	var rawRight:Float = 0;

	public var console(default, set):Int = MODEL_ONE;

	function set_console(want:Int):Int {
		console = want < 0 ? 0 : (want >= CONSOLES ? CONSOLES - 1 : want);
		rolled();

		return console;
	}

	function rolled():Void {
		if (rate <= 0) return;

		final corner = CORNERS[console];

		rollPole = 0;
		rollZero = 0;
		rollGain = 1;

		if (corner <= 0 || corner >= rate * 0.5) return;

		final pole = Math.exp(-2 * Math.PI * corner / rate);

		final at = MATCHED * rate * 0.5;
		final cosine = Math.cos(2 * Math.PI * at / rate);

		final want = 1 / Math.sqrt(1 + (at / corner) * (at / corner));
		final under = Math.sqrt(1 - 2 * pole * cosine + pole * pole);
		final ratio = want * under / (1 - pole);

		final spread = 1 - ratio * ratio;
		final middle = 2 * (ratio * ratio - cosine);
		final root = middle * middle - 4 * spread * spread;

		var zero = 0.0;

		if (root >= 0 && spread != 0) {
			final held = Math.sqrt(root);

			final one = (-middle + held) / (2 * spread);
			final two = (-middle - held) / (2 * spread);

			zero = (one < 0 ? -one : one) < (two < 0 ? -two : two) ? one : two;
		}

		rollPole = pole;
		rollZero = zero;
		rollGain = (1 - pole) / (1 - zero);
	}
	public static inline final FULL_SCALE = 2560.0;
	static inline final SCALE = 1.0 / FULL_SCALE;
	static inline final PRIMED = 0.100;

	public static inline final TAPS = 2048;
	public static inline final TAP_EVERY = 4;
	static inline final FM_TAP = 1.0 / 200.0;
	static inline final PSG_TAP = 1.0 / 340.0;

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
	public var heardAt(default, null):Int = 0;

	public var peak(default, null):Float = 0;
	public var clipped(default, null):Int = 0;
	public var monitor:Float = 1;

	public static inline final SNAPS = 96;

	public final sounding:Sounding = new Sounding();

	final snapAt:Vector<Int> = new Vector<Int>(SNAPS);
	final snapNote:Vector<Int> = new Vector<Int>(SNAPS * mdd.song.Part.COUNT);
	final snapKeyed:Vector<Bool> = new Vector<Bool>(SNAPS * mdd.song.Part.COUNT);
	var snapNext:Int = 0;
	public var writes(default, null):Int = 0;
	public var poured(default, null):Int = 0;

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
	var worstHeld(default, null):Int = 0;

	static inline final BAND = 19845.0;

	static inline final PHASES = 32;

	static inline final WEIGHTS = 127;

	static inline final SQUARES = 384;

	final weights:Vector<Float> = new Vector<Float>(WEIGHTS * PHASES);
	final pastLeft:Vector<Float> = new Vector<Float>(WEIGHTS);
	final pastRight:Vector<Float> = new Vector<Float>(WEIGHTS);

	var pastAt:Int = 0;

	final squareWeights:Vector<Float> = new Vector<Float>(SQUARES * PHASES);
	final squarePast:Vector<Float> = new Vector<Float>(SQUARES);

	var squareAt:Int = 0;

	public function new(rate:Int, frames:Int = BLOCK, queue:Null<Queue> = null) {
		this.rate = rate <= 0 ? 48000 : rate;
		this.frames = frames <= 0 ? BLOCK : frames;
		this.queue = queue == null ? new Queue() : queue;

		block = new Vector<cpp.Float32>(this.frames * 2);

		coupling = Math.exp(-2 * Math.PI * COUPLED / this.rate);
		rolled();
		fmStep = Ym2612.CLOCK / (Ym2612.PER_SAMPLE * this.rate);
		psgStep = Sn76489.CLOCK / (Sn76489.DIVIDER * this.rate);

		shaped();
	}

	function shaped():Void {
		final chip = Ym2612.CLOCK / Ym2612.PER_SAMPLE;

		final kept = 0.45 * rate < BAND ? 0.45 * rate : BAND;

		var cut = kept / chip;
		if (cut > 0.5) cut = 0.5;

		final middle = (WEIGHTS - 1) * 0.5;

		for (phase in 0...PHASES) {
			final shift = phase / PHASES;
			final base = phase * WEIGHTS;

			var total = 0.0;

			for (index in 0...WEIGHTS) {
				final at = index - middle + shift;
				final sinc = at == 0 ? 2 * cut
					: Math.sin(2 * Math.PI * cut * at) / (Math.PI * at);

				final window = 0.42 - 0.5 * Math.cos(2 * Math.PI * index / (WEIGHTS - 1))
					+ 0.08 * Math.cos(4 * Math.PI * index / (WEIGHTS - 1));

				weights[base + index] = sinc * window;
				total += weights[base + index];
			}

			for (index in 0...WEIGHTS) weights[base + index] /= total;
		}

		for (index in 0...WEIGHTS) {
			pastLeft[index] = 0;
			pastRight[index] = 0;
		}

		final square = Sn76489.CLOCK / Sn76489.DIVIDER;

		var edge = kept / square;
		if (edge > 0.5) edge = 0.5;

		final centre = (SQUARES - 1) * 0.5;

		for (phase in 0...PHASES) {
			final shift = phase / PHASES;
			final base = phase * SQUARES;

			var whole = 0.0;

			for (index in 0...SQUARES) {
				final at = index - centre + shift;
				final sinc = at == 0 ? 2 * edge
					: Math.sin(2 * Math.PI * edge * at) / (Math.PI * at);

				final window = 0.42 - 0.5 * Math.cos(2 * Math.PI * index / (SQUARES - 1))
					+ 0.08 * Math.cos(4 * Math.PI * index / (SQUARES - 1));

				squareWeights[base + index] = sinc * window;
				whole += squareWeights[base + index];
			}

			for (index in 0...SQUARES) squareWeights[base + index] /= whole;
		}

		for (index in 0...SQUARES) squarePast[index] = 0;
	}

	public function reset():Void {
		ym.reset();
		psg.reset();
		queue.clear();

		fmAt = 0;
		psgAt = 0;
		pastAt = 0;
		squareAt = 0;

		for (index in 0...WEIGHTS) {
			pastLeft[index] = 0;
			pastRight[index] = 0;
		}

		for (index in 0...SQUARES) squarePast[index] = 0;
		fmLeft = 0;
		fmRight = 0;
		wentLeft = 0;
		wentRight = 0;
		heldLeft = 0;
		heldRight = 0;
		made = 0;
		writes = 0;
		poured = 0;
		heardAt = 0;
		snapNext = 0;
		sounding.forget();

		for (index in 0...SNAPS) snapAt[index] = -1;
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

	public function serve(stream:Null<Stream>, from:Int, count:Int, carry:Int = 0,
			fresh:Bool = false):Int {
		final many = count > frames ? frames : count;

		if (fresh || stream == null || poured > stream.count) poured = 0;

		var next = poured;
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

			while (fmAt >= 1) {
				fmAt -= 1;
				ym.sample();

				pastAt++;
				if (pastAt >= WEIGHTS) pastAt = 0;

				pastLeft[pastAt] = ym.left;
				pastRight[pastAt] = ym.right;
			}

			var gotLeft = 0.0;
			var gotRight = 0.0;
			var at = pastAt;

			var phase = Std.int(fmAt * PHASES);
			if (phase < 0) phase = 0;
			if (phase >= PHASES) phase = PHASES - 1;

			final base = phase * WEIGHTS;

			for (index in 0...WEIGHTS) {
				gotLeft += pastLeft[at] * weights[base + index];
				gotRight += pastRight[at] * weights[base + index];

				at--;
				if (at < 0) at = WEIGHTS - 1;
			}

			fmLeft = gotLeft;
			fmRight = gotRight;

			psgAt += psgStep;

			while (psgAt >= 1) {
				psgAt -= 1;

				squareAt++;
				if (squareAt >= SQUARES) squareAt = 0;

				squarePast[squareAt] = psg.sample();
			}

			var other = 0.0;
			var square = squareAt;

			var turn = Std.int(psgAt * PHASES);
			if (turn < 0) turn = 0;
			if (turn >= PHASES) turn = PHASES - 1;

			final tap = turn * SQUARES;

			for (index in 0...SQUARES) {
				other += squarePast[square] * squareWeights[tap + index];

				square--;
				if (square < 0) square = SQUARES - 1;
			}

			final left = fmLeft + other;
			final right = fmRight + other;

			heldLeft = (left - wentLeft) + coupling * heldLeft;
			heldRight = (right - wentRight) + coupling * heldRight;
			wentLeft = left;
			wentRight = right;

			tapNext++;

			if (tapNext >= TAP_EVERY) {
				tapNext = 0;
				tapping();
			}

			final wasLeft = rawLeft;
			final wasRight = rawRight;

			rawLeft = heldLeft;
			rawRight = heldRight;

			rolledLeft = rollGain * (heldLeft - rollZero * wasLeft) + rollPole * rolledLeft;
			rolledRight = rollGain * (heldRight - rollZero * wasRight) + rollPole * rolledRight;

			final wantLeft = rolledLeft * SCALE;
			final wantRight = rolledRight * SCALE;
			final loudest = (wantLeft < 0 ? -wantLeft : wantLeft)
				> (wantRight < 0 ? -wantRight : wantRight)
				? (wantLeft < 0 ? -wantLeft : wantLeft)
				: (wantRight < 0 ? -wantRight : wantRight);

			if (loudest > peak) peak = loudest;
			if (loudest > 1) clipped++;

			block[frame * 2] = clamped(wantLeft * monitor);
			block[frame * 2 + 1] = clamped(wantRight * monitor);

			held += Tempo.TICKS;
			while (held >= rate) {
				held -= rate;
				tick++;
			}
		}

		if (stream != null && fresh) {
			while (next < stream.count) {
				pour(stream, next);
				next++;
			}
		}

		poured = next;
		made += many;

		return many;
	}

	inline function pour(stream:Stream, index:Int):Void {
		final kind = stream.kindAt(index);
		final port = stream.portAt(index);
		final value = stream.valueAt(index);

		if (kind == Stream.PSG) psg.write(value);
		else ym.write(port, value);

		sounding.write(kind, port, value);
		writes++;
	}

	public function snapped():Void {
		final at = snapNext % SNAPS;
		snapAt[at] = made;

		for (index in 0...mdd.song.Part.COUNT) {
			snapNote[at * mdd.song.Part.COUNT + index] = sounding.notes[index];
			snapKeyed[at * mdd.song.Part.COUNT + index] = sounding.keyed[index];
		}

		snapNext++;
	}

	public function litAt(position:Int, into:Sounding):Bool {
		var best = -1;
		var found = -1;

		for (index in 0...SNAPS) {
			final at = snapAt[index];
			if (at < 0 || at > position || at <= found) continue;

			found = at;
			best = index;
		}

		if (best < 0) return false;

		for (index in 0...mdd.song.Part.COUNT) {
			into.notes[index] = snapNote[best * mdd.song.Part.COUNT + index];
			into.keyed[index] = snapKeyed[best * mdd.song.Part.COUNT + index];
		}

		return true;
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

	public function forgetPeak():Void {
		peak = 0;
		clipped = 0;
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

		sys.thread.Thread.create(function():Void {
			mdd.host.Crash.thread("the render thread");
			feed();
		});
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
			serve(held.stream, from, frames, held.entering, true);
		}

		snapped();

		final took = Audio.write(device, pointer(), frames);
		if (took < frames) dropped += frames - took;

		blocks++;
	}

	function feed():Void {
		final aim = cushion > 0 ? cushion : Audio.period(device) * 2;

		while (alive) {
			final held = Audio.held(device);

			heardAt = made - held;

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
