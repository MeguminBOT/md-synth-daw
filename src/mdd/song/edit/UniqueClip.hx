package mdd.song.edit;

/**
	Gives a clip a pattern of its own.

	Two clips showing the same pattern are the same music, and editing either one edits
	both. That is what a pattern is for and it is why slicing one leaves two clips still
	joined: a slice cuts where a clip starts and ends, not what it plays. Where the two
	halves are meant to go their separate ways, one of them needs a pattern nothing else
	is looking at, and this is what makes one.

	The copy is put at the end of the song's patterns, so every clip already pointing at
	something keeps pointing at the same thing.

	One step on the undo stack. `apply` does it and `revert` puts the song back exactly
	as it was, which is why anything it overwrites is kept here.
**/
final class UniqueClip implements Command {
	final clip:Clip;

	var made:Null<Pattern> = null;
	var was:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param clip The clip to give a pattern of its own.
	**/
	public function new(clip:Clip) {
		this.clip = clip;
	}

	/**
		@param song The song the clip is in.
		@param clip A clip.
		@return Whether anything else is looking at the pattern it plays. A clip that is
			the only one on it is already unique, and making another copy would leave the
			song carrying a pattern nothing plays.
	**/
	public static function shares(song:Song, clip:Clip):Bool {
		if (clip.automates()) return false;
		if (song.patternAt(clip.pattern) == null) return false;

		var seen = 0;

		for (track in song.tracks) {
			for (held in track.clips) {
				if (held.automates() || held.pattern != clip.pattern) continue;

				seen++;
				if (seen > 1) return true;
			}
		}

		return false;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final from = song.patternAt(clip.pattern);
		if (from == null || clip.automates()) return;

		was = clip.pattern;

		var held = made;

		if (held == null) {
			held = from.copy(named(song, from.name));
			made = held;
		}

		song.patterns.push(held);
		clip.pattern = song.patterns.length - 1;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = made;
		if (held == null || was < 0) return;

		song.patterns.remove(held);
		clip.pattern = was;
	}

	/**
		@param song The song the name has to be unique in.
		@param from The name it is a copy of.
		@return A name nothing in the song is already called. Two copies of one pattern
			both called the same thing are two rows in the list nobody can tell apart.
	**/
	static function named(song:Song, from:String):String {
		var count = 2;

		while (taken(song, from + " " + count)) count++;

		return from + " " + count;
	}

	/**
		@param song The song to look in.
		@param name A name.
		@return Whether a pattern is already called that.
	**/
	static function taken(song:Song, name:String):Bool {
		for (pattern in song.patterns) if (pattern.name == name) return true;
		return false;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "make a clip unique";
	}
}
