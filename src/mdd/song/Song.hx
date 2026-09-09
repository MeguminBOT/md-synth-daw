package mdd.song;

import haxe.ds.Vector;

/**
	The whole piece: its patterns, its tracks, its instruments, its banks, its samples,
	the tempo map, and the mixer state of every part.

	It is the model and nothing else. It draws nothing, plays nothing and knows about
	no interface.
**/
@:unreflective
final class Song {
	/**
		What the piece is called.
	**/
	public var name:String;

	/**
		Who wrote it.
	**/
	public var author:String = "";

	/**
		Whether the FM part LFO runs.
	**/
	public var lfoOn:Bool = false;

	/**
		How fast it runs, 0 to 7.
	**/
	public var lfoRate:Int = 0;

	/**
		Channel three mode: normal, separate, or CSM.
	**/
	public var mode:Int = 0;

	/**
		Whether an export is paced the way a real sound driver would pace it.
	**/
	public var driving:Bool = false;

	/**
		Where a deliberate driver stall begins, in ticks, or -1 for none. This is how a
		piece can be made to sound the way it does on hardware that is busy elsewhere.
	**/
	public var stallAt:Int = -1;

	/**
		How long that stall lasts.
	**/
	public var stallFor:Int = 0;

	/**
		How often it happens, in samples.
	**/
	public var stallEvery:Float = 735;

	/**
		The tempo map.
	**/
	public final tempo:Tempo;

	/**
		Every pattern, whether placed or not.
	**/
	public final patterns:Array<Pattern> = [];

	/**
		The playlist rows, in order.
	**/
	public final tracks:Array<Track> = [];

	/**
		Every instrument the song carries.
	**/
	public final instruments:Array<Instrument> = [];

	/**
		The groups those instruments are offered in.
	**/
	public final banks:Array<Bank> = [];

	/**
		Every sample the song carries.
	**/
	public final samples:Array<Sample> = [];

	/**
		Which instrument each part plays when a note does not name one.
	**/
	public final rack:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		The loudest a channel volume goes.
	**/
	public static inline final LOUDEST = 127;

	/**
		Which parts are muted.
	**/
	public final muted:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	/**
		Which parts are soloed. Any solo silences everything not soloed.
	**/
	public final soloed:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	/**
		Each part volume, 0 to 127.
	**/
	public final volume:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Each part stereo bits, `LEFT`, `RIGHT` or `BOTH`.
	**/
	public final pan:Vector<Int> = new Vector<Int>(Part.COUNT);

	/**
		Pan: left only.
	**/
	public static inline final LEFT = 2;

	/**
		Pan: right only.
	**/
	public static inline final RIGHT = 1;

	/**
		Pan: both sides.
	**/
	public static inline final BOTH = 3;

	/**
		Builds an empty song with everything unmuted and at full volume.

		@param name What to call it.
		@param ppqn Ticks per quarter note.
		@param beats The tempo at the start.
	**/
	public function new(name:String = "untitled", ppqn:Int = 96, beats:Float = 120) {
		this.name = name;
		tempo = new Tempo(ppqn, beats);

		for (i in 0...Part.COUNT) {
			rack[i] = -1;
			muted[i] = false;
			soloed[i] = false;
			volume[i] = LOUDEST;
			pan[i] = BOTH;
		}
	}

	/**
		Adds a pattern.

		@param pattern The pattern to add.
		@return The same pattern.
	**/
	public function add(pattern:Pattern):Pattern {
		patterns.push(pattern);
		return pattern;
	}

	/**
		Adds a playlist row.

		@param track The track to add.
		@return The same track.
	**/
	public function track(track:Track):Track {
		tracks.push(track);
		return track;
	}

	/**
		Adds an instrument.

		@param instrument The instrument to add.
		@return The same instrument.
	**/
	public function instrument(instrument:Instrument):Instrument {
		instruments.push(instrument);
		bank(0).add(instruments.length - 1);
		return instrument;
	}

	/**
		@param index Which bank.
		@return That bank, or the first one where the index is out of range.
	**/
	public function bank(index:Int):Bank {
		while (banks.length <= index) {
			banks.push(new Bank(banks.length == 0 ? "Default" : "bank " + banks.length));
		}

		return banks[index];
	}

	/**
		Finds a bank by name, creating it where there is none.

		@param name What it is called.
		@param kept Whether a bank created here is saved with the song.
		@return The bank.
	**/
	public function banked(name:String, kept:Bool = true):Bank {
		for (held in banks) if (held.name == name) return held;

		final made = new Bank(name, kept);
		banks.push(made);

		return made;
	}

	/**
		@param index An instrument, by index.
		@return Which bank holds it, or -1 where none does.
	**/
	public function bankOf(index:Int):Int {
		for (at in 0...banks.length) if (banks[at].holds(index)) return at;
		return 0;
	}

	/**
		Adds a sample.

		@param sample The sample to add.
		@return The same sample.
	**/
	public function sample(sample:Sample):Sample {
		samples.push(sample);
		return sample;
	}

	/**
		@param index Which pattern.
		@return That pattern, or null where the index is out of range.
	**/
	public function patternAt(index:Int):Null<Pattern> {
		return index < 0 || index >= patterns.length ? null : patterns[index];
	}

	/**
		@param part Which part.
		@return The patch the rack holds for it, or null where there is none.
	**/
	public function patchOf(part:Part):Null<Patch> {
		final held = instrumentAt(rack[part.index()]);
		return held == null ? null : held.patch;
	}

	/**
		@param index Which instrument.
		@return That instrument, or null where the index is out of range.
	**/
	public function instrumentAt(index:Int):Null<Instrument> {
		return index < 0 || index >= instruments.length ? null : instruments[index];
	}

	/**
		@param index Which sample.
		@return That sample, or null where the index is out of range.
	**/
	public function sampleAt(index:Int):Null<Sample> {
		return index < 0 || index >= samples.length ? null : samples[index];
	}

	/**
		@param part Which part.
		@param note The note being played.
		@return The instrument that note plays, which is its own where it names one and the rack one
			otherwise.
	**/
	public function chosen(part:Part, note:Note):Null<Instrument> {
		final named = note.instrument >= 0 ? note.instrument : rack[part.index()];
		return instrumentAt(named);
	}

	/**
		Whether the arrangement ever sounds a part, which is what decides whether it is
		worth a stem of its own. A muted track carries nothing, and neither does a part
		the mixer has silenced.

		@param part A part.
		@return Whether any placed clip writes a note on it.
	**/
	public function carries(part:Part):Bool {
		if (!audible(part)) return false;

		for (track in tracks) {
			if (track.muted) continue;

			for (clip in track.clips) {
				if (clip.automates()) continue;

				final pattern = patternAt(clip.pattern);
				if (pattern == null) continue;

				if (pattern.lane(part).notes.length > 0) return true;
			}
		}

		return false;
	}

	/**
		@return Whether any part is soloed.
	**/
	function soloing():Bool {
		for (i in 0...Part.COUNT) if (soloed[i]) return true;
		return false;
	}

	/**
		@param part Which part.
		@return Whether it should sound, taking both mute and solo into account.
	**/
	public function audible(part:Part):Bool {
		final index = part.index();
		if (soloing()) return soloed[index];
		return !muted[index];
	}

	/**
		Copies the song with every clip given a pattern of its own, so a format that
		cannot express reuse can be written from it without changing this one.

		@return The flattened copy.
	**/
	public function unshared():Song {
		final out = new Song(name, tempo.ppqn, tempo.bpm[0]);

		out.author = author;
		out.lfoOn = lfoOn;
		out.stallAt = stallAt;
		out.stallFor = stallFor;
		out.stallEvery = stallEvery;
		out.lfoRate = lfoRate;
		out.mode = mode;
		out.driving = driving;
		out.tempo.rate = tempo.rate;

		for (i in 1...tempo.at.length) out.tempo.set(tempo.at[i], tempo.bpm[i]);

		for (instrument in instruments) out.instrument(instrument.copy());
		for (sample in samples) out.sample(sample.copy());

		out.banks.resize(0);

		for (held in banks) {
			final made = out.banked(held.name, held.kept);
			for (index in held.instruments) made.add(index);
		}

		for (i in 0...Part.COUNT) {
			out.rack[i] = rack[i];
			out.muted[i] = muted[i];
			out.soloed[i] = soloed[i];
			out.volume[i] = volume[i];
			out.pan[i] = pan[i];
		}

		for (track in tracks) {
			final made = new Track(track.name);

			made.colour = track.colour;
			made.icon = track.icon;
			made.muted = track.muted;

			for (clip in track.clips) {
				final source = patternAt(clip.pattern);

				if (source == null) {
					made.add(clip.copy());
					continue;
				}

				final pattern = new Pattern(source.name + " " + out.patterns.length,
					source.length, source.colour);

				for (index in 0...Part.COUNT) {
					final part:Part = index;
					final lane = source.lane(part);

					for (note in lane.notes) {
						final held = note.copy();
						held.pitch += clip.transpose;
						pattern.lane(part).add(held);
					}

					for (line in lane.automation) {
						final held = new Automation(line.target, line.slot);
						for (point in line.points) held.add(point.copy());
						pattern.lane(part).automation.push(held);
					}
				}

				out.add(pattern);
				made.add(new Clip(out.patterns.length - 1, clip.at, clip.length, 0, clip.offset));
			}

			out.track(made);
		}

		return out;
	}

	/**
		@return How many patterns are placed by more than one clip.
	**/
	public function shares():Int {
		final seen:Array<Int> = [];
		var many = 0;

		for (track in tracks) {
			for (clip in track.clips) {
				if (seen.indexOf(clip.pattern) >= 0) many++;
				else seen.push(clip.pattern);
			}
		}

		return many;
	}

	/**
		Changes the tick resolution, moving everything to keep the music where it was.

		@param ppqn The new ticks per quarter note.
	**/
	public function retick(ppqn:Int):Void {
		final want = ppqn < 1 ? 96 : ppqn;
		final was = tempo.ppqn;

		if (want == was) return;

		stretch(want / was);
		tempo.resolve(want);
	}

	/**
		Changes the tempo and moves the music with it, so the piece sounds the same and
		the grid underneath it does not.

		@param beats The new tempo.
	**/
	public function regrid(beats:Float):Void {
		final was = tempo.beatsAt(0);

		if (was <= 0 || beats <= 0) return;

		final by = beats / was;
		if (by > 0.9999 && by < 1.0001) return;

		stretch(by);

		for (index in 0...tempo.bpm.length) tempo.bpm[index] *= by;

		tempo.resolve(tempo.ppqn);
	}

	public var offset(default, null):Int = 0;

	/**
		Breaks one pattern carrying several parts into one pattern per part, each on a
		track of its own, which is what an import that read a whole register log needs.

		@param source The pattern to break up.
		@return False where it carried nothing worth splitting.
	**/
	public function split(source:Pattern):Bool {
		final length = source.length;

		var used = 0;
		for (index in 0...Part.COUNT) if (holds(source.lane(index))) used++;

		if (used < 2) return false;

		patterns.remove(source);
		while (tracks.length > 0) tracks.remove(tracks[0]);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = source.lane(part);

			if (!holds(lane)) continue;

			final made = add(new Pattern(part.name(), length));
			made.part = index;

			for (note in lane.notes) made.lane(part).add(note);
			for (line in lane.automation) made.lane(part).automation.push(line);

			final track = this.track(new Track(part.name()));
			track.add(new Clip(patterns.length - 1, 0, length));
		}

		return true;
	}

	/**
		@param lane A lane.
		@return Whether it carries notes, or automation that ever changes.
	**/
	static function holds(lane:Lane):Bool {
		if (lane.notes.length > 0) return true;

		for (line in lane.automation) {
			if (line.points.length < 2) continue;

			final first = line.points[0].value;
			for (point in line.points) if (point.value != first) return true;
		}

		return false;
	}

	/**
		@return The first tick anything happens on, or -1 for an empty song.
	**/
	function earliest():Int {
		var least = -1;

		for (pattern in patterns) {
			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);

				for (note in lane.notes) if (least < 0 || note.at < least) least = note.at;

				for (line in lane.automation) {
					for (point in line.points) if (least < 0 || point.at < least) least = point.at;
				}
			}
		}

		for (track in tracks) {
			for (clip in track.clips) if (least < 0 || clip.at < least) least = clip.at;
		}

		for (index in 0...tempo.at.length) {
			final held = tempo.at[index];
			if (held > 0 && (least < 0 || held < least)) least = held;
		}

		return least < 0 ? 0 : least;
	}

	/**
		Moves the whole piece along in time, clips, notes, points and tempo changes
		alike. Nothing is moved before nought.

		@param by How far to move it, in ticks.
		@return How far it actually moved.
	**/
	public function shift(by:Int):Int {
		if (by == 0) return 0;

		offset += by;

		for (pattern in patterns) {
			if (by > 0) pattern.length += by;

			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);

				for (note in lane.notes) note.at = moved(note.at, by);
				for (line in lane.automation) {
					for (point in line.points) point.at = moved(point.at, by);
				}
			}
		}

		for (index in 0...tempo.at.length) {
			if (tempo.at[index] > 0) tempo.at[index] = moved(tempo.at[index], by);
		}

		tempo.resolve(tempo.ppqn);
		return by;
	}

	/**
		@param value A tick.
		@param by How far to move it.
		@return The moved tick, never below nought.
	**/
	static inline function moved(value:Int, by:Int):Int {
		final held = value + by;
		return held < 0 ? 0 : held;
	}

	/**
		Scales every position in the piece, which is what changing the resolution or the
		grid comes down to.

		@param by What to multiply every position by.
	**/
	public function stretch(by:Float):Void {
		if (by <= 0) return;

		for (pattern in patterns) {
			pattern.length = scaled(pattern.length, by);

			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);

				for (note in lane.notes) {
					note.at = scaled(note.at, by);
					note.length = scaled(note.length, by);
				}

				for (line in lane.automation) {
					for (point in line.points) point.at = scaled(point.at, by);
				}
			}
		}

		for (track in tracks) {
			for (clip in track.clips) {
				clip.at = scaled(clip.at, by);
				clip.length = scaled(clip.length, by);
				clip.offset = scaled(clip.offset, by);
			}
		}

		for (index in 0...tempo.at.length) tempo.at[index] = scaled(tempo.at[index], by);
	}

	/**
		@param value A tick.
		@param by What to multiply it by.
		@return The scaled tick.
	**/
	static inline function scaled(value:Int, by:Float):Int {
		final held = Math.round(value * by);
		return held < 0 ? 0 : held;
	}

	/**
		@return The tick the last clip on any track finishes on.
	**/
	public function ends():Int {
		var most = 0;
		for (track in tracks) if (track.ends() > most) most = track.ends();
		return most;
	}
}
