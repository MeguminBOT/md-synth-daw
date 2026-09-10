package mdd.song.edit;

import mdd.song.Part;

/**
	Changes which speakers one of the parts reaches.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class PanPart implements Command {
	final part:Int;
	final pan:Int;

	var was:Int = 0;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param part Which part, by index.
		@param pan Which speakers it reaches.
	**/
	public function new(part:Int, pan:Int) {
		this.part = part;
		this.pan = pan;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		was = song.pan[part];
		song.pan[part] = pan;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (part < 0 || part >= Part.COUNT) return;

		song.pan[part] = was;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "pan a channel";
	}
}
