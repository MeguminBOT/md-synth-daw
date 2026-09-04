package mdd.song.edit;

final class LiftAutomation implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;

	var line:Null<Automation> = null;
	var clip:Null<Clip> = null;
	var track:Null<Track> = null;

	public function new(pattern:Int, part:Part, target:Int, slot:Int) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
	}

	public function apply(song:Song):Void {
		final held = song.patternAt(pattern);
		if (held == null) return;

		final lane = held.lane(part);

		if (line == null) {
			for (found in lane.automation) {
				if (found.held(target, slot)) line = found;
			}
		}

		final found = line;
		if (found == null) return;

		lane.automation.remove(found);

		if (clip == null) {
			final made = new Clip(-1, placed(song), held.length);

			made.kind = Clip.AUTOMATION;
			made.part = part.index();
			made.line = found;

			clip = made;
		}

		if (track == null) track = new Track(part.name());

		song.tracks.push(track);
		track.add(clip);
	}

	function placed(song:Song):Int {
		for (held in song.tracks) {
			for (found in held.clips) {
				if (found.kind == Clip.PATTERN && found.pattern == pattern) return found.at;
			}
		}

		return 0;
	}

	public function revert(song:Song):Void {
		final held = song.patternAt(pattern);
		final found = line;

		if (track != null) {
			if (clip != null) track.remove(clip);
			song.tracks.remove(track);
		}

		if (held != null && found != null) held.lane(part).automation.push(found);
	}

	public function label():String {
		return "move automation to the playlist";
	}
}
