package mdd.song;

/**
	One row of the playlist: a name, a colour, an icon and the clips on it.
**/
@:unreflective
final class Track {
	/**
		What the row is called.
	**/
	public var name:String;

	/**
		The row colour, or -1 for the theme. A clip with no colour of its own takes this.
	**/
	public var colour:Int = -1;

	/**
		Which icon the row carries, or -1 for none.
	**/
	public var icon:Int = -1;

	/**
		Whether the row is silent.
	**/
	public var muted:Bool = false;

	/**
		The clips on it, kept in tick order.
	**/
	public final clips:Array<Clip> = [];

	/**
		Builds an empty track.

		@param name What to call it.
	**/
	public function new(name:String) {
		this.name = name;
	}

	/**
		Puts a clip on the track, in tick order.

		@param clip The clip to add.
		@return The same clip.
	**/
	public function add(clip:Clip):Clip {
		var at = clips.length;
		while (at > 0 && clips[at - 1].at > clip.at) at--;

		clips.insert(at, clip);
		return clip;
	}

	/**
		Takes a clip off the track.

		@param clip The clip to remove.
		@return False where it was not on this track.
	**/
	public function remove(clip:Clip):Bool {
		return clips.remove(clip);
	}

	/**
		@return The tick the last clip finishes on.
	**/
	public function ends():Int {
		var most = 0;
		for (clip in clips) if (clip.ends() > most) most = clip.ends();
		return most;
	}
}
