package mdd.song;

interface Command {
	public function apply(song:Song):Void;
	public function revert(song:Song):Void;
	public function label():String;
}
