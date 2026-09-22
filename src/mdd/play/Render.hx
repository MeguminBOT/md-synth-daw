/*
	MD Synth DAW
	https://github.com/MeguminBOT/md-synth-daw

	MIT License

	Copyright (c) 2026 MeguminBOT and the md-synth-daw contributors

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.

	SPDX-License-Identifier: MIT
*/
package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.host.Audio;
import mdd.host.Device;
import mdd.host.Sdl;
import mdd.song.Tempo;

/**
	The render thread: two chips, a resampler, the output stage the console puts after
	them, and the device the result is served to.

	Everything reachable from `serve` runs on the audio thread, and it allocates
	nothing: fixed-size state only, no closures, no `Dynamic`, no array growth, no
	string building. A pause here is heard. It reaches a collector safe point once
	per block rather than declaring itself outside the collector, which frees what
	only this thread is holding.

	The same class does the offline render an export needs, which is what makes an
	export the same sound as playback rather than a second path that could drift.
**/
@:unreflective
final class Render {
	/**
		Frames per block, which is the unit everything here works in.
	**/
	public static inline final BLOCK = 128;

	/**
		The corner of the coupling capacitor on the real board, in hertz. It is the one
		filter here that is not an effect: the hardware has it whether or not anyone wants
		it.
	**/
	static inline final COUPLED = 17.569;

	/**
		Output stage: the chips alone, with nothing after them.
	**/
	public static inline final CHIP = 0;

	/**
		Output stage: a Mega Drive, which rolls off above three and a bit kilohertz.
	**/
	public static inline final MODEL_ONE = 1;

	/**
		Output stage: a Mega Drive 2, which rolls off much higher and so sounds brighter.
	**/
	public static inline final MODEL_TWO = 2;

	/**
		How many output stages there are.
	**/
	public static inline final CONSOLES = 3;

	/**
		The roll off corner of each output stage, in hertz. Nought means no roll off.
	**/
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

	/**
		Which output stage the render goes through. Setting it refits the filter, and a
		value outside the range is clamped rather than refused.
	**/
	public var console(default, set):Int = MODEL_ONE;

	function set_console(want:Int):Int {
		console = want < 0 ? 0 : (want >= CONSOLES ? CONSOLES - 1 : want);
		rolled();

		return console;
	}

	/**
		Refits the roll off filter for the current output stage and rate.
	**/
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

	/**
		What the summed chips reach at their loudest, and so what the float output is
		scaled by.
	**/
	public static inline final FULL_SCALE = 2560.0;
	static inline final SCALE = 1.0 / FULL_SCALE;

	/**
		How much audio is written before the device is started. A WASAPI device asks for
		more in its first few callbacks than the buffer size it reports, and priming
		exactly the reported size underran three times in the first quarter second, every
		run, and never again after.
	**/
	static inline final PRIMED = 0.100;

	/**
		How many samples the scope can read back. Every sample is kept and the scope decides
		how many of them to use, so this holds about 170 ms at 48 kHz: enough that a frame
		the main thread was late for does not leave a gap in a lane.
	**/
	public static inline final TAPS = 8192;
	static inline final FM_TAP = 1.0 / 200.0;
	static inline final PSG_TAP = 1.0 / 340.0;

	/**
		The ring the scope reads. Written on the render thread and read on the main one,
		which is safe because a stale sample in a waveform is not a fault.
	**/
	public final taps:haxe.ds.Vector<cpp.Float32> =
		new haxe.ds.Vector<cpp.Float32>(mdd.song.Part.COUNT * TAPS);

	/**
		How many samples have been put in `taps` since the start.
	**/
	public var tapped(default, null):Int = 0;

	/**
		How many frames the device has in hand.
	**/
	public var cushion(default, null):Int = 0;

	/**
		How many times the device asked for audio that was not there. Anything but nought
		is an underrun and is heard.
	**/
	public var dropped(default, null):Int = 0;

	/**
		The smallest the cushion has been since it was last forgotten.
	**/
	public var leastHeld(default, null):Int = 0;

	/**
		The FM part this render drives.
	**/
	public final ym:Ym2612 = new Ym2612();

	/**
		The square part this render drives.
	**/
	public final psg:Sn76489 = new Sn76489();

	/**
		Where register writes arrive from the main thread.
	**/
	public final queue:Queue;

	/**
		The output rate in hertz. Both chips run at their own rates and are resampled to
		this one.
	**/
	public var rate(default, null):Int;

	/**
		Frames per block for this render.
	**/
	public var frames(default, null):Int;

	/**
		How many frames have been produced since the start.
	**/
	public var made(default, null):Int = 0;

	/**
		Where in the song the device is actually playing, which is behind what has been
		produced by whatever the cushion holds.
	**/
	public var heardAt(default, null):Int = 0;

	/**
		The loudest sample since the peak was last forgotten.
	**/
	public var peak(default, null):Float = 0;

	/**
		How many samples went past full scale.
	**/
	public var clipped(default, null):Int = 0;

	/**
		Monitoring gain. It changes what is heard and never what is exported.
	**/
	public var monitor:Float = 1;

	/**
		How many keyed state snapshots are kept, one per block.
	**/
	public static inline final SNAPS = 96;

	/**
		What is keyed right now, for the meters and the channel rack.
	**/
	public final sounding:Sounding = new Sounding();

	final snapAt:Vector<Int> = new Vector<Int>(SNAPS);
	final snapNote:Vector<Int> = new Vector<Int>(SNAPS * mdd.song.Part.COUNT);
	final snapKeyed:Vector<Bool> = new Vector<Bool>(SNAPS * mdd.song.Part.COUNT);
	var snapNext:Int = 0;

	/**
		How many register writes this render has taken.
	**/
	public var writes(default, null):Int = 0;

	/**
		How far through the stream an offline render has read. Held as a field rather than
		a local because the collector traces a field and may not trace a register.
	**/
	public var poured(default, null):Int = 0;

	/**
		The block being filled, interleaved stereo.
	**/
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

	/**
		The transport this render reports its position to, where there is one.
	**/
	public var transport:Null<Transport> = null;

	var device:cpp.Star<Device> = null;
	var alive:Bool = false;

	/**
		Whether the device is started.
	**/
	public var running(default, null):Bool = false;

	/**
		How many blocks have been served.
	**/
	public var blocks(default, null):Int = 0;
	var worstHeld(default, null):Int = 0;

	/**
		The resampler pass band, in hertz.
	**/
	static inline final BAND = 19845.0;

	/**
		How many fractional phases the resampler kernel is built for.
	**/
	static inline final PHASES = 32;

	/**
		Taps per phase of the FM resampler kernel. A multiple of four, because the kernel is
		summed in four runs, one tap of each at a time.
	**/
	static inline final WEIGHTS = 512;

	/**
		Taps per phase of the square part's kernel, a multiple of four for the same reason.
	**/
	static inline final SQUARES = 384;

	final weights:Vector<Float> = new Vector<Float>(WEIGHTS * PHASES);

	/**
		The last `WEIGHTS` FM samples on the left, each held twice, `WEIGHTS` apart, so the
		kernel reads them newest first as one unbroken run down from `pastAt + WEIGHTS`.
	**/
	final pastLeft:Vector<Float> = new Vector<Float>(WEIGHTS * 2);

	/**
		The same on the right.
	**/
	final pastRight:Vector<Float> = new Vector<Float>(WEIGHTS * 2);

	var pastAt:Int = 0;

	final squareWeights:Vector<Float> = new Vector<Float>(SQUARES * PHASES);

	/**
		The last `SQUARES` square part samples, held twice in the same way.
	**/
	final squarePast:Vector<Float> = new Vector<Float>(SQUARES * 2);

	var squareAt:Int = 0;

	/**
		Builds a render and its resampler kernel.

		@param rate The output rate in hertz. Anything at or below nought becomes 48000.
		@param frames Frames per block. Anything at or below nought becomes `BLOCK`.
		@param queue Where register writes arrive from, or null for a queue of its own.
	**/
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

	/**
		Builds the resampler kernel, once, in the constructor.
	**/
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

		for (index in 0...WEIGHTS * 2) {
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

		for (index in 0...SQUARES * 2) squarePast[index] = 0;
	}

	/**
		Both chips back to power on, the filters cleared, and every counter at nought.
	**/
	public function reset():Void {
		ym.reset();
		psg.reset();
		queue.clear();

		fmAt = 0;
		psgAt = 0;
		pastAt = 0;
		squareAt = 0;

		for (index in 0...WEIGHTS * 2) {
			pastLeft[index] = 0;
			pastRight[index] = 0;
		}

		for (index in 0...SQUARES * 2) squarePast[index] = 0;
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

	/**
		Takes everything waiting in the queue and applies it to the chips.

		@return How many writes were taken.
	**/
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

	/**
		Renders frames with no register writes at all, which is what silence needs.

		@param count How many frames to render, capped at one block.
		@return How many frames were actually rendered.
	**/
	public function fill(count:Int):Int {
		return serve(null, 0, count);
	}

	/**
		Renders one span into `block`. Runs both chips at their own rates, applies each
		register write at its own sample, resamples to the output rate, and puts the
		result through the output stage.
	
		This is the audio thread. It allocates nothing and it reaches a collector safe
		point once a block.

		@param stream The writes to apply, or null to render silence.
		@param from Where in the span the first frame sits, in output samples.
		@param count How many frames to render, capped at one block.
		@param carry How many samples of the previous span to carry over, for a render that is not
			starting fresh.
		@param fresh Whether to start reading the stream from its beginning again.
		@return How many frames were rendered.
	**/
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
				pastLeft[pastAt + WEIGHTS] = ym.left;
				pastRight[pastAt] = ym.right;
				pastRight[pastAt + WEIGHTS] = ym.right;
			}

			var phase = Std.int(fmAt * PHASES);
			if (phase < 0) phase = 0;
			if (phase >= PHASES) phase = PHASES - 1;

			final base = phase * WEIGHTS;
			final newest = pastAt + WEIGHTS;

			var leftOne = 0.0;
			var leftTwo = 0.0;
			var leftThree = 0.0;
			var leftFour = 0.0;
			var rightOne = 0.0;
			var rightTwo = 0.0;
			var rightThree = 0.0;
			var rightFour = 0.0;
			var reach = 0;

			while (reach < WEIGHTS) {
				final weightOne = weights[base + reach];
				final weightTwo = weights[base + reach + 1];
				final weightThree = weights[base + reach + 2];
				final weightFour = weights[base + reach + 3];
				final at = newest - reach;

				leftOne += pastLeft[at] * weightOne;
				leftTwo += pastLeft[at - 1] * weightTwo;
				leftThree += pastLeft[at - 2] * weightThree;
				leftFour += pastLeft[at - 3] * weightFour;

				rightOne += pastRight[at] * weightOne;
				rightTwo += pastRight[at - 1] * weightTwo;
				rightThree += pastRight[at - 2] * weightThree;
				rightFour += pastRight[at - 3] * weightFour;

				reach += 4;
			}

			fmLeft = (leftOne + leftTwo) + (leftThree + leftFour);
			fmRight = (rightOne + rightTwo) + (rightThree + rightFour);

			psgAt += psgStep;

			while (psgAt >= 1) {
				psgAt -= 1;

				squareAt++;
				if (squareAt >= SQUARES) squareAt = 0;

				final level:Float = psg.sample();
				squarePast[squareAt] = level;
				squarePast[squareAt + SQUARES] = level;
			}

			var turn = Std.int(psgAt * PHASES);
			if (turn < 0) turn = 0;
			if (turn >= PHASES) turn = PHASES - 1;

			final tap = turn * SQUARES;
			final newestSquare = squareAt + SQUARES;

			var squareOne = 0.0;
			var squareTwo = 0.0;
			var squareThree = 0.0;
			var squareFour = 0.0;
			var squareReach = 0;

			while (squareReach < SQUARES) {
				final at = newestSquare - squareReach;

				squareOne += squarePast[at] * squareWeights[tap + squareReach];
				squareTwo += squarePast[at - 1] * squareWeights[tap + squareReach + 1];
				squareThree += squarePast[at - 2] * squareWeights[tap + squareReach + 2];
				squareFour += squarePast[at - 3] * squareWeights[tap + squareReach + 3];

				squareReach += 4;
			}

			final other = (squareOne + squareTwo) + (squareThree + squareFour);

			final left = fmLeft + other;
			final right = fmRight + other;

			heldLeft = (left - wentLeft) + coupling * heldLeft;
			heldRight = (right - wentRight) + coupling * heldRight;
			wentLeft = left;
			wentRight = right;

			tapping();

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

	/**
		Records what is keyed now, so the interface can read back what was sounding at a
		position the device has already played.
	**/
	public function snapped():Void {
		final at = snapNext % SNAPS;
		snapAt[at] = made;

		for (index in 0...mdd.song.Part.COUNT) {
			snapNote[at * mdd.song.Part.COUNT + index] = sounding.notes[index];
			snapKeyed[at * mdd.song.Part.COUNT + index] = sounding.keyed[index];
		}

		snapNext++;
	}

	/**
		Reads back the keyed state at a position, from the snapshots.

		@param position A position in output samples from the start.
		@param into Filled in with what was keyed there.
		@return False where the position is older than anything still kept, leaving `into`
			untouched.
	**/
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

	/**
		Forgets the peak and the clip count.
	**/
	public function forgetPeak():Void {
		peak = 0;
		clipped = 0;
	}

	/**
		@param value A sample.
		@return The same sample held to plus or minus one.
	**/
	static inline function clamped(value:Float):cpp.Float32 {
		return value > 1 ? 1 : (value < -1 ? -1 : value);
	}

	/**
		@return A raw pointer to the block, for the device to read without copying.
	**/
	public inline function pointer():cpp.RawConstPointer<cpp.Float32> {
		return cpp.Pointer.arrayElem(block.toData(), 0).constRaw;
	}

	/**
		Primes the ring and starts the device. The device is opened stopped, so it never
		plays what has not been written yet.

		@param device The audio device to serve.
		@return False where it is already running or the device is null.
	**/
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

	/**
		Stops the device and lets the render thread finish.
	**/
	public function stop():Void {
		alive = false;
		while (running) Sdl.sleep(0.0005);

		if (device != null) Audio.stop(device);
		device = null;
	}

	/**
		Hands whatever is ready to the device.
	**/
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

	/**
		Keeps the ring full while the device is running.
	**/
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
