package mdd.song.edit;

import mdd.song.Part;

/**
	Changes how loud one of the parts is in the mix.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class SetVolume implements Command {
	final part:Int;
	final volume:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param part Which part, by index.
		@param volume How loud, 0 to 127.
	**/
	public function new(part:Int, volume:Int) {
		this.part = part;
		this.volume = volume;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		was = song.volume[part];
		song.volume[part] = volume;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		song.volume[part] = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "set a channel volume";
	}
}
