package mdd.play;

import haxe.ds.Vector;

/**
	The click the metronome and a count in make, added to what the device plays after the chips
	and the output stage. It is none of the parts and writes no register, so nothing an export
	renders can reach it: only `Render.deliver` adds it.

	A click is a short decaying tone, higher on the first beat of a bar. A click struck while the
	last one still rings takes over from it.

	`strikes` and `adds` run on the render thread and allocate nothing. The two tones are built
	once, when the metronome is made.
**/
@:unreflective
final class Metronome {
	/**
		How long a click rings, in seconds.
	**/
	static inline final LENGTH = 0.060;

	/**
		How quickly a click dies away: the time it takes to fall to about a third, in seconds.
	**/
	static inline final DECAY = 0.008;

	/**
		The pitch of the first beat of a bar, and of every other beat, in hertz.
	**/
	static inline final ACCENT_PITCH = 1760.0;
	static inline final BEAT_PITCH = 1320.0;

	/**
		How loud each starts, against full scale.
	**/
	static inline final ACCENT_LEVEL = 0.45;
	static inline final BEAT_LEVEL = 0.30;

	/**
		The most clicks one block can be asked for.
	**/
	public static inline final WAITING = 4;

	final accent:Vector<Float>;
	final beat:Vector<Float>;

	final waitAt:Vector<Int> = new Vector<Int>(WAITING);
	final waitAccent:Vector<Bool> = new Vector<Bool>(WAITING);
	var waiting:Int = 0;

	var ringing:Int = -1;
	var accented:Bool = false;

	/**
		Builds the two tones for an output rate.

		@param rate The output rate in hertz.
	**/
	public function new(rate:Int) {
		final count = Std.int((rate <= 0 ? 48000 : rate) * LENGTH);

		accent = tone(count, rate, ACCENT_PITCH, ACCENT_LEVEL);
		beat = tone(count, rate, BEAT_PITCH, BEAT_LEVEL);
	}

	static function tone(count:Int, rate:Int, pitch:Float, level:Float):Vector<Float> {
		final out = new Vector<Float>(count);

		for (index in 0...count) {
			final seconds = index / rate;
			out[index] = Math.sin(2 * Math.PI * pitch * seconds) * Math.exp(-seconds / DECAY) * level;
		}

		return out;
	}

	/**
		Asks for a click in the next block `adds` is given. Clicks are asked for in the order they
		fall, and past `WAITING` of them the rest are dropped.

		@param frame Where in the block it falls, in frames.
		@param first Whether it is the first beat of a bar.
	**/
	public inline function strikes(frame:Int, first:Bool):Void {
		if (waiting >= WAITING) return;

		waitAt[waiting] = frame;
		waitAccent[waiting] = first;
		waiting++;
	}

	/**
		Adds the clicks asked for, and whatever is still ringing from the last block, to a block.

		@param block Interleaved stereo, `count` frames of it.
		@param count How many frames it holds.
		@param gain What to scale the clicks by.
	**/
	public function adds(block:Vector<cpp.Float32>, count:Int, gain:Float):Void {
		if (waiting == 0 && ringing < 0) return;

		var next = 0;

		for (frame in 0...count) {
			while (next < waiting && waitAt[next] <= frame) {
				ringing = 0;
				accented = waitAccent[next];
				next++;
			}

			if (ringing < 0) continue;

			final table = accented ? accent : beat;
			final value = table[ringing] * gain;

			block[frame * 2] = clamped(block[frame * 2] + value);
			block[frame * 2 + 1] = clamped(block[frame * 2 + 1] + value);

			ringing++;
			if (ringing >= table.length) ringing = -1;
		}

		waiting = 0;
	}

	/**
		@return Whether a click is ringing or waiting.
	**/
	public inline function sounding():Bool {
		return waiting > 0 || ringing >= 0;
	}

	static inline function clamped(value:Float):cpp.Float32 {
		return value > 1 ? 1 : (value < -1 ? -1 : value);
	}
}
