package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Ym2612;
import mdd.song.Tempo;

@:unreflective
final class Driver {
	public static inline final BUSY_CYCLES = 32;
	public static inline final PER_SAMPLE = 24;
	public static inline final BACKLOG = 8192;

	public var on:Bool = false;

	public static inline final PER_FRAME = 141;

	public var perFrame:Int = PER_FRAME;
	public var rate:Int = 60;

	public var spilled(default, null):Int = 0;
	public var latest(default, null):Int = 0;
	public var lost(default, null):Int = 0;

	final heldTick:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldKind:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldPort:Vector<Int> = new Vector<Int>(BACKLOG);
	final heldValue:Vector<Int> = new Vector<Int>(BACKLOG);

	var held:Int = 0;

	public static inline final TALLY = 256;

	final counted:Vector<Int> = new Vector<Int>(TALLY);
	final countedAt:Vector<Int> = new Vector<Int>(TALLY);

	var ready:Int = 0;

	public function new() {
		for (index in 0...TALLY) countedAt[index] = -1;
	}

	public static function busy():Int {
		final samples = Ym2612.CLOCK / Ym2612.PER_SAMPLE;
		final gap = Math.ceil(Tempo.TICKS * BUSY_CYCLES / (PER_SAMPLE * samples));

		return gap < 1 ? 1 : gap;
	}

	public inline function frame():Int {
		return Std.int(Tempo.TICKS / (rate < 1 ? 60 : rate));
	}

	public function forget():Void {
		held = 0;
		ready = 0;

		for (index in 0...TALLY) countedAt[index] = -1;

		spilled = 0;
		latest = 0;
		lost = 0;
	}

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

	static inline function paired(kind:Int, port:Int):Bool {
		return kind == Stream.YM && (port & 1) == 0;
	}

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

	public inline function waiting():Int {
		return held;
	}
}
