package mdd.song.edit;

import mdd.song.Part;

/**
	Mutes or unmutes one of the eleven parts.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MutePart implements Command {
	final part:Int;
	final muted:Bool;

	var was:Bool = false;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param part Which part, by index.
		@param muted Whether the part is muted.
	**/
	public function new(part:Int, muted:Bool) {
		this.part = part;
		this.muted = muted;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		was = song.muted[part];
		song.muted[part] = muted;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		song.muted[part] = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "mute a channel";
	}
}
