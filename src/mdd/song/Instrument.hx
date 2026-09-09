package mdd.song;

/**
	What a note plays: a name, which kind of part it is for, and one of a patch, an
	envelope or a sample depending on that kind.
**/
@:unreflective
final class Instrument {
	/**
		What it is called.
	**/
	public var name:String;

	/**
		Which family of part it is for, which decides whether the patch, the envelope or
		the sample is the one that matters.
	**/
	public var kind:Part;

	/**
		Which icon it carries, or -1 for none.
	**/
	public var icon:Int = -1;

	/**
		Its FM patch, for an FM instrument.
	**/
	public var patch:Null<Patch> = null;

	/**
		Its envelope, for a square or noise instrument.
	**/
	public var envelope:Null<Envelope> = null;

	/**
		Which sample it plays, by index into the song, for a sample instrument.
	**/
	public var sample:Int = -1;

	/**
		Words the preset browser searches, beside the name.
	**/
	public final tags:Array<String> = [];

	/**
		Builds an instrument, with whichever of a patch or an envelope its kind needs.

		@param name What to call it.
		@param kind Which family of part it is for.
	**/
	public function new(name:String, kind:Part) {
		this.name = name;
		this.kind = kind;

		if (kind.fm()) patch = new Patch();
		else if (kind.square() || kind.noise()) envelope = new Envelope();
	}

	/**
		@param said What was typed into the search.
		@return Whether the name or any tag carries it, ignoring case.
	**/
	public function tagged(said:String):Bool {
		final want = said.toLowerCase();

		if (name.toLowerCase().indexOf(want) >= 0) return true;
		for (tag in tags) if (tag.toLowerCase().indexOf(want) >= 0) return true;

		return false;
	}

	/**
		@return A new instrument with its own copy of whatever it carries.
	**/
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
