package mdd.app;

import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.edit.AddPattern;

@:unreflective
final class Patterns {
	public final session:Session;

	public function new(session:Session) {
		this.session = session;
	}

	public function added(name:String):Void {
		final held = session.current();
		final length = held == null ? session.song.tempo.ppqn * 4 : held.length;

		session.does(new AddPattern(new Pattern(name, length)));
		session.chooses(session.song.patterns.length - 1);
	}

	public function duplicated(at:Int):Void {
		final from = session.song.patternAt(at);
		if (from == null) return;

		final made = new Pattern(from.name + " 2", from.length, from.colour);
		made.part = from.part;

		session.holds();

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			for (note in from.lane(part).notes) made.lane(part).add(note.copy());
		}

		session.frees();

		session.does(new AddPattern(made));
		session.chooses(session.song.patterns.length - 1);
	}

	public function renamed(at:Int, to:String):Void {
		final held = session.song.patternAt(at);
		if (held == null || to == "" || to == held.name) return;

		session.does(new mdd.song.edit.RenamePattern(at, to));
	}

	public function inserted(at:Int):Void {
		final held = session.song.patternAt(at);
		final track = session.song.tracks[0];
		if (held == null || track == null) return;

		var ends = 0;
		for (clip in track.clips) if (clip.ends() > ends) ends = clip.ends();

		session.does(new mdd.song.edit.AddClip(0, new mdd.song.Clip(at, ends, held.length)));
	}

	public function dropped(at:Int):Void {
		if (session.song.patterns.length <= 1) return;

		session.does(new mdd.song.edit.RemovePattern(at));

		if (session.pattern >= session.song.patterns.length) {
			session.pattern = session.song.patterns.length - 1;
		}

		session.follows();
		session.changed();
	}
}
