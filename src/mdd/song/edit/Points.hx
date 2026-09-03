package mdd.song.edit;

class Points {
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

	public static function drop(song:Song, pattern:Int, part:Part, line:Automation,
			direct:Null<Automation> = null):Void {
		if (direct != null) return;

		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).automation.remove(line);
	}
}
