package mdd.song.edit;

import haxe.ds.Vector;

/**
	Scales a recording up until its loudest byte reaches full scale.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.

	Scaling rounds and clamps, so the bytes it started from are kept whole rather than
	the gain that made them: dividing back out would not land on what was there.
**/
final class LoudenSample implements Command {
	final at:Int;

	var was:Null<Vector<Int>> = null;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which recording, by index.
	**/
	public function new(at:Int) {
		this.at = at;
	}

	/**
		@param sample A recording.
		@return How far its loudest byte sits from the middle, or nought where it is silent.
	**/
	public static function peakOf(sample:Sample):Int {
		final bytes = sample.bytes;
		var most = 0;

		for (index in 0...bytes.length) {
			final away = bytes[index] - 128;
			final much = away < 0 ? -away : away;

			if (much > most) most = much;
		}

		return most;
	}

	/**
		@param sample A recording.
		@return Whether scaling it would change anything. A silent one has nothing to scale
			and one already at full scale has nowhere to go.
	**/
	public static function worth(sample:Sample):Bool {
		final most = peakOf(sample);
		return most > 0 && most < 127;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final sample = song.sampleAt(at);
		if (sample == null) return;

		final most = peakOf(sample);
		if (most <= 0 || most >= 127) return;

		final bytes = sample.bytes;
		final kept = new Vector<Int>(bytes.length);

		Vector.blit(bytes, 0, kept, 0, bytes.length);
		was = kept;

		final gain = 127 / most;

		for (index in 0...bytes.length) {
			final value = Math.round((bytes[index] - 128) * gain) + 128;
			bytes[index] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = was;
		final sample = song.sampleAt(at);

		if (held == null || sample == null) return;
		if (held.length != sample.bytes.length) return;

		Vector.blit(held, 0, sample.bytes, 0, held.length);
		was = null;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "normalise a sample";
	}
}
