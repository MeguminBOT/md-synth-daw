package mdd.song;

@:unreflective
final class Track {
	public var name:String;
	public var held:Int;
	public var muted:Bool = false;
	public final clips:Array<Clip> = [];

	public function new(name:String, held:Int = -1) {
		this.name = name;
		this.held = held;
	}

	public function add(clip:Clip):Clip {
		var at = clips.length;
		while (at > 0 && clips[at - 1].at > clip.at) at--;

		clips.insert(at, clip);
		return clip;
	}

	public function remove(clip:Clip):Bool {
		return clips.remove(clip);
	}

	public function ends():Int {
		var most = 0;
		for (clip in clips) if (clip.ends() > most) most = clip.ends();
		return most;
	}
}
