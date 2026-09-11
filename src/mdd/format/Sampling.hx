package mdd.format;

import haxe.ds.Vector;
import mdd.song.Sample;

@:unreflective

/**
	How a recording becomes a sample the converter can play, and the settings that
	decide it.

	Each stage is a decision somebody would otherwise have to make by hand, and the
	order they run in matters: the offset comes out before anything measures a level,
	the trim leaves a lead in because a window at the very edge of a run rejects far
	less than one in the middle, and the loudness is set in floating point before the
	bytes are made rather than by scaling bytes afterwards, which only throws away
	what the first pass rounded off.

	This is an offline path. It allocates.
**/
final class Sampling {
	/**
		The rate to bring it to, in hertz.
	**/
	public var rate:Int = 11025;

	/**
		Whether to cut the silence before the hit and the tail past hearing.
	**/
	public var trim:Bool = true;

	/**
		How far below the loudest the tail has to fall before it is cut, in decibels.
	**/
	public var tail:Float = -42;

	/**
		How much silence to leave in front of the hit, in seconds, so the window has
		something to work with where the recording starts.
	**/
	public var lead:Float = 0.004;

	/**
		The longest it may be, in seconds, or nought for as long as it is.
	**/
	public var cap:Float = 0;

	/**
		How long the fade at a cut end is, in seconds.
	**/
	public var fade:Float = 0.006;

	/**
		Whether to bring the loudest point up to full.
	**/
	public var loud:Bool = true;

	/**
		Whether to take the offset out, which costs range in eight bits where it is
		left in.
	**/
	public var centre:Bool = true;

	/**
		Builds the settings a drum kit wants.
	**/
	public function new() {}

	/**
		@return A copy, so a kit can hold one of these per hit without sharing.
	**/
	public function copy():Sampling {
		final out = new Sampling();

		out.rate = rate;
		out.trim = trim;
		out.tail = tail;
		out.lead = lead;
		out.cap = cap;
		out.fade = fade;
		out.loud = loud;
		out.centre = centre;

		return out;
	}

	/**
		How long a run of audio is once these settings have been applied, without
		building it.

		@param held The audio, at plus or minus one.
		@param was The rate it is at.
		@return How many bytes it would come to.
	**/
	public function counts(held:Vector<Float>, was:Int):Int {
		return takes(held, was, "").length();
	}

	/**
		Turns a run of audio into a sample.

		@param held The audio, at plus or minus one. It is not written to.
		@param was The rate it is at, in hertz.
		@param name What to call the sample.
		@return The sample, at `rate`, as unsigned bytes centred on 128.
	**/
	public function takes(held:Vector<Float>, was:Int, name:String):Sample {
		final made = new Sample(name, rate);
		if (held.length == 0 || was < 1 || rate < 1) return made;

		var run = centre ? centred(held) : held;
		if (trim) run = cut(run, was);

		run = Resampler.into(run, was, rate);
		run = capped(run, rate);
		run = faded(run, rate);

		made.hold(bytes(run));
		return made;
	}

	/**
		@param held The audio.
		@return It with its own average taken off, so it sits on nought.
	**/
	static function centred(held:Vector<Float>):Vector<Float> {
		var sum = 0.0;
		for (index in 0...held.length) sum += held[index];

		final middle = sum / held.length;
		if (middle == 0) return held;

		final out = new Vector<Float>(held.length);
		for (index in 0...held.length) out[index] = held[index] - middle;

		return out;
	}

	/**
		Cuts to the hit: from a little before it starts to where it has fallen past
		hearing.

		@param held The audio.
		@param was The rate it is at.
		@return The part worth keeping.
	**/
	function cut(held:Vector<Float>, was:Int):Vector<Float> {
		final peak = loudest(held);
		if (peak <= 0) return held;

		final over = peak * Math.pow(10, tail / 20);
		final quiet = peak * QUIET;

		var head = 0;
		while (head < held.length && size(held[head]) <= quiet) head++;

		if (head >= held.length) return held;

		var last = held.length - 1;
		while (last > head && size(held[last]) <= over) last--;

		final back = Std.int(was * lead);

		var from = head - back;
		if (from < 0) from = 0;

		var until = last + back;
		if (until > held.length) until = held.length;

		if (until <= from) return held;

		final out = new Vector<Float>(until - from);
		for (index in 0...out.length) out[index] = held[from + index];

		return out;
	}

	/**
		@param held The audio.
		@param was The rate it is at.
		@return It no longer than `cap`.
	**/
	function capped(held:Vector<Float>, was:Int):Vector<Float> {
		if (cap <= 0) return held;

		final many = Std.int(was * cap);
		if (many < 1 || held.length <= many) return held;

		final out = new Vector<Float>(many);
		for (index in 0...many) out[index] = held[index];

		return out;
	}

	/**
		@param held The audio.
		@param was The rate it is at.
		@return It with its last few milliseconds taken down, so an end that was cut
			does not click.
	**/
	function faded(held:Vector<Float>, was:Int):Vector<Float> {
		var span = Std.int(was * fade);
		if (span < 2 || held.length < 2) return held;
		if (span > held.length) span = held.length;

		final out = new Vector<Float>(held.length);
		for (index in 0...held.length) out[index] = held[index];

		final from = held.length - span;
		for (index in 0...span) out[from + index] *= 1 - index / (span - 1);

		return out;
	}

	/**
		@param held The audio.
		@return The unsigned bytes the converter takes, brought up to full first where
			that was asked for.
	**/
	function bytes(held:Vector<Float>):Vector<Int> {
		final out = new Vector<Int>(held.length);
		final peak = loudest(held);
		final scale = loud && peak > 0 ? 127 / peak : 127.0;

		for (index in 0...held.length) {
			final value = Math.round(held[index] * scale) + 128;
			out[index] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		return out;
	}

	static inline final QUIET = 0.001;

	static inline function size(value:Float):Float {
		return value < 0 ? -value : value;
	}

	static function loudest(held:Vector<Float>):Float {
		var most = 0.0;

		for (index in 0...held.length) {
			final one = size(held[index]);
			if (one > most) most = one;
		}

		return most;
	}
}
