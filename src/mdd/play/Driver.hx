package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Ym2612;
import mdd.song.Tempo;

/**
	Paces a register stream the way a real sound driver would, so an export is written
	the way hardware would have taken it rather than all at once.

	A driver writes on a frame timer, waits on the busy flag, and can only get so many
	writes out per frame. Everything it cannot fit is carried into the next one. What
	this produces is what a Mega Drive would actually have heard.
**/
@:unreflective
final class Driver {
	/**
		How many part cycles a write keeps the busy flag raised for.
	**/
	static inline final BUSY_CYCLES = 32;

	/**
		Part cycles per output sample.
	**/
	public static inline final PER_SAMPLE = 24;

	/**
		How many writes can be carried over before they start being lost.
	**/
	static inline final BACKLOG = 8192;

	/**
		Whether pacing happens at all. Off passes the stream through untouched.
	**/
	public var on:Bool = false;

	/**
		How many writes a frame has room for, at the default rate.
	**/
	public static inline final PER_FRAME = 178;

	/**
		How many writes a frame has room for here.
	**/
	public var perFrame:Int = PER_FRAME;

	/**
		Frames a second, which is 60 on NTSC and 50 on PAL.
	**/
	public var rate:Int = 60;

	/**
		How many writes were pushed into a later frame for want of room.
	**/
	public var spilled(default, null):Int = 0;

	/**
		The furthest any write was pushed, in samples. This is the worst a piece is behind
		where it was written.
	**/
	public var latest(default, null):Int = 0;

	/**
		How many writes were thrown away because the backlog was full.
	**/
	public var lost(default, null):Int = 0;

	final heldTick:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldKind:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldPort:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldValue:Vector<Int> = new Vector<Int>(BACKLOG);

	var held:Int = 0;

	/**
		How many registers the per frame counters cover.
	**/
	static inline final TALLY = 256;

	final counted:Vector<Int> = new Vector<Int>(TALLY);
	final countedAt:Vector<Int> = new Vector<Int>(TALLY);

	var ready:Int = 0;

	public function new() {
		for (index in 0...TALLY) countedAt[index] = -1;
	}

	/**
		@return How many output samples the busy flag stays raised for after a write.
	**/
	public static function busy():Int {
		final samples = Ym2612.CLOCK / Ym2612.PER_SAMPLE;
		final gap = Math.ceil(Tempo.TICKS * BUSY_CYCLES / (PER_SAMPLE * samples));

		return gap < 1 ? 1 : gap;
	}

	/**
		@return How many output samples one driver frame lasts.
	**/
	public inline function frame():Int {
		return Std.int(Tempo.TICKS / (rate < 1 ? 60 : rate));
	}

	/**
		Empties the backlog and forgets every count, which a seek has to do.
	**/
	public function forget():Void {
		held = 0;
		ready = 0;

		for (index in 0...TALLY) countedAt[index] = -1;

		spilled = 0;
		latest = 0;
		lost = 0;
	}

	/**
		Reads one stream and writes a paced copy of it into another.

		@param from The stream as the sequencer produced it.
		@param into Where the paced copy goes. Cleared first.
		@param until The last tick to pace up to.
	**/
	public function paces(from:Stream, into:Stream, until:Int):Void {
		final gap = busy();
		final span = frame();
		final carried = held;

		held = 0;

		stalling = false;

		var back = 0;
		var index = 0;

		while (back < carried || index < from.count) {
			final takesBack = index >= from.count
				|| (back < carried && heldTick[back] <= from.tickAt(index));

			if (takesBack) {
				final pairs = paired(heldKind[back], heldPort[back]) && back + 1 < carried;

				back += took(into, heldTick[back], heldKind[back], heldPort[back],
					heldValue[back], pairs ? heldPort[back + 1] : -1,
					pairs ? heldValue[back + 1] : 0, until, gap, span, true);

				continue;
			}

			final pairs = paired(from.kindAt(index), from.portAt(index))
				&& index + 1 < from.count;

			index += took(into, from.tickAt(index), from.kindAt(index), from.portAt(index),
				from.valueAt(index), pairs ? from.portAt(index + 1) : -1,
				pairs ? from.valueAt(index + 1) : 0, until, gap, span, false);
		}
	}

	var stalling:Bool = false;

	/**
		@param kind Which part.
		@param port The bus port.
		@return True where the write is an address that must stay with the value after it, so the
			pair is never split across a frame.
	**/
	static inline function paired(kind:Int, port:Int):Bool {
		return kind == Stream.YM && (port & 1) == 0;
	}

	/**
		Places one write at the earliest tick a driver could actually have made it,
		given the busy flag and how full the frame already is.

		@param into Where the paced write goes.
		@param tick When it was wanted.
		@param kind Which part.
		@param port The bus port.
		@param value The byte.
		@param second The port of a paired write that must follow it, or -1 for none.
		@param held The value of that paired write.
		@param until The last tick anything may be placed at.
		@param gap How many samples the busy flag holds a write off for.
		@param span How many samples one driver frame lasts.
		@param already Whether this write came out of the backlog rather than the stream.
		@return How many writes were consumed, one or two.
	**/
	function took(into:Stream, tick:Int, kind:Int, port:Int, value:Int, second:Int,
			held:Int, until:Int, gap:Int, span:Int, already:Bool):Int {
		final many = second < 0 ? 1 : 2;

		if (stalling) {
			keeps(tick, kind, port, value);
			if (many > 1) keeps(tick, kind, second, held);

			return many;
		}

		if (kind == Stream.YM && port < 2 && value == 0x2A) {
			into.raw(tick, kind, port, value);
			if (many > 1) into.raw(tick, kind, second, held);

			return many;
		}

		var at = tick > ready ? tick : ready;
		var frame = Std.int(at / span);
		var looked = 0;

		while (frame > 0 && tally(frame) >= perFrame && looked < TALLY) {
			frame++;
			at = frame * span;
			looked++;
		}

		if (looked > 0 && !already) {
			spilled++;
			if (at - tick > latest) latest = at - tick;
		}

		if (at >= until) {
			stalling = true;

			keeps(at, kind, port, value);
			if (many > 1) keeps(at, kind, second, held);

			return many;
		}

		into.raw(at, kind, port, value);
		if (many > 1) into.raw(at, kind, second, held);

		tallies(frame);
		ready = at + (kind == Stream.YM ? gap : 0);

		return many;
	}

	inline function tally(frame:Int):Int {
		final slot = frame % TALLY;

		if (countedAt[slot] != frame) {
			countedAt[slot] = frame;
			counted[slot] = 0;
		}

		return counted[slot];
	}

	inline function tallies(frame:Int):Void {
		final slot = frame % TALLY;

		if (countedAt[slot] != frame) {
			countedAt[slot] = frame;
			counted[slot] = 0;
		}

		counted[slot]++;
	}

	/**
		Carries a write that would not fit into the backlog, or counts it lost.

		@param tick When it was wanted.
		@param kind Which part.
		@param port The bus port.
		@param value The byte.
	**/
	function keeps(tick:Int, kind:Int, port:Int, value:Int):Void {
		if (held >= BACKLOG) {
			lost++;
			return;
		}

		heldTick[held] = tick;
		heldKind[held] = kind;
		heldPort[held] = port;
		heldValue[held] = value;

		held++;
	}

	/**
		@return How many writes are still carried over.
	**/
	public inline function waiting():Int {
		return held;
	}
}
