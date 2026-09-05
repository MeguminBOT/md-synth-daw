package mdd.song;

@:unreflective
final class Instrument {
	public var name:String;
	public var kind:Part;

	public var icon:Int = -1;

	public var patch:Null<Patch> = null;
	public var envelope:Null<Envelope> = null;
	public var sample:Int = -1;

	public final tags:Array<String> = [];

	public function new(name:String, kind:Part) {
		this.name = name;
		this.kind = kind;

		if (kind.fm()) patch = new Patch();
		else if (kind.square() || kind.noise()) envelope = new Envelope();
	}

	public function tagged(said:String):Bool {
		final want = said.toLowerCase();

		if (name.toLowerCase().indexOf(want) >= 0) return true;
		for (tag in tags) if (tag.toLowerCase().indexOf(want) >= 0) return true;

		return false;
	}

	public function copy():Instrument {
		final out = new Instrument(name, kind);
		out.icon = icon;
		out.patch = patch == null ? null : patch.copy();
		out.envelope = envelope == null ? null : envelope.copy();
		out.sample = sample;

		for (tag in tags) out.tags.push(tag);
		return out;
	}
}
