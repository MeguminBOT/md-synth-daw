package mdd.format;

@:unreflective

/**
	One strand of a MIDI file: what a single track wrote on a single channel.

	A file is surveyed before any of it is imported, so a reader can be shown what is
	in it and say which parts to take and where each one goes. A track that writes on
	two channels is two strands, because two channels are two things to route.

	The counts are what the survey found and are read only. `taken` and `part` are what
	the reader chose, and they are the only fields the import reads back.
**/
final class Strand {
	/**
		Which track chunk it came from, counted from nought.
	**/
	public var track(default, null):Int;

	/**
		Which MIDI channel it wrote on, counted from nought, so channel ten is nine.
	**/
	public var channel(default, null):Int;

	/**
		What the track called itself, or an empty string where it did not say.
	**/
	public var name:String = "";

	/**
		How many notes it holds.
	**/
	public var notes(default, null):Int = 0;

	/**
		The lowest note it plays, or -1 where it plays none.
	**/
	public var lowest(default, null):Int = -1;

	/**
		The highest note it plays, or -1 where it plays none.
	**/
	public var highest(default, null):Int = -1;

	/**
		Where its last note ends, in the file's own ticks.
	**/
	public var ends(default, null):Int = 0;

	/**
		Whether the import takes it.
	**/
	public var taken:Bool = true;

	/**
		Which part it plays, by index. The survey fills this in with where the channel
		would land on its own, and a reader is free to move it.
	**/
	public var part:Int = 0;

	/**
		Builds an empty strand.

		@param track Which track chunk.
		@param channel Which MIDI channel.
	**/
	public function new(track:Int, channel:Int) {
		this.track = track;
		this.channel = channel;
	}

	/**
		Counts one note into the survey.

		@param pitch Its pitch.
		@param ends Where it finishes, in the file's own ticks.
	**/
	public function counts(pitch:Int, ends:Int):Void {
		notes++;

		if (lowest < 0 || pitch < lowest) lowest = pitch;
		if (pitch > highest) highest = pitch;
		if (ends > this.ends) this.ends = ends;
	}

	/**
		@return Whether it is the channel general MIDI keeps for drums, which is the one
			channel whose notes name a drum rather than a pitch.
	**/
	public inline function drums():Bool {
		return channel == Midi.DRUMS;
	}

	/**
		@return What to call it where it did not name itself: the channel, which is the only
			other thing that tells one strand from another.
	**/
	public function titled():String {
		return name != "" ? name : "Channel " + (channel + 1);
	}
}
