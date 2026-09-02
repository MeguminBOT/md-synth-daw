package mdd.song;

@:unreflective
final class Note {
	public var at:Int;
	public var length:Int;
	public var pitch:Int;
	public var velocity:Int;
	public var instrument:Int;
	public var tied:Bool = false;

	public function new(at:Int, length:Int, pitch:Int, velocity:Int = 100,
			instrument:Int = -1) {
		this.at = at;
		this.length = length;
		this.pitch = pitch;
		this.velocity = velocity;
		this.instrument = instrument;
	}

	public function copy():Note {
		final out = new Note(at, length, pitch, velocity, instrument);
		out.tied = tied;

		return out;
	}

	public inline function ends():Int {
		return at + length;
	}

	public function same(other:Note):Bool {
		return at == other.at && length == other.length && pitch == other.pitch
			&& velocity == other.velocity && instrument == other.instrument
			&& tied == other.tied;
	}
}
