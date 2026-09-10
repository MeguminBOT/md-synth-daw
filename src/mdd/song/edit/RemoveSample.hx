package mdd.song.edit;

/**
	Removes a recording and moves every instrument that named one after it.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.

	An instrument names its recording by place rather than by name, so taking one out
	moves every recording after it and every instrument pointing past it moves with it.
	Taking one out without that leaves each of them playing its neighbour, and the last
	one playing nothing.
**/
final class RemoveSample implements Command {
	final at:Int;

	var sample:Null<Sample> = null;
	final moved:Array<Instrument> = [];
	final marks:Array<Int> = [];

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which one, by index.
	**/
	public function new(at:Int) {
		this.at = at;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (at < 0 || at >= song.samples.length) return;

		sample = song.samples[at];

		moved.resize(0);
		marks.resize(0);

		for (instrument in song.instruments) {
			if (instrument.sample < at) continue;

			moved.push(instrument);
			marks.push(instrument.sample);

			instrument.sample = instrument.sample == at ? -1 : instrument.sample - 1;
		}

		song.samples.splice(at, 1);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = sample;
		if (held == null) return;

		song.samples.insert(at, held);

		for (index in 0...moved.length) moved[index].sample = marks[index];

		moved.resize(0);
		marks.resize(0);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "remove a sample";
	}
}
