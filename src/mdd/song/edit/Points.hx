package mdd.song.edit;

/**
	Finding and clearing away the automation lane a point command works on.

	The commands that add, move and remove a point all need the same lookup, and one
	of them creating a lane that another then has to remove again is the reason this
	is in one place.
**/
class Points {
	/**
		Finds the automation lane a point belongs to.

		@param song The song to look in.
		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param target Which channel the lane belongs to, or -1 for the part's own.
		@param slot Which lane of that channel.
		@param make Whether to create the lane where there is none yet.
		@param direct A lane to use instead of looking one up.
		@return The lane, or null where there is none and `make` was false.
	**/
	public static function line(song:Song, pattern:Int, part:Part, target:Int, slot:Int,
			make:Bool, direct:Null<Automation> = null):Null<Automation> {
		if (direct != null) return direct;

		final held = song.patternAt(pattern);
		if (held == null) return null;

		final lane = held.lane(part);

		for (found in lane.automation) {
			if (found.held(target, slot)) return found;
		}

		if (!make) return null;

		final made = new Automation(target, slot);
		lane.automation.push(made);

		return made;
	}

	/**
		Removes a lane that was created for a point and is now empty, so undoing an add
		leaves nothing behind. A lane the caller supplied directly is left alone.

		@param song The song to look in.
		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param line The lane to consider removing.
		@param direct The lane the caller supplied, where it did.
	**/
	public static function drop(song:Song, pattern:Int, part:Part, line:Automation,
			direct:Null<Automation> = null):Void {
		if (direct != null) return;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).automation.remove(line);
	}
}
