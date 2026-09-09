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
	The SN76489, three square channels and a noise channel sharing one write port.

	It is named for the part rather than for what it does here, because the Master
	System carries the same one and a second hardware profile should slot in beside
	this rather than around it. Like the FM part it imports nothing above `mdd.chip`.
**/
@:unreflective
final class Sn76489 {
	/**
		The clock a Mega Drive gives the part, in hertz.
	**/
	public static inline final CLOCK = 3579545;

	/**
		How many clocks pass between internal steps.
	**/
	public static inline final DIVIDER = 16;

	/**
		The shift register taps for white noise: bits 0 and 3.
	**/
	static inline final WHITE = 0x0009;

	/**
		The single tap that makes the noise periodic instead.
	**/
	static inline final PERIODIC = 0x0001;

	/**
		The ten bit period of each channel. The fourth entry is unused; the noise channel
		takes its rate from `noise`.
	**/
	public final tone:Vector<Int> = new Vector<Int>(4);

	/**
		Each channel's attenuation, 0 loudest and 15 silent, at two decibels a step.
	**/
	public final attenuation:Vector<Int> = new Vector<Int>(4);

	/**
		The amplitude an unattenuated channel reaches.
	**/
	static inline final LOUDEST = 255;

	/**
		The sixteen attenuation steps as amplitudes, built once in the constructor.
	**/
	final volumes:Vector<Int> = new Vector<Int>(16);

	final counter:Vector<Int> = new Vector<Int>(4);
	final output:Vector<Int> = new Vector<Int>(4);

	/**
		How many writes the part has taken since it was made.
	**/
	public var writes(default, null):Int = 0;

	var latched:Int = 0;

	/**
		The noise control nibble: bit two picks white over periodic, and the low two bits
		pick the rate, of which the fourth is the third square's own period.
	**/
	public var noise(default, null):Int = 0;

	/**
		The noise shift register. Writing the noise control register reloads it, which is
		what makes a noise burst start the same way every time.
	**/
	public var shift(default, null):Int = 0x8000;
	var spare:Int = 0;
	var total:Int = 0;
	var counted:Int = 0;

	public function new() {
		for (i in 0...16) {
			volumes[i] = i == 15 ? 0 : Math.round(LOUDEST * Math.pow(10, -0.1 * i));
		}

		reset();
	}

	/**
		Back to power on: every channel silent, the shift register reloaded.
	**/
	public function reset():Void {
		for (i in 0...4) {
			tone[i] = 0;
			attenuation[i] = 15;
			counter[i] = 0;
			output[i] = 1;
		}

		latched = 0;
		noise = 0;
		shift = 0x8000;
		spare = 0;
		total = 0;
		counted = 0;
		writes = 0;
	}

	/**
		One bus write.

		@param value The byte. With the top bit set it latches a register and carries the low four
			bits of it; without, it carries the upper six bits of whatever was latched last, which is
			how a ten bit period arrives in two writes.
	**/
	public function write(value:Int):Void {
		final byte = value & 0xFF;
		writes++;

		if ((byte & 0x80) != 0) {
			latched = (byte >> 4) & 0x07;
			final channel = latched >> 1;

			if ((latched & 1) != 0) attenuation[channel] = byte & 0x0F;
			else if (channel == 3) setNoise(byte & 0x0F);
			else tone[channel] = (tone[channel] & 0x3F0) | (byte & 0x0F);

			return;
		}

		final channel = latched >> 1;
		if ((latched & 1) != 0) attenuation[channel] = byte & 0x0F;
		else if (channel == 3) setNoise(byte & 0x0F);
		else tone[channel] = (tone[channel] & 0x000F) | ((byte & 0x3F) << 4);
	}

	/**
		Takes the noise control nibble and reloads the shift register with it.

		@param value The nibble written.
	**/
	function setNoise(value:Int):Void {
		noise = value & 0x07;
		shift = 0x8000;
	}

	/**
		Runs the part forward, keeping any remainder for the next call.

		@param clocks How many master clocks to run.
	**/
	public function run(clocks:Int):Void {
		spare += clocks;

		while (spare >= DIVIDER) {
			spare -= DIVIDER;
			step();
		}
	}

	/**
		One internal step: each square counter down by one and flipped where it expires,
		then the noise channel, then the sum gathered for `taken`.
	**/
	function step():Void {
		for (channel in 0...3) {
			if (--counter[channel] > 0) continue;

			counter[channel] = tone[channel] < 1 ? 1 : tone[channel];
			if (tone[channel] >= 1) output[channel] = output[channel] > 0 ? 0 : 1;
			else output[channel] = 1;
		}

		if (--counter[3] > 0) {
			gather();
			return;
		}

		counter[3] = switch (noise & 0x03) {
			case 0: 0x10;
			case 1: 0x20;
			case 2: 0x40;
			case _: tone[2] < 1 ? 1 : tone[2];
		}

		final feedback = (noise & 0x04) != 0 ? WHITE : PERIODIC;
		final parity = countBits(shift & feedback) & 1;
		shift = ((shift >> 1) | (parity << 15)) & 0xFFFF;
		output[3] = shift & 1;
		gather();
	}

	/**
		Adds the current level to the running mean `taken` will answer with.
	**/
	inline function gather():Void {
		total += level();
		counted++;
	}

	/**
		Reads the accumulated mean and resets it.

		@return The mean level across every step since the last call, which is what an output
			running slower than the part needs.
	**/
	public function taken():Int {
		if (counted == 0) return level();

		final answer = Std.int(total / counted);
		total = 0;
		counted = 0;
		return answer;
	}

	/**
		One channel on its own, for the scope and the meters.

		@param channel Which channel, 0 to 3.
		@return Its amplitude, or nought where it is low, or where the index is out of range.
	**/
	public inline function voice(channel:Int):Int {
		if (channel < 0 || channel > 3) return 0;
		return output[channel] > 0 ? volumes[attenuation[channel]] : 0;
	}

	/**
		One step and the level after it, for a caller running the part at its own rate.

		@return The level after that step.
	**/
	public inline function sample():Int {
		step();
		return level();
	}

	/**
		@return The four channels summed as they stand, with no averaging.
	**/
	public function level():Int {
		var sum = 0;
		for (channel in 0...4) if (output[channel] > 0) sum += volumes[attenuation[channel]];
		return sum;
	}

	/**
		@param value The masked shift register.
		@return How many bits are set, which is the parity fed back into it.
	**/
	static inline function countBits(value:Int):Int {
		var left = value;
		var count = 0;
		while (left != 0) {
			count += left & 1;
			left >>= 1;
		}
		return count;
	}
}
