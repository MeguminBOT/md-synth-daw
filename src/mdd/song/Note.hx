package mdd.song;

/**
	One note in one lane: when it starts, how long it lasts, its pitch, how hard it is
	played and which instrument plays it.
**/
@:unreflective
final class Note {
	/**
		Where it starts, in ticks.
	**/
	public var at:Int;

	/**
		How long it lasts, in ticks.
	**/
	public var length:Int;

	/**
		Its MIDI note number.
	**/
	public var pitch:Int;

	/**
		How hard it is played, 1 to 127.
	**/
	public var velocity:Int;

	/**
		Which instrument plays it, or -1 to use whatever the rack holds for the part.
	**/
	public var instrument:Int;

	/**
		Whether the note after it runs straight on, so no key off happens between them.
	**/
	public var tied:Bool = false;

	/**
		Builds a note.

		@param at Where it starts, in ticks.
		@param length How long it lasts, in ticks.
		@param pitch Its MIDI note number.
		@param velocity How hard it is played, 1 to 127.
		@param instrument Which instrument plays it, or -1 for the rack.
	**/
	public function new(at:Int, length:Int, pitch:Int, velocity:Int = 100,
			instrument:Int = -1) {
		this.at = at;
		this.length = length;
		this.pitch = pitch;
		this.velocity = velocity;
		this.instrument = instrument;
	}

	/**
		@return A new note with the same values.
	**/
	public function copy():Note {
		final out = new Note(at, length, pitch, velocity, instrument);
		out.tied = tied;

		return out;
	}

	/**
		@return The tick it finishes on.
	**/
	public inline function ends():Int {
		return at + length;
	}

	/**
		@param other Another note.
		@return Whether the two carry the same values. Identity is not enough, because a copy taken
			for an undo step has to compare equal.
	**/
	public function same(other:Note):Bool {
		return at == other.at && length == other.length && pitch == other.pitch
			&& velocity == other.velocity && instrument == other.instrument
			&& tied == other.tied;
	}
}
