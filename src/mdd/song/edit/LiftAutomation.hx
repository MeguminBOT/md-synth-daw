package mdd.song.edit;

/**
	Takes an automation lane off a channel and hands it to the caller.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class LiftAutomation implements Command {
	final pattern:Int;
	final part:Part;
	final target:Int;
	final slot:Int;

	var line:Null<Automation> = null;
	var clip:Null<Clip> = null;
	var track:Null<Track> = null;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param pattern Which pattern, by index.
		@param part Which part of the pattern.
		@param target Which channel the lane belongs to, or -1 for the part's own.
		@param slot Which lane of that channel.
	**/
	public function new(pattern:Int, part:Part, target:Int, slot:Int) {
		this.pattern = pattern;
		this.part = part;
		this.target = target;
		this.slot = slot;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
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

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = song.patternAt(pattern);
		final found = line;

		if (track != null) {
			if (clip != null) track.remove(clip);
			song.tracks.remove(track);
		}

		if (held != null && found != null) held.lane(part).automation.push(found);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "move automation to the playlist";
	}
}
