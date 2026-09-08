package mdd.song.edit;

final class ResetTrack implements Command {
	final at:Int;
	final name:String;

	var was:String = "";
	var wasColour:Int = -1;
	var wasIcon:Int = -1;
	var wasMuted:Bool = false;

	final held:Array<Clip> = [];

	public function new(at:Int, name:String) {
		this.at = at;
		this.name = name;
	}

	public function apply(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		final track = song.tracks[at];

		was = track.name;
		wasColour = track.colour;
		wasIcon = track.icon;
		wasMuted = track.muted;

		held.resize(0);
		for (clip in track.clips) held.push(clip);

		track.name = name;
		track.colour = -1;
		track.icon = -1;
		track.muted = false;
		track.clips.resize(0);
	}

	public function revert(song:Song):Void {
		if (at < 0 || at >= song.tracks.length) return;

		final track = song.tracks[at];

		track.name = was;
		track.colour = wasColour;
		track.icon = wasIcon;
		track.muted = wasMuted;

		track.clips.resize(0);
		for (clip in held) track.clips.push(clip);
	}

	public function label():String {
		return "reset a track";
	}
}
