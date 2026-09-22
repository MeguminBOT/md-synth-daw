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
package mdd.chip;

import haxe.ds.Vector;

/**
	One FM channel: four operators, the algorithm that wires them together, the
	frequency word they are all tuned from, and the accumulator their outputs land in.

	It knows nothing above itself. Everything here comes from the part documentation
	and from measurement against a known-good YM2612.
**/
@:unreflective
final class Channel {
	/**
		The part's detune table, in phase increment units before the key code shift.
	**/
	static final DETUNE:Vector<Int> = Vector.fromArrayCopy([16, 17, 19, 20, 22, 24, 27, 29]);

	/**
		Maps the top four bits of a frequency word onto the low two bits of the key code,
		which is what scales every envelope rate and every detune.
	**/
	static final KEY_CODE:Vector<Int> =
		Vector.fromArrayCopy([0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 3, 3, 3, 3, 3, 3]);

	/**
		The LFO pitch table, one entry per depth and step, each packing three shift amounts
		into twelve bits.
	**/
	static final VIBRATO:Vector<Int> = Vector.fromArrayCopy([
		0x077, 0x077, 0x077, 0x077, 0x077, 0x077, 0x077, 0x077,
		0x077, 0x077, 0x077, 0x077, 0x074, 0x074, 0x074, 0x074,
		0x077, 0x077, 0x077, 0x074, 0x074, 0x074, 0x073, 0x073,
		0x077, 0x077, 0x074, 0x074, 0x073, 0x073, 0x221, 0x221,
		0x077, 0x077, 0x074, 0x073, 0x073, 0x073, 0x221, 0x072,
		0x077, 0x077, 0x073, 0x221, 0x072, 0x072, 0x220, 0x210,
		0x077, 0x077, 0x072, 0x121, 0x071, 0x071, 0x120, 0x110,
		0x077, 0x077, 0x071, 0x021, 0x070, 0x070, 0x020, 0x010
	]);

	/**
		The four operators, in the order the part slots them, in an array made at its size and
		never grown for the same reason as `Ym2612.channels`.
	**/
	public final operators:Array<Operator> = cpp.NativeArray.create(4);

	/**
		Which of the eight operator wirings this channel uses.
	**/
	public var algorithm:Int = 0;

	/**
		How much of operator one's own output is fed back into it, 0 for none.
	**/
	public var feedback:Int = 0;

	/**
		The eleven bit frequency word every operator is tuned from.
	**/
	public var frequency:Int = 0;

	/**
		The octave the frequency word sits in, 0 to 7.
	**/
	public var block:Int = 0;
	public var left:Bool = true;
	public var right:Bool = true;

	/**
		Channel three's second mode, where the first three operators each carry their own
		frequency and block instead of sharing the channel's.
	**/
	public var separate:Bool = false;

	/**
		The three extra frequency words `separate` mode reads.
	**/
	public final notes:Vector<Int> = new Vector<Int>(3);

	/**
		The three extra blocks that go with them.
	**/
	public final blocks:Vector<Int> = new Vector<Int>(3);

	/**
		Whether total level is applied at all. Only channel three in CSM mode clears it.
	**/
	public var levelled:Bool = true;

	/**
		How far the LFO swings the amplitude, as a shift, so 7 is no swing at all.
	**/
	public var tremoloDepth:Int = 7;

	/**
		How far the LFO swings the pitch, 0 for not at all.
	**/
	public var vibratoDepth:Int = 0;

	/**
		The key on nibble latched from register `$28`, one bit per operator. It reaches the
		operators as `keyRequest` on the next slot rather than at once.
	**/
	public var armed:Int = 0;

	/**
		What `armed` became once the part acted on it: which operators are keyed now.
	**/
	public var keyRequest:Int = 0;

	var published(default, null):Int = 0;

	/**
		The channel's last finished sample. `capture` is what moves a sample here, so every
		channel is read from the same instant.
	**/
	public var delivered(default, null):Int = 0;

	final outputs:Vector<Int> = new Vector<Int>(4);

	final codes:Vector<Int> = new Vector<Int>(4);

	var accumulated:Int = 0;
	var carried:Int = 0;
	var lateTwo:Int = 0;
	var earlierTwo:Int = 0;
	var previous:Int = 0;
	var older:Int = 0;
	var swept:Int = 0;

	public function new() {
		for (i in 0...4) operators[i] = new Operator();
		for (i in 0...4) outputs[i] = 0;
		for (i in 0...4) codes[i] = 0;
		for (i in 0...3) notes[i] = 0;
		for (i in 0...3) blocks[i] = 0;
	}

	/**
		Back to power on: every operator reset, both outputs on, and nothing keyed.
	**/
	public function reset():Void {
		for (each in operators) each.reset();
		for (i in 0...4) outputs[i] = 0;
		algorithm = 0;
		feedback = 0;
		frequency = 0;
		block = 0;
		left = true;
		right = true;
		separate = false;
		levelled = true;
		for (i in 0...3) notes[i] = 0;
		for (i in 0...3) blocks[i] = 0;
		tremoloDepth = 7;
		vibratoDepth = 0;
		swept = 0;
		armed = 0;
		keyRequest = 0;
		published = 0;
		delivered = 0;
		accumulated = 0;
		carried = 0;
		lateTwo = 0;
		earlierTwo = 0;
		previous = 0;
		older = 0;
		retune();
	}

	/**
		Sets the whole channel's block and frequency word and retunes every operator.

		@param block The octave, 0 to 7.
		@param frequency The eleven bit frequency word.
	**/
	public function setFrequency(block:Int, frequency:Int):Void {
		this.block = block & 7;
		this.frequency = frequency & 0x7FF;
		retune();
	}

	/**
		Sets one of the three frequencies `separate` mode uses, and retunes.

		@param index Which of the three, 0 to 2.
		@param block The octave for it.
		@param frequency The frequency word for it.
	**/
	public function setSeparate(index:Int, block:Int, frequency:Int):Void {
		blocks[index] = block & 7;
		notes[index] = frequency & 0x7FF;
		retune();
	}

	/**
		Takes the LFO current step, which is where vibrato comes from, and retunes.

		@param step The LFO phase, 0 to 31.
	**/
	public function tune(step:Int):Void {
		swept = step;
		retune();
	}

	/**
		@param index Which operator, 0 to 3.
		@return The frequency word that operator is tuned from, which is the channel's unless
			`separate` is on and this is not the last operator.
	**/
	public inline function noteOf(index:Int):Int {
		return separate && index != 3 ? notes[index] : frequency;
	}

	/**
		@param index Which operator, 0 to 3.
		@return The block that goes with `noteOf`.
	**/
	public inline function blockOf(index:Int):Int {
		return separate && index != 3 ? blocks[index] : block;
	}

	/**
		@param index Which operator, 0 to 3.
		@return The key code for that operator, which scales its envelope rates.
	**/
	public inline function keyCode(index:Int):Int {
		return codes[index];
	}

	/**
		Works out every operator phase increment again from the frequency, the block, the
		vibrato, the detune and the multiple. Called whenever any of those move.
	**/
	function retune():Void {
		for (i in 0...4) {
			final each = operators[i];
			final note = noteOf(i);
			final at = blockOf(i);
			codes[i] = (at << 2) | KEY_CODE[(note >> 7) & 0x0F];

			final tuned = ((note << 1) + vibratoOf(note)) & 0xFFF;

			var step = (tuned << at) >> 2;
			final amount = detuneOf(each.detune & 3, codes[i]);
			step += (each.detune & 4) != 0 ? -amount : amount;
			step &= 0x1FFFF;

			each.increment = (each.multiple == 0 ? step >> 1 : step * each.multiple) & 0xFFFFF;
		}
	}

	/**
		@param note The frequency word being tuned.
		@return How far the LFO moves it on the current step, signed.
	**/
	inline function vibratoOf(note:Int):Int {
		if (vibratoDepth == 0) return 0;

		final at = (swept & 8) != 0 ? 7 - (swept & 7) : swept & 7;
		final shifts = VIBRATO[(vibratoDepth << 3) | at];
		final high = note >> 4;
		final size = ((high >> (shifts & 0x0F)) + (high >> ((shifts >> 4) & 0x0F))) >> (shifts >> 8);

		return (swept & 16) != 0 ? -size : size;
	}

	/**
		@param amount The low two bits of the detune field.
		@param keyCode The key code of the operator, which the offset depends on.
		@return The detune offset in phase increment units.
	**/
	static function detuneOf(amount:Int, keyCode:Int):Int {
		if (amount == 0) return 0;

		final code = keyCode > 0x1C ? 0x1C : keyCode;
		final sum = (code >> 2) + 9 + (amount == 3 ? 3 : (amount & 2));
		return DETUNE[((sum & 1) << 2) | (code & 3)] >> (9 - (sum >> 1));
	}

	/**
		Runs one operator for one slot: reads its output, feeds it wherever the
		algorithm sends it, and moves its phase and envelope on. The part visits twenty
		four slots per sample, four per channel, and this is one of them.

		@param turn Which pass through the channel this slot is, 0 to 3.
		@param index Which operator this slot runs.
		@param counter The part's global envelope counter.
		@param tick Whether that counter moved since the last slot.
		@param swell The LFO amplitude ramp for this sample.
		@param pulsed Whether CSM mode is keying this channel on this sample.
	**/
	public function slot(turn:Int, index:Int, counter:Int, tick:Bool, swell:Int,
			pulsed:Bool):Void {
		if (turn == 1) {
			published = accumulated;
			accumulated = 0;
		}

		accumulated = accumulate(accumulated, carried);

		final each = operators[index];

		final wanted = pulsed || (keyRequest & (1 << index)) != 0;

		var out = 0;

		if (each.idle(wanted)) {
			each.step();
		} else {
			each.shape(wanted);

			final pressed = wanted && !each.keyed;
			final started = pressed || (each.keyed && each.repeats);
			final restarting = pressed || each.restarts;

			final attenuation = (levelled ? each.totalLevel << 3 : 0)
				+ (each.tremolo ? swell >> tremoloDepth : 0);

			out = each.output(modulation(index), attenuation);

			if (restarting) each.phase = 0;
			else each.step();

			if (each.keyed && !wanted) each.lift();
			each.advance(keyCode(index), counter, tick, wanted, started, pulsed);
			each.keyed = wanted;
		}

		outputs[index] = out;

		if (index == 0) {
			older = previous;
			previous = out;
		} else if (index == 1) {
			earlierTwo = lateTwo;
			lateTwo = out;
		}

		carried = carries(index) ? out : 0;
	}

	/**
		Publishes the sample the last full pass accumulated as `delivered`.
	**/
	public inline function capture():Void {
		delivered = published;
	}

	/**
		@param total The accumulator so far.
		@param value A carrier output to add.
		@return The accumulator with the part's own shift and clamp applied.
	**/
	static inline function accumulate(total:Int, value:Int):Int {
		final sum = total + (value >> 5);
		return sum > 255 ? 255 : (sum < -256 ? -256 : sum);
	}

	/**
		@param index Which operator is about to run.
		@return What is added to its phase this slot: the feedback for operator one, and whatever
			the algorithm routes into the others.
	**/
	inline function modulation(index:Int):Int {
		return switch (index) {
			case 0:
				feedback == 0 ? 0 : (previous + older) >> (10 - feedback);
			case 2:
				switch (algorithm) {
					case 0, 2: lateTwo >> 1;
					case 1: (older + lateTwo) >> 1;
					case 5: older >> 1;
					case _: 0;
				}
			case 1:
				switch (algorithm) {
					case 0, 4, 5, 6: outputs[0] >> 1;
					case 3: outputs[0] >> 1;
					case _: 0;
				}
			case _:
				switch (algorithm) {
					case 0, 1, 4: outputs[2] >> 1;
					case 2: (outputs[0] + outputs[2]) >> 1;
					case 3: (earlierTwo + outputs[2]) >> 1;
					case 5: outputs[0] >> 1;
					case _: 0;
				}
		}
	}

	/**
		@param index Which operator.
		@return True where it is a carrier under the current algorithm, so its output lands in the
			accumulator rather than only modulating another operator.
	**/
	inline function carries(index:Int):Bool {
		return switch (index) {
			case 0: algorithm == 7;
			case 2: algorithm >= 5;
			case 1: algorithm >= 4;
			case _: true;
		}
	}

	/**
		@return The channel's sample on the left, or nought where it is not panned there.
	**/
	inline function onLeft():Int {
		return left ? delivered : 0;
	}

	/**
		@return The same on the right.
	**/
	inline function onRight():Int {
		return right ? delivered : 0;
	}
}
