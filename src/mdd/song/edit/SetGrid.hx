package mdd.song.edit;

final class SetGrid implements Command {
	final beats:Float;

	var was:Float = 0;

	public function new(beats:Float) {
		this.beats = beats;
	}

	public function apply(song:Song):Void {
		was = song.tempo.beatsAt(0);
		song.regrid(beats);
	}

	public function revert(song:Song):Void {
		if (was > 0) song.regrid(was);
	}

	public function label():String {
		return "move the grid";
	}
}
