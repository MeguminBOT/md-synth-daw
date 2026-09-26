package mdd.song;

/**
	The tempo map: where the tempo changes and what it becomes, and the arithmetic that
	turns a tick into a sample and back.

	A tick is a musical position and a sample is a real one, and everything that has to
	agree with the audio goes through here rather than multiplying by a single tempo.
**/
@:unreflective
final class Tempo {
	/**
		The rate positions are measured in, in hertz.
	**/
	public static inline final TICKS = 44100;

	/**
		How many samples one frame lasts on an NTSC console, a sixtieth of a second.
	**/
	public static inline final FRAME = 735;

	/**
		Ticks per quarter note.
	**/
	public var ppqn(default, null):Int;

	/**
		Frames a second the machine runs at, 60 on NTSC and 50 on PAL. The music is written for 60,
		and at 50 it plays the way a driver counting frames plays it on a PAL console: every tick
		takes six fifths as long, which changing this works out again.
	**/
	public var rate(default, set):Int;

	/**
		How much longer a tick takes than the tempo says, which is one at 60 frames a second and
		six fifths at 50.
	**/
	public var stretch(get, never):Float;

	/**
		The tick each tempo change happens on.
	**/
	public final at:Array<Int> = [];

	/**
		The tempo each change moves to.
	**/
	public final bpm:Array<Float> = [];

	final base:Array<Float> = [];
	final perTick:Array<Float> = [];

	/**
		Builds a map with one tempo from the start.

		@param ppqn Ticks per quarter note.
		@param first The tempo at tick nought.
		@param rate Frames a second the machine runs at.
	**/
	public function new(ppqn:Int = 96, first:Float = 120, rate:Int = 60) {
		this.ppqn = ppqn < 1 ? 96 : ppqn;

		at.push(0);
		bpm.push(first <= 0 ? 120 : first);

		this.rate = rate;
	}

	function set_rate(want:Int):Int {
		rate = want;
		settle();

		return rate;
	}

	inline function get_stretch():Float {
		return rate == 50 ? 1.2 : 1.0;
	}

	/**
		@return How many samples one frame of the console lasts: `FRAME` at 60 frames a second,
			and a fiftieth of a second at 50.
	**/
	public inline function frame():Int {
		return Std.int(TICKS / (rate < 1 ? 60 : rate));
	}

	/**
		Adds or replaces a tempo change.

		@param tick Where the change happens.
		@param beats The tempo it moves to.
	**/
	public function set(tick:Int, beats:Float):Void {
		final want = beats <= 0 ? 1 : beats;

		if (tick <= 0) {
			bpm[0] = want;
			settle();
			return;
		}

		for (i in 0...at.length) {
			if (at[i] != tick) continue;
			bpm[i] = want;
			settle();
			return;
		}

		var index = at.length;
		while (index > 0 && at[index - 1] > tick) index--;

		at.insert(index, tick);
		bpm.insert(index, want);
		settle();
	}

	/**
		Removes a tempo change. The one at tick nought cannot be removed.

		@param tick Where the change is.
		@return False where there was no change there.
	**/
	public function drop(tick:Int):Bool {
		if (tick <= 0) return false;

		for (i in 0...at.length) {
			if (at[i] != tick) continue;
			at.splice(i, 1);
			bpm.splice(i, 1);
			settle();
			return true;
		}

		return false;
	}

	/**
		Changes the tick resolution, moving every change to keep the music where it was.

		@param ppqn The new ticks per quarter note.
	**/
	public function resolve(ppqn:Int):Void {
		this.ppqn = ppqn < 1 ? 96 : ppqn;
		settle();
	}

	/**
		Works out the running sample position of every change again, which everything else
		here reads. Called whenever a change moves.
	**/
	public function settle():Void {
		base.resize(0);
		perTick.resize(0);

		var running = 0.0;

		for (i in 0...at.length) {
			base.push(running);
			perTick.push(TICKS * 60.0 / (bpm[i] * ppqn) * stretch);

			if (i + 1 < at.length) running += (at[i + 1] - at[i]) * perTick[i];
		}
	}

	/**
		@param tick A tick.
		@return Which stretch of constant tempo it falls in.
	**/
	public function segment(tick:Int):Int {
		var low = 0;
		var high = at.length - 1;

		while (low < high) {
			final middle = (low + high + 1) >> 1;

			if (at[middle] <= tick) low = middle;
			else high = middle - 1;
		}

		return low;
	}

	/**
		@param samples A sample position.
		@return Which stretch of constant tempo it falls in.
	**/
	function segmentAt(samples:Float):Int {
		var low = 0;
		var high = base.length - 1;

		while (low < high) {
			final middle = (low + high + 1) >> 1;

			if (base[middle] <= samples) low = middle;
			else high = middle - 1;
		}

		return low;
	}

	/**
		@param tick A tick.
		@return The sample it falls on.
	**/
	public function samplesAt(tick:Int):Int {
		final which = segment(tick);
		return Math.round(base[which] + (tick - at[which]) * perTick[which]);
	}

	/**
		@param samples A sample position.
		@return The tick it falls on.
	**/
	public function tickAt(samples:Int):Int {
		final which = segmentAt(samples);
		return at[which] + Math.round((samples - base[which]) / perTick[which]);
	}

	/**
		@param samples A sample position.
		@return The tick it falls on, with how far it is towards the next one, which is what a lane
			read between ticks needs.
	**/
	public function ticksAt(samples:Float):Float {
		final which = segmentAt(samples);
		return at[which] + (samples - base[which]) / perTick[which];
	}

	/**
		@param tick A tick.
		@return The tempo in force there.
	**/
	public inline function beatsAt(tick:Int):Float {
		return bpm[segment(tick)];
	}

	/**
		@return A new map with the same changes.
	**/
	public function copy():Tempo {
		final out = new Tempo(ppqn, bpm[0], rate);

		for (i in 1...at.length) {
			out.at.push(at[i]);
			out.bpm.push(bpm[i]);
		}

		out.settle();
		return out;
	}
}
