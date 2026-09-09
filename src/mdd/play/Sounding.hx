package mdd.play;

import haxe.ds.Vector;
import mdd.song.Part;

/**
	What is keyed and what note each part is holding, worked out by reading a register
	stream rather than by asking the sequencer.

	The interface needs to show what is playing at a position the device has already
	reached, and the sequencer only knows what it asked for. Reading the stream back
	is what makes the meters and the channel rack agree with what is heard.
**/
@:unreflective
final class Sounding {
	/**
		The note each part is tuned to, as a MIDI note number, or -1 for none.
	**/
	public final notes:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Whether each part is sounding.
	**/
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

	/**
		Back to nothing keyed and no note anywhere, including the latches a two byte write
		is assembled through.
	**/
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

	/**
		Reads a span of a stream and folds it into the state here.

		@param stream The stream to read.
		@param from Where to start. Past the end starts again from the beginning, which is what a
			stream that was cleared needs.
		@return How far it read to, to pass back as `from` next time.
	**/
	public function take(stream:Stream, from:Int):Int {
		final many = stream.count;
		if (from > many) return read(stream, 0, many);

		return read(stream, from, many);
	}

	/**
		@param stream The stream to read.
		@param from The first write to take.
		@param to One past the last.
		@return The value of `to`.
	**/
	function read(stream:Stream, from:Int, to:Int):Int {
		for (index in from...to) {
			if (stream.kindAt(index) == Stream.YM) ym(stream.portAt(index), stream.valueAt(index));
			else psg(stream.valueAt(index));
		}

		return to;
	}

	/**
		Folds one write in, for a caller holding writes rather than a stream.

		@param kind Which part, `Stream.YM` or `Stream.PSG`.
		@param port The bus port.
		@param value The byte written.
	**/
	public inline function write(kind:Int, port:Int, value:Int):Void {
		if (kind == Stream.YM) ym(port, value);
		else psg(value);
	}

	/**
		Follows one FM write, latching an address until its value arrives.

		@param port The bus port.
		@param value The byte written.
	**/
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

	/**
		Follows a write to register `$28`, which is what keys a channel.

		@param value The byte written.
	**/
	function keys(value:Int):Void {
		final channel = value & 3;
		if (channel > 2) return;

		final slot = ((value & 4) != 0 ? 3 : 0) + channel;
		if (slot > 5) return;

		keyed[slot] = (value & 0xF0) != 0;
	}

	/**
		Follows one square part write, which may be half of a two byte period.

		@param value The byte written.
	**/
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

	/**
		Reads an FM frequency word back as the nearest note. It is the nearest and not
		the exact one: every driver carries its own table and rounds it its own way, so
		the word a game wrote is usually a unit or two from what this would produce.

		@param block The octave.
		@param frequency The eleven bit frequency word.
		@return The MIDI note number, clamped to 0 to 127.
	**/
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

	/**
		Reads a square period back as the nearest note.

		@param period The ten bit period.
		@return The MIDI note number, or -1 where the period is not a note at all.
	**/
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
