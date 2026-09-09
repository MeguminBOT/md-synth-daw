package mdd.song.edit;

import mdd.song.Part;

/**
	Folds every clip on a track into one pattern and one clip.

	One step on the undo stack. `apply` does it and `revert` puts the song back
	exactly as it was, which is why anything it overwrites is kept here.
**/
final class MergeClips implements Command {
	final track:Int;
	final name:String;

	final was:Array<Clip> = [];

	var made:Null<Clip> = null;
	var pattern:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param track Which track, by index.
		@param name The new name.
	**/
	public function new(track:Int, name:String) {
		this.track = track;
		this.name = name;
	}

	public static function merges(held:Track):Bool {
		var many = 0;
		for (clip in held.clips) if (clip.kind == Clip.PATTERN) many++;

		return many > 1;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		if (track < 0 || track >= song.tracks.length) return;

		final held = song.tracks[track];
		if (!merges(held)) return;

		was.resize(0);
		for (clip in held.clips) was.push(clip);

		var first = -1;
		var last = 0;

		for (clip in held.clips) {
			if (clip.kind != Clip.PATTERN) continue;
			if (first < 0 || clip.at < first) first = clip.at;
			if (clip.ends() > last) last = clip.ends();
		}

		if (first < 0 || last <= first) return;

		final folded = new Pattern(name, last - first, held.colour);

		for (clip in held.clips) {
			if (clip.kind != Clip.PATTERN) continue;

			final source = song.patternAt(clip.pattern);
			if (source == null) continue;

			final shift = clip.at - first;

			for (index in 0...Part.COUNT) {
				final part:Part = index;
				final lane = source.lane(part);

				for (note in lane.notes) {
					if (note.at < clip.offset) continue;
					if (note.at >= clip.offset + clip.length) continue;

					final copy = note.copy();

					copy.at = shift + note.at - clip.offset;
					copy.pitch += clip.transpose;

					if (copy.at + copy.length > folded.length) {
						copy.length = folded.length - copy.at;
					}

					if (copy.length > 0) folded.lane(part).add(copy);
				}

				for (line in lane.automation) {
					final drawn = new Automation(line.target, line.slot);

					for (point in line.points) {
						if (point.at < clip.offset) continue;
						if (point.at >= clip.offset + clip.length) continue;

						final copy = point.copy();
						copy.at = shift + point.at - clip.offset;

						drawn.add(copy);
					}

					if (drawn.points.length > 0) folded.lane(part).automation.push(drawn);
				}
			}
		}

		song.add(folded);
		pattern = song.patterns.length - 1;

		held.clips.resize(0);

		for (clip in was) {
			if (clip.kind != Clip.PATTERN) held.add(clip);
		}

		made = new Clip(pattern, first, last - first);
		held.add(made);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		if (track < 0 || track >= song.tracks.length) return;
		if (pattern < 0) return;

		final held = song.tracks[track];

		held.clips.resize(0);
		for (clip in was) held.clips.push(clip);

		if (pattern == song.patterns.length - 1) song.patterns.pop();

		made = null;
		pattern = -1;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "merge clips";
	}
}
