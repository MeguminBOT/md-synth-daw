package mdd.song;

@:unreflective
final class Instrument {
	public var name:String;
	public var kind:Part;

	public var patch:Null<Patch> = null;
	public var envelope:Null<Envelope> = null;
	public var sample:Int = -1;

	public function new(name:String, kind:Part) {
		this.name = name;
		this.kind = kind;

		if (kind.fm()) patch = new Patch();
		else if (kind.square() || kind.noise()) envelope = new Envelope();
	}

	public function copy():Instrument {
		final out = new Instrument(name, kind);
		out.patch = patch == null ? null : patch.copy();
		out.envelope = envelope == null ? null : envelope.copy();
		out.sample = sample;
		return out;
	}
}
