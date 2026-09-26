package mdd.app;

import mdd.song.Pattern;
import mdd.song.edit.AddPattern;

@:unreflective

/**
	What the pattern list does when a button on it is pressed: add, duplicate, rename,
	insert and remove.

	Everything here goes through the command stack, so all of it undoes.
**/
final class Patterns {
	/**
		The session it acts on.
	**/
	public final session:Session;

	/**
		Binds the pattern actions to a session.

		@param session The session to act on.
	**/
	public function new(session:Session) {
		this.session = session;
	}

	/**
		Adds an empty pattern and chooses it.

		@param name What to call it.
	**/
	public function added(name:String):Void {
		final held = session.current();
		final length = held == null ? session.song.bar() : held.length;

		session.does(new AddPattern(new Pattern(name, length)));
		session.chooses(session.song.patterns.length - 1);
	}

	/**
		Copies a pattern and everything in it, and chooses the copy.

		@param at Which pattern, by index.
	**/
	public function duplicated(at:Int):Void {
		final from = session.song.patternAt(at);
		if (from == null) return;

		session.holds();

		final made = from.copy(named(from.name));

		session.frees();

		session.does(new AddPattern(made));
		session.chooses(session.song.patterns.length - 1);
	}

	/**
		@param word What a pattern is called in the language being worn.
		@return The word and a number, which is one past the patterns in the song unless a pattern is
			already called that, and then the first free number after it. Counting the patterns alone
			gave a new pattern the name of one already there as soon as any had been removed.
	**/
	public function numbered(word:String):String {
		var count = session.song.patterns.length + 1;

		while (taken(word + " " + count)) count++;

		return word + " " + count;
	}

	/**
		@param from The name being copied.
		@return A name nothing in the song is already called. Appending the same number
			every time gave two patterns one name as soon as anything was duplicated
			twice, and the list has nothing else to tell them apart by.
	**/
	function named(from:String):String {
		var count = 2;

		while (taken(from + " " + count)) count++;

		return from + " " + count;
	}

	/**
		@param name A name.
		@return Whether a pattern is already called that.
	**/
	function taken(name:String):Bool {
		for (pattern in session.song.patterns) if (pattern.name == name) return true;
		return false;
	}

	/**
		Renames a pattern.

		@param at Which pattern, by index.
		@param to The new name.
	**/
	public function renamed(at:Int, to:String):Void {
		final held = session.song.patternAt(at);
		if (held == null || to == "" || to == held.name) return;

		session.does(new mdd.song.edit.RenamePattern(at, to));
	}

	/**
		Puts a new empty pattern after one.

		@param at Which pattern to insert after, by index.
	**/
	public function inserted(at:Int):Void {
		final held = session.song.patternAt(at);
		final track = session.song.tracks[0];
		if (held == null || track == null) return;

		var ends = 0;
		for (clip in track.clips) if (clip.ends() > ends) ends = clip.ends();

		session.does(new mdd.song.edit.AddClip(0, new mdd.song.Clip(at, ends, held.length)));
	}

	/**
		Removes a pattern and every clip that played it.

		@param at Which pattern, by index.
	**/
	public function dropped(at:Int):Void {
		if (session.song.patterns.length <= 1) return;

		session.does(new mdd.song.edit.RemovePattern(at));

		if (session.pattern >= session.song.patterns.length) {
			session.pattern = session.song.patterns.length - 1;
		}

		session.follows();
		session.changed();
	}
}
