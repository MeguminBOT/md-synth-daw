package mdd.song.edit;

interface Command {
	public function apply(song:Song):Void;
	public function revert(song:Song):Void;
	public function label():String;
}
