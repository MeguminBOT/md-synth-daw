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
	The YM2612: six FM channels of four operators each, with the sixth able to give way
	to an eight bit sample channel.

	This is a part, not a component of a program. It is written to and it is asked for
	samples, and it imports nothing above `mdd.chip`. Everything it does was taken from
	the part documentation and then measured against a known-good YM2612 sample for
	sample, rather than read out of somebody else's emulator.

	Two instances have to be able to coexist, because the live render and the offline
	one are both running, so nothing here is static except an immutable table.
**/
@:unreflective
final class Ym2612 {
	/**
		The master clock a Mega Drive gives the part, in hertz.
	**/
	public static inline final CLOCK = 7670453;

	/**
		Master clocks per output sample, which is what makes the part run at 53267 Hz.
	**/
	public static inline final PER_SAMPLE = 144;

	/**
		Operator slots per output sample: six channels of four, visited in a fixed order.
	**/
	static inline final PER_FRAME = 24;

	/**
		The mode value for channel three's CSM mode, where timer A keys the channel.
	**/
	static inline final CSM = 2;

	/**
		How many slots the busy flag stays raised after a write.
	**/
	static inline final BUSY = 32;

	/**
		How many slots pass before a written value reaches its register. A driver that
		reads the busy flag depends on this, and so does anything compared with hardware.
	**/
	static inline final WRITE_LATENCY = 2;

	/**
		Which operator each of channel three's three extra frequency registers belongs to.
	**/
	static final APART:Vector<Int> = Vector.fromArrayCopy([2, 0, 1]);

	/**
		The channel visited at each of the twenty four slots.
	**/
	static final SPEAKS:Vector<Int> = Vector.fromArrayCopy([
		0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5,
		0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5
	]);

	/**
		Which pass through the channel each slot is, 0 to 3.
	**/
	static final TURNS:Vector<Int> = Vector.fromArrayCopy([
		0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1,
		2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3
	]);

	/**
		Which operator each slot runs. The part does not visit them in numeric order.
	**/
	static final PLAYS:Vector<Int> = Vector.fromArrayCopy([
		0, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 2,
		1, 1, 1, 1, 1, 1, 3, 3, 3, 3, 3, 3
	]);

	/**
		One mask per LFO rate, deciding how often the LFO phase moves on.
	**/
	static final SWEEP:Vector<Int> = Vector.fromArrayCopy([108, 77, 71, 67, 62, 44, 8, 5]);

	/**
		The four amplitude sensitivities as shifts, so 7 is no swing at all.
	**/
	static final TREMOLO:Vector<Int> = Vector.fromArrayCopy([7, 3, 1, 0]);

	/**
		Which channel finishes its sample at each slot, or -1 where none does.
	**/
	static final TAKEN:Vector<Int> = Vector.fromArrayCopy([
		1, -1, -1, -1, 5, -1, -1, -1, 3, -1, -1, -1,
		0, -1, -1, -1, 4, -1, -1, -1, 2, -1, -1, -1
	]);

	/**
		Every register the part holds, both halves, exactly as written. This is what the
		register timeline and the hardware monitor read.
	**/
	public final registers:Vector<Int> = new Vector<Int>(512);

	/**
		The six channels.
	**/
	public final channels:Vector<Channel> = new Vector<Channel>(6);

	/**
		How many writes the part has taken since it was made. Checks compare this against
		what a file contains.
	**/
	public var writes(default, null):Int = 0;

	/**
		The last sample on the left, before any output stage.
	**/
	public var left(default, null):Int = 0;

	/**
		The same on the right.
	**/
	public var right(default, null):Int = 0;

	/**
		The byte the sample channel is holding, unsigned.
	**/
	public var dac(default, null):Int = 0;

	/**
		Whether the sample channel has taken channel six.
	**/
	public var dacOn(default, null):Bool = false;

	/**
		Which converter is modelled. The discrete YM2612 drives a channel's value for all
		four cycles it holds, offset by a step whose sign follows the value, so a signal
		crossing zero jumps the gap between the two steps. That is the ladder effect.
		Clearing this gives the YM3438 instead, which rests at zero for a fourth cycle and
		has no gap. The default is the discrete part, since that is what a Model 1 carries.
	**/
	public var discrete:Bool = true;

	var address:Int = 0;
	var part:Int = 0;

	var timerA:Int = 0;
	var timerB:Int = 0;
	var timerACount:Int = 0;
	var timerBCount:Int = 0;
	var status:Int = 0;

	var envelopeCounter:Int = 0;
	var envelopeDivider:Int = 0;
	var visible:Int = 0;
	var ticking:Bool = false;
	var position:Int = 0;
	var pendingHalf:Int = 0;
	var pendingAddress:Int = 0;
	var pendingValue:Int = 0;
	var pendingIn:Int = 0;
	var waiting:Bool = false;
	var lfoPhase(default, null):Int = 0;

	/**
		The LFO's amplitude ramp for this sample, which every tremolo reads.
	**/
	public var swell(default, null):Int = 126;

	var lfoOn:Bool = false;
	var lfoRate:Int = 0;
	var lfoHeld:Int = 0;
	var vibrato:Int = 0;
	var mode:Int = 0;
	var csmKeyed:Bool = false;
	var busyFor:Int = 0;

	/**
		The high byte each channel is holding until its low byte arrives, one per channel
		rather than one for the part. `$A4` to `$A6` are real registers on each half, so a
		driver may write all six high bytes and then all six low bytes, and one latch
		between them would give every channel the last high byte written.
	**/
	final frequencyLatch:Vector<Int> = new Vector<Int>(6);

	/**
		The same for channel three separate operator frequencies, which have three latches
		of their own at `$AC` to `$AE`.
	**/
	final operatorLatch:Vector<Int> = new Vector<Int>(3);

	public function new() {
		for (i in 0...6) channels[i] = new Channel();
		reset();
	}

	/**
		Back to power on: every register cleared, every channel reset, timers stopped.
	**/
	public function reset():Void {
		for (i in 0...registers.length) registers[i] = 0;
		for (channel in channels) channel.reset();

		address = 0;
		part = 0;
		timerA = 0;
		timerB = 0;
		timerACount = 0;
		timerBCount = 0;
		status = 0;
		writes = 0;
		left = 0;
		right = 0;
		dac = 0;
		dacOn = false;
		envelopeCounter = 0;
		envelopeDivider = 0;
		visible = 0;
		ticking = false;
		position = 0;
		pendingHalf = 0;
		pendingAddress = 0;
		pendingValue = 0;
		pendingIn = 0;
		waiting = false;
		lfoOn = false;
		lfoRate = 0;
		lfoPhase = 0;
		lfoHeld = 0;
		vibrato = 0;
		mode = 0;
		csmKeyed = false;
		busyFor = 0;
		for (index in 0...6) frequencyLatch[index] = 0;
		for (index in 0...3) operatorLatch[index] = 0;
		swell = 126;
	}

	/**
		One bus write. An even port sets the address and picks the half; an odd port is
		the value, which is latched and reaches its register a couple of slots later, at
		a slot the register actually belongs to. A second write before the first has
		landed commits the first, exactly as the part does.

		@param port The bus port, 0 to 3. Bit 0 picks address or value and bit 1 picks the half of
			the register file.
		@param value The byte written.
	**/
	public function write(port:Int, value:Int):Void {
		writes++;

		final byte = value & 0xFF;
		if ((port & 1) == 0) {
			part = (port >> 1) & 1;
			address = byte;
			return;
		}

		busyFor = BUSY;

		if (pendingIn > 0 || waiting) commit();

		pendingHalf = part;
		pendingAddress = address;
		pendingValue = byte;
		pendingIn = WRITE_LATENCY;
		waiting = false;
	}

	/**
		Puts the latched write into its register and acts on it.
	**/
	function commit():Void {
		pendingIn = 0;
		waiting = false;
		registers[(pendingHalf << 8) | pendingAddress] = pendingValue;
		apply(pendingHalf, pendingAddress, pendingValue);
	}

	/**
		@param at The slot the part is on, 0 to 23.
		@return True where the pending write can be taken now. Registers below `$30` land anywhere;
			the rest wait for a slot belonging to their own channel.
	**/
	inline function lands(at:Int):Bool {
		final address = pendingAddress;
		if (address < 0x30) return true;

		final channel = pendingHalf * 3 + (address & 3);
		if ((address & 3) == 3) return true;

		return address < 0xA0
			? at % 12 == ((address >> 2) & 1) * 6 + channel
			: at % 6 == channel;
	}

	/**
		@return The status byte: the two timer overflow flags, and the busy bit while a write is
			still being taken.
	**/
	public function read():Int {
		return status | (busyFor > 0 ? 0x80 : 0);
	}

	/**
		Decodes one register write into whatever it changes: the LFO, the timers, the key
		on nibble, the sample channel, or one operator or channel field.

		@param half Which half of the register file, 0 or 1.
		@param at The register address within that half.
		@param value The byte written.
	**/
	function apply(half:Int, at:Int, value:Int):Void {
		if (half == 0) {
			switch (at) {
				case 0x22:
					lfoOn = (value & 0x08) != 0;
					lfoRate = value & 7;
				case 0x24: timerA = (timerA & 0x03) | (value << 2);
				case 0x25: timerA = (timerA & 0x3FC) | (value & 0x03);
				case 0x26: timerB = value;
				case 0x27: timers(value);
				case 0x28: key(value);
				case 0x2A: dac = value;
				case 0x2B: dacOn = (value & 0x80) != 0;
				case _:
			}
			if (at < 0x30) return;
		}

		if (at >= 0xA8 && at <= 0xAF) {
			if (half != 0 || (at & 3) == 3) return;

			if (at >= 0xAC) {
				operatorLatch[at & 3] = value;
				return;
			}

			final held = operatorLatch[at & 3];
			final which = APART[at & 3];
			final third = channels[2];

			third.setSeparate(which, (held >> 3) & 7, ((held & 7) << 8) | value);
			return;
		}

		if (at >= 0xA4 && at <= 0xA7) {
			if ((at & 3) != 3) frequencyLatch[half * 3 + (at & 3)] = value;
			return;
		}

		final index = at & 0x03;
		if (index == 3) return;

		final channel = channels[half * 3 + index];

		if (at >= 0x30 && at < 0xA0) {
			final which = operatorOf(at);
			channel.operators[which].set(at & 0xF0, value);
			return;
		}

		switch (at & 0xFC) {
			case 0xA0: {
				final held = frequencyLatch[half * 3 + index];
				channel.setFrequency((held >> 3) & 7, ((held & 7) << 8) | value);
			}
			case 0xB0:
				channel.algorithm = value & 7;
				channel.feedback = (value >> 3) & 7;
			case 0xB4:
				channel.left = (value & 0x80) != 0;
				channel.right = (value & 0x40) != 0;
				channel.tremoloDepth = TREMOLO[(value >> 4) & 3];
				channel.vibratoDepth = value & 7;
				channel.tune(vibrato);
			case _:
		}
	}

	/**
		@param at A register address in the `$30` to `$9F` range.
		@return Which operator it belongs to. The part lays them out 1, 3, 2, 4 rather than in
			order, and the documentation has this the wrong way round.
	**/
	static inline function operatorOf(at:Int):Int {
		return switch ((at >> 2) & 3) {
			case 0: 0;
			case 1: 2;
			case 2: 1;
			case _: 3;
		}
	}

	/**
		Register `$27`: channel three's mode, and starting, stopping and clearing the two
		timers.

		@param value The byte written.
	**/
	function timers(value:Int):Void {
		mode = (value >> 6) & 3;

		final apart = mode != 0;
		if (apart != channels[2].separate) {
			channels[2].separate = apart;
			channels[2].tune(vibrato);
		}

		channels[2].levelled = mode != CSM;

		if ((value & 0x10) != 0) status &= ~0x01;
		if ((value & 0x20) != 0) status &= ~0x02;

		if ((value & 0x01) != 0 && timerACount == 0) timerACount = 1024 - timerA;
		if ((value & 0x02) != 0 && timerBCount == 0) timerBCount = (256 - timerB) * 16;
	}

	/**
		Register `$28`: which operators of one channel are keyed. It is latched rather
		than applied, and reaches the channel on the next slot.

		@param value The byte written: the channel in the low three bits and the operator mask in
			the high nibble.
	**/
	function key(value:Int):Void {
		final which = value & 0x07;
		if ((which & 3) == 3) return;

		channels[(which & 3) + ((which & 4) != 0 ? 3 : 0)].armed = (value >> 4) & 0x0F;
	}

	/**
		Counts both timers down by one sample and raises their flags. Timer A also keys
		channel three while CSM mode is on.
	**/
	function countTimers():Void {
		csmKeyed = false;

		if (timerACount > 0) {
			if (--timerACount <= 0) {
				if ((registers[0x27] & 0x04) != 0) status |= 0x01;
				timerACount += 1024 - timerA;
				csmKeyed = mode == CSM;
			}
		}

		if (timerBCount > 0) {
			if (--timerBCount <= 0) {
				if ((registers[0x27] & 0x08) != 0) status |= 0x02;
				timerBCount += (256 - timerB) * 16;
			}
		}
	}

	/**
		One operator slot: land any pending write, run the operator, publish a channel that
		has finished, and move the envelope counter on every twenty fourth slot.
	**/
	function cycle():Void {
		if (busyFor > 0) busyFor--;
		if (pendingIn > 0 && --pendingIn == 0) waiting = true;
		if (waiting && lands(position)) commit();

		final which = SPEAKS[position];
		channels[which].slot(TURNS[position], PLAYS[position], visible, ticking, swell,
			csmKeyed && which == 2);

		final taken = TAKEN[position];
		if (taken >= 0) channels[taken].capture();

		if (position < 6) channels[which].keyRequest = channels[which].armed;

		if (++position < PER_FRAME) return;

		position = 0;

		ticking = visible != envelopeCounter;
		visible = envelopeCounter;

		if (++envelopeDivider >= 3) {
			envelopeDivider = 0;
			envelopeCounter = (envelopeCounter + 1) & 0xFFF;
		}
	}

	/**
		Moves the LFO on by one sample, which drives both the tremolo ramp and the vibrato
		step every channel is retuned from.
	**/
	function oscillate():Void {
		final ramp = (lfoPhase << 1) & 0x7E;
		swell = (lfoPhase & 0x40) != 0 ? ramp : ramp ^ 0x7E;

		final step = lfoPhase >> 2;
		if (step != vibrato) {
			vibrato = step;
			for (channel in channels) if (channel.vibratoDepth != 0) channel.tune(step);
		}

		final mask = SWEEP[lfoRate];
		if ((lfoHeld & mask) == mask) {
			lfoHeld = 0;
			if (lfoOn) lfoPhase = (lfoPhase + 1) & 0x7F;
		}

		lfoHeld++;
		if (!lfoOn) lfoPhase = 0;
	}

	/**
		One output sample: the LFO, the timers, twenty four slots, then the six channels
		summed through the converter. Leaves `left` and `right` behind.

		@return The two sides summed.
	**/
	public function sample():Int {
		oscillate();
		countTimers();
		for (_ in 0...PER_FRAME) cycle();

		left = 0;
		right = 0;

		for (i in 0...6) {
			final channel = channels[i];

			final value = i == 5 && dacOn ? (dac - 0x80) << 1 : channel.delivered;

			if (!discrete) {
				if (channel.left) left += value;
				if (channel.right) right += value;
				continue;
			}

			final step = value >= 0 ? 1 : -1;
			final driven = (value >= 0 ? value + 1 : value) + 3 * step;

			left += channel.left ? driven : 4 * step;
			right += channel.right ? driven : 4 * step;
		}

		return left + right;
	}
}
