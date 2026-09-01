package mdd.song;

final class SetTempo implements Command {
	final at:Int;
	final beats:Float;

	var was:Float = 0;
	var existed:Bool = false;

	public function new(at:Int, beats:Float) {
		this.at = at;
		this.beats = beats;
	}

	public function apply(song:Song):Void {
		existed = false;

		for (i in 0...song.tempo.at.length) {
			if (song.tempo.at[i] != at) continue;
			existed = true;
			was = song.tempo.bpm[i];
		}

		song.tempo.set(at, beats);
	}

	public function revert(song:Song):Void {
		if (existed) song.tempo.set(at, was);
		else song.tempo.drop(at);
	}

	public function label():String {
		return "set the tempo";
	}
}
