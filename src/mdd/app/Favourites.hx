package mdd.app;

/**
	The presets a reader has starred, by identity.

	A preset is what it sounds like, and its identity is a hash of that, so a star follows a preset
	from one piece to the next, from one machine to the next, and through a rename or a move to
	another folder, and a preset edited into something else is no longer the one that was starred.
	The list is a reader's own rather than a piece's, so it is kept beside the settings and never
	written into a file a piece carries.
**/
@:unreflective
final class Favourites {
	/**
		Called whenever the list changes, which is what writes it back out.
	**/
	public var onChange:Null<Void -> Void> = null;

	final held:Array<String> = [];

	public function new() {}

	/**
		@return How many are starred.
	**/
	public inline function count():Int {
		return held.length;
	}

	/**
		@param id A preset's identity.
		@return Whether it is starred. An empty identity never is.
	**/
	public function favours(id:String):Bool {
		return id != "" && held.indexOf(id) >= 0;
	}

	/**
		Stars one or takes the star off it.

		@param id A preset's identity.
		@param on Whether it should be starred.
		@return Whether the list changed, which an empty identity never makes it do.
	**/
	public function favour(id:String, on:Bool):Bool {
		if (id == "") return false;

		final at = held.indexOf(id);

		if (on) {
			if (at >= 0) return false;

			held.push(id);
		} else {
			if (at < 0) return false;

			held.splice(at, 1);
		}

		if (onChange != null) onChange();

		return true;
	}

	/**
		Stars one that is not starred and unstars one that is.

		@param id A preset's identity.
		@return Whether it is starred now.
	**/
	public function toggles(id:String):Bool {
		final want = !favours(id);
		favour(id, want);

		return want;
	}

	/**
		@return The whole list as one line, which is how the settings hold it.
	**/
	public function spelt():String {
		return held.join(",");
	}

	/**
		Reads the list back, replacing whatever was held.

		@param said A line `spelt` wrote.
	**/
	public function reads(said:String):Void {
		held.resize(0);

		for (one in said.split(",")) {
			final id = StringTools.trim(one);
			if (id != "" && held.indexOf(id) < 0) held.push(id);
		}
	}
}
