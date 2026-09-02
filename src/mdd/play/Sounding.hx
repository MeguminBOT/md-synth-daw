package mdd.play;

import haxe.ds.Vector;
import mdd.song.Part;

@:unreflective
final class Sounding {
	public final notes:Vector<Int> = new Vector<Int>(Part.COUNT);
	public final keyed:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	final blocks:Vector<Int> = new Vector<Int>(3);
	final coarse:Vector<Int> = new Vector<Int>(3);
	final halves:Vector<Int> = new Vector<Int>(2);
	final periods:Vector<Int> = new Vector<Int>(4);
	final latched:Vector<Int> = new Vector<Int>(4);

	var waiting:Int = 0;
	var pending:Int = -1;

	public function new() {
		forget();
	}

	public function forget():Void {
		for (index in 0...Part.COUNT) {
			notes[index] = -1;
			keyed[index] = false;
		}

		for (index in 0...3) {
			blocks[index] = 0;
			coarse[index] = 0;
		}

		for (index in 0...2) halves[index] = -1;

		for (index in 0...4) {
			periods[index] = 0;
			latched[index] = 0;
		}

		waiting = 0;
		pending = -1;
	}

	public function take(stream:Stream, from:Int):Int {
		final many = stream.count;
		if (from > many) return read(stream, 0, many);

		return read(stream, from, many);
	}

	function read(stream:Stream, from:Int, to:Int):Int {
		for (index in from...to) {
			if (stream.kindAt(index) == Stream.YM) ym(stream.portAt(index), stream.valueAt(index));
			else psg(stream.valueAt(index));
		}

		return to;
	}

	public inline function write(kind:Int, port:Int, value:Int):Void {
		if (kind == Stream.YM) ym(port, value);
		else psg(value);
	}

	function ym(port:Int, value:Int):Void {
		final half = port >> 1;
		if (half > 1) return;

		if ((port & 1) == 0) {
			halves[half] = value;
			return;
		}

		final at = halves[half];
		if (at < 0) return;

		halves[half] = -1;

		if (at == 0x28 && half == 0) {
			keys(value);
			return;
		}

		final channel = at & 3;
		if (channel > 2) return;

		final slot = half * 3 + channel;
		if (slot > 5) return;

		if (at >= 0xA4 && at <= 0xA6) {
			blocks[channel] = (value >> 3) & 7;
			coarse[channel] = (value & 7) << 8;
			return;
		}

		if (at < 0xA0 || at > 0xA2) return;

		final frequency = coarse[channel] | value;
		notes[slot] = noteOf(blocks[channel], frequency);
	}

	function keys(value:Int):Void {
		final channel = value & 3;
		if (channel > 2) return;

		final slot = ((value & 4) != 0 ? 3 : 0) + channel;
		if (slot > 5) return;

		keyed[slot] = (value & 0xF0) != 0;
	}

	function psg(value:Int):Void {
		if ((value & 0x80) != 0) {
			final channel = (value >> 5) & 3;

			if ((value & 0x10) != 0) {
				final quiet = (value & 0x0F) == 0x0F;
				final slot = 6 + channel;

				if (slot < Part.COUNT) {
					keyed[slot] = !quiet;
					if (quiet) notes[slot] = -1;
				}

				waiting = 0;
				pending = -1;
				return;
			}

			latched[channel] = value & 0x0F;
			pending = channel;
			waiting = 1;
			return;
		}

		if (waiting == 0 || pending < 0 || pending > 2) return;

		periods[pending] = latched[pending] | ((value & 0x3F) << 4);
		notes[6 + pending] = periodNote(periods[pending]);

		waiting = 0;
		pending = -1;
	}

	static function noteOf(block:Int, frequency:Int):Int {
		var best = 0;
		var away = 0x7FFFFFFF;

		for (index in 0...12) {
			final held = Stream.FM_NOTES[index] - frequency;
			final much = held < 0 ? -held : held;

			if (much >= away) continue;

			away = much;
			best = index;
		}

		final note = (block + 1) * 12 + best;
		return note < 0 ? 0 : (note > 127 ? 127 : note);
	}

	static function periodNote(period:Int):Int {
		if (period < 1) return -1;

		var best = -1;
		var away = 0x7FFFFFFF;

		for (note in 0...128) {
			final held = Stream.PSG_PERIODS[note] - period;
			final much = held < 0 ? -held : held;

			if (much >= away) continue;

			away = much;
			best = note;
		}

		return best;
	}
}
