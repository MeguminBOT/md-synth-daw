package mdd.song.edit;

/**
	Changes the time signature of the piece, or of one pattern.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetMeter implements Command {
	final at:Int;
	final beats:Int;
	final unit:Int;

	var wasBeats:Int = 4;
	var wasUnit:Int = 4;
	var wasOwn:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which pattern, by index, or -1 for the piece.
		@param beats How many beats a bar holds, or nought for a pattern to follow the piece.
		@param unit What note a beat is.
	**/
	public function new(at:Int, beats:Int, unit:Int) {
		this.at = at;
		this.beats = beats;
		this.unit = unit;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0) {
			wasBeats = song.meter.beats;
			wasUnit = song.meter.unit;
			song.meter.sets(beats, unit);
			return;
		}

		final pattern = song.patternAt(at);
		if (pattern == null) return;

		final held = pattern.meter;

		wasOwn = held != null;
		wasBeats = held == null ? 0 : held.beats;
		wasUnit = held == null ? 0 : held.unit;

		pattern.meter = beats < 1 ? null : new Meter(beats, unit);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (at < 0) {
			song.meter.sets(wasBeats, wasUnit);
			return;
		}

		final pattern = song.patternAt(at);
		if (pattern == null) return;

		pattern.meter = wasOwn ? new Meter(wasBeats, wasUnit) : null;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return at < 0 ? "change the time signature" : "change a pattern's time signature";
	}
}
