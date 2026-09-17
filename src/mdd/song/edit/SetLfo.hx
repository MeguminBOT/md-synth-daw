package mdd.song.edit;

/**
	Switches the chip's LFO on or off and sets how fast it runs, which is one setting for the
	whole song because the part has one LFO for every channel.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetLfo implements Command {
	final on:Bool;
	final rate:Int;

	var wasOn:Bool = false;
	var wasRate:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param on Whether the LFO runs.
		@param rate How fast it runs, 0 to 7.
	**/
	public function new(on:Bool, rate:Int) {
		this.on = on;
		this.rate = rate < 0 ? 0 : (rate > 7 ? 7 : rate);
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		wasOn = song.lfoOn;
		wasRate = song.lfoRate;

		song.lfoOn = on;
		song.lfoRate = rate;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		song.lfoOn = wasOn;
		song.lfoRate = wasRate;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return on ? "set the lfo rate" : "switch the lfo off";
	}
}
