package mdd.app;

@:unreflective

/**
	When each preset the reader has installed was first seen, by identity, which is what the
	browser sorts and groups by date added.

	A preset is kept by what it sounds like, so a date stays with it through a rename, a new set of
	tags or a move to another folder, and only a preset never seen before is given one. That date
	is when its file was last written where the file says, which is when it arrived for a preset
	copied in from elsewhere, and the moment it was first seen otherwise. The presets the
	application ships are not listed: they have been there since it was installed.

	The list is a reader's own rather than a piece's, so it is kept beside the settings.
**/
final class Added {
	/**
		Called whenever the list changes, which is what writes it back out.
	**/
	public var onChange:Null<Void -> Void> = null;

	final held:haxe.ds.StringMap<Float> = new haxe.ds.StringMap<Float>();

	/**
		The identities in the order they were first seen, which is the order they are written in,
		since a map keeps no order on every target.
	**/
	final order:Array<String> = [];

	public function new() {}

	/**
		@return How many presets have a date.
	**/
	public inline function count():Int {
		return order.length;
	}

	/**
		@param id A preset's identity.
		@return When it was first seen, in seconds since 1970, or nought where it never was, as
			for a preset the application ships.
	**/
	public function when(id:String):Float {
		final at = held.get(id);
		return at == null ? 0 : at;
	}

	/**
		Gives a preset a date, unless it already has one.

		@param id Its identity.
		@param time When it arrived, in seconds since 1970.
		@return Whether it was new.
	**/
	public function notes(id:String, time:Float):Bool {
		if (id == "" || held.exists(id)) return false;

		held.set(id, time);
		order.push(id);

		return true;
	}

	/**
		Gives every preset the library read out of the presets folder a date, where it has none,
		and says once where anything was new.

		@param library The library, just read.
		@param now What time it is, in seconds since 1970, for a preset whose file gave none.
		@return How many were given a date.
	**/
	public function sees(library:mdd.song.Library, now:Float):Int {
		var many = 0;

		for (at in 0...library.names.length) {
			if (!library.owned[at]) continue;

			final held = library.instruments[at];
			final times = library.times[at];

			for (which in 0...held.length) {
				final time = which < times.length && times[which] > 0 ? times[which] : now;
				if (notes(held[which].id, time)) many++;
			}
		}

		if (many > 0 && onChange != null) onChange();

		return many;
	}

	/**
		@return The whole list, one preset a line, which is how it is kept on disk.
	**/
	public function spelt():String {
		final out = new StringBuf();

		for (id in order) {
			out.add(id);
			out.add(" ");
			out.add(Std.string(Math.round(when(id))));
			out.add("\n");
		}

		return out.toString();
	}

	/**
		Reads the list back, replacing whatever was held. A line that does not read is passed over.

		@param said What `spelt` wrote.
	**/
	public function reads(said:String):Void {
		held.clear();
		order.resize(0);

		for (line in said.split("\n")) {
			final space = line.indexOf(" ");
			if (space <= 0) continue;

			final time = Std.parseFloat(StringTools.trim(line.substr(space + 1)));
			if (Math.isNaN(time)) continue;

			notes(line.substr(0, space), time);
		}
	}
}
