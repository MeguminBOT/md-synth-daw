package mdd.song.edit;

class Points {
	public static function line(song:Song, pattern:Int, part:Part, target:Int, slot:Int,
			make:Bool):Null<Automation> {
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

	public static function drop(song:Song, pattern:Int, part:Part,
			line:Automation):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		held.lane(part).automation.remove(line);
	}
}
