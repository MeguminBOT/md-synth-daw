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
	One of the four operators of an FM channel: a phase accumulator, an envelope
	generator, and the two logarithmic tables that turn the pair into a sample.

	Written from the part documentation and then measured against a known-good YM2612,
	sample for sample, rather than approximated by ear. It knows nothing about the
	channel that owns it or about anything above that.
**/
@:unreflective
final class Operator {
	/**
		A quarter of a sine, held as attenuation in the same logarithmic units the envelope
		is in, so applying an envelope to a sample is an addition rather than a multiply.
	**/
	static final SINE:Vector<Int> = sine();

	/**
		The inverse of `SINE`: attenuation back to a linear amplitude.
	**/
	static final EXPONENTIAL:Vector<Int> = exponential();

	/**
		Builds `SINE` once, at load. A table shipped as data says nothing about where it
		came from; this says exactly what the part holds.

		@return The 256 entry quarter sine, in attenuation units.
	**/
	static function sine():Vector<Int> {
		final out = new Vector<Int>(256);
		for (i in 0...256) {
			final value = Math.sin((i + 0.5) * Math.PI / 512);
			out[i] = Std.int(Math.round(-Math.log(value) / Math.log(2) * 256));
		}
		return out;
	}

	/**
		Builds `EXPONENTIAL` once, at load, for the same reason.

		@return The 256 entry attenuation to amplitude table.
	**/
	static function exponential():Vector<Int> {
		final out = new Vector<Int>(256);
		for (i in 0...256) out[i] = Std.int(Math.round((Math.pow(2, i / 256.0) - 1) * 1024));
		return out;
	}

	public var detune:Int = 0;
	public var multiple:Int = 0;

	/**
		This operator's own attenuation, 0 loudest and 127 silent, at three quarters of a
		decibel a step.
	**/
	public var totalLevel:Int = 0;
	public var keyScale:Int = 0;
	public var attackRate:Int = 0;
	public var decayRate:Int = 0;
	public var sustainRate:Int = 0;
	public var releaseRate:Int = 0;

	public var sustainLevel:Int = 0;

	public var tremolo:Bool = false;

	/**
		The phase accumulator, twenty bits, of which the top ten index the sine.
	**/
	public var phase:Int = 0;

	/**
		How far `phase` moves per sample. The channel works this out from the frequency
		word, the block, the detune and the multiple, and writes it here.
	**/
	public var increment:Int = 0;

	/**
		Current attenuation, 0 loudest and 1023 silent. This is the raw value; `shown` is
		what the output stage reads.
	**/
	public var envelope:Int = 1023;
	public var state:Phase = Release;

	/**
		Whether the operator was keyed on the previous slot. `advance` compares it against
		what is wanted now to find the key edges.
	**/
	public var keyed:Bool = false;

	/**
		The SSG-EG nibble. Bit three enables it and the low three bits pick one of eight
		shapes.
	**/
	public var ssg:Int = 0;

	/**
		Set by `shape` when the SSG shape asks for the phase to begin again. Two of the
		eight shapes do.
	**/
	public var restarts(default, null):Bool = false;

	/**
		Set by `shape` when the SSG shape asks for the envelope to begin again.
	**/
	public var repeats(default, null):Bool = false;

	var rising:Bool = false;
	var inverted:Bool = false;
	var holding:Bool = false;

	public function new() {}

	/**
		Back to power on: silent, released, and with every register value at nought.
	**/
	public function reset():Void {
		detune = 0;
		multiple = 0;
		totalLevel = 0;
		keyScale = 0;
		attackRate = 0;
		decayRate = 0;
		sustainRate = 0;
		releaseRate = 0;
		sustainLevel = 0;
		tremolo = false;
		phase = 0;
		increment = 0;
		envelope = 1023;
		state = Release;
		keyed = false;
		ssg = 0;
		restarts = false;
		repeats = false;
		rising = false;
		inverted = false;
		holding = false;
	}

	/**
		Takes one register write and unpacks it into the fields it carries.

		@param group The register base the write arrived under: `$30` detune and multiple, `$40`
			total level, `$50` rate scaling and attack, `$60` tremolo and decay, `$70` sustain rate,
			`$80` sustain level and release, `$90` SSG-EG. Any other value is ignored.
		@param value The byte written.
	**/
	public function set(group:Int, value:Int):Void {
		switch (group) {
			case 0x30:
				detune = (value >> 4) & 7;
				multiple = value & 0x0F;
			case 0x40:
				totalLevel = value & 0x7F;
			case 0x50:
				keyScale = (value >> 6) & 3;
				attackRate = value & 0x1F;
			case 0x60:
				tremolo = (value & 0x80) != 0;
				decayRate = value & 0x1F;
			case 0x70:
				sustainRate = value & 0x1F;
			case 0x90:
				ssg = value & 0x0F;
			case 0x80:
				final level = (value >> 4) & 0x0F;
				sustainLevel = (level == 0x0F ? 31 : level) << 1;
				releaseRate = (value & 0x0F) * 2 + 1;
			case _:
		}
	}

	/**
		Reads the SSG-EG shape for this slot and sets `restarts`, `repeats` and the
		inversion from it. Call it before `output`, because the inversion decides what
		`shown` answers.

		@param wanted Whether the operator is being keyed on this slot.
	**/
	public function shape(wanted:Bool):Void {
		restarts = false;
		repeats = false;
		holding = false;

		var direction = false;

		if ((ssg & 0x08) != 0) {
			direction = rising;

			if ((envelope & 0x200) != 0) {
				if ((ssg & 0x03) == 0x00) restarts = true;
				if ((ssg & 0x01) == 0x00) repeats = true;
				if ((ssg & 0x03) == 0x02) direction = !direction;
				if ((ssg & 0x03) == 0x03) direction = true;
			}

			if (wanted && ((ssg & 0x07) == 0x05 || (ssg & 0x07) == 0x03)) holding = true;

			direction = direction && keyed;
		}

		rising = direction;
		inverted = (rising != ((ssg & 0x0C) == 0x0C)) && keyed;
	}

	/**
		Whether the operator can be stepped and nothing else.

		@param wanted Whether the operator is being keyed on this slot.
		@return True where it is silent, released, not keyed, not being keyed, and running no SSG
			shape, so the whole slot can be skipped.
	**/
	public inline function idle(wanted:Bool):Bool {
		return !wanted && !keyed && ssg == 0 && envelope == 1023 && state == Release;
	}

	/**
		Folds an inverted envelope back into a plain one, which is what a key off has to do
		before the release can run from where the sound actually was.
	**/
	public inline function lift():Void {
		envelope = shown();
	}

	/**
		@return The envelope as the output stage sees it, inverted where the SSG shape asks.
	**/
	public inline function shown():Int {
		return inverted ? (512 - envelope) & 0x3FF : envelope;
	}

	/**
		Moves the envelope on by one slot.

		@param keyCode The channel's key code for this operator, which scales every rate.
		@param counter The part's global envelope counter, which decides which rates step at all on
			this tick.
		@param tick Whether the envelope counter moved since the last slot.
		@param held Whether the key is still down.
		@param started Whether this slot is a key on edge.
		@param pulsed Whether the part is re-reading total level, which CSM mode does.
	**/
	public function advance(keyCode:Int, counter:Int, tick:Bool, held:Bool, started:Bool,
			pulsed:Bool):Void {
		final shaped = (ssg & 0x08) != 0;

		final rate = rateOf(keyCode >> (3 - keyScale), started ? Attack : state);
		final fastest = rate >= 62;

		var size = 0;
		if (tick && rate != 0) {
			if (rate < 48) {
				final shift = 11 - (rate >> 2);
				if ((counter & ((1 << shift) - 1)) == 0) {
					size = STEP[((rate & 3) << 3) | ((counter >> shift) & 7)];
				}
			} else {
				final grow = FASTER[((rate & 3) << 2) | (counter & 3)] + (rate >> 2) - 12;
				size = 1 << (grow > 3 ? 3 : grow);
			}
		}

		final spent = shaped ? (envelope & 0x200) != 0 : (envelope & 0x3F0) == 0x3F0;
		if (shaped && state != Attack) size <<= 2;

		if (started) {
			final again = state == Attack;
			state = Attack;

			var step = 0;
			if (fastest) envelope = 0;
			else if (again && envelope != 0 && size != 0 && held) step = ((~envelope) * size) >> 4;

			if (pulsed) envelope |= totalLevel << 3;
			envelope = (envelope + step) & 0x3FF;
			return;
		}

		var next = state;
		var step = 0;

		switch (state) {
			case Attack:
				if (envelope == 0) next = Decay;
				else if (size != 0 && !fastest && held) step = ((~envelope) * size) >> 4;

			case Decay:
				if ((envelope >> 4) == sustainLevel) next = Sustain;
				else if (!spent && size != 0) step = size;

			case Sustain, Release:
				if (!spent && size != 0) step = size;
		}

		if (!held) next = Release;

		if (pulsed) envelope |= totalLevel << 3;

		if (state != Attack && spent && !holding) {
			next = Release;
			envelope = 1023;
			step = 0;
		}

		envelope = (envelope + step) & 0x3FF;
		state = next;
	}

	/**
		The step pattern below rate 48, indexed by the low two bits of the rate and by the
		envelope counter: some ticks step and some do not.
	**/
	static final STEP:Vector<Int> = Vector.fromArrayCopy([
		0, 1, 0, 1, 0, 1, 0, 1,
		0, 1, 0, 1, 1, 1, 0, 1,
		0, 1, 1, 1, 0, 1, 1, 1,
		0, 1, 1, 1, 1, 1, 1, 1
	]);

	/**
		The same at rate 48 and above, where a tick steps by more than one.
	**/
	static final FASTER:Vector<Int> = Vector.fromArrayCopy([
		0, 0, 0, 0,
		1, 0, 0, 0,
		1, 0, 1, 0,
		1, 1, 1, 0
	]);

	/**
		@param scaling The key code shifted by the rate scaling field.
		@param which Which envelope stage the rate is wanted for.
		@return The rate for that stage, clamped to 63. A base rate of nought answers nought and
			never steps, whatever the scaling.
	**/
	function rateOf(scaling:Int, which:Phase):Int {
		final base = switch (which) {
			case Attack: attackRate;
			case Decay: decayRate;
			case Sustain: sustainRate;
			case Release: releaseRate;
		}

		if (base == 0) return 0;
		final rate = base * 2 + scaling;
		return rate > 63 ? 63 : rate;
	}

	/**
		@param attenuation Extra attenuation to add, from total level and tremolo.
		@return The envelope plus that attenuation, clamped at silence.
	**/
	public inline function level(attenuation:Int):Int {
		final total = shown() + attenuation;
		return total > 1023 ? 1023 : total;
	}

	/**
		One sample from this operator.

		@param modulation Added to the phase before the sine is read, which is how one operator
			modulates another.
		@param added Extra attenuation from total level and tremolo.
		@return The sample, signed, at the part's own scale.
	**/
	public function output(modulation:Int, added:Int):Int {
		final at = ((phase >> 10) + modulation) & 0x3FF;
		final quarter = at & 0xFF;
		final mirrored = (at & 0x100) != 0 ? 255 - quarter : quarter;

		var attenuation = SINE[mirrored] + (level(added) << 2);
		if (attenuation > 0x1FFF) attenuation = 0x1FFF;

		final value = ((EXPONENTIAL[(~attenuation) & 0xFF] + 1024) << 2) >> (attenuation >> 8);
		return (at & 0x200) != 0 ? -value : value;
	}

	/**
		Advances the phase by one sample and wraps it to twenty bits.
	**/
	public inline function step():Void {
		phase = (phase + increment) & 0xFFFFF;
	}
}
