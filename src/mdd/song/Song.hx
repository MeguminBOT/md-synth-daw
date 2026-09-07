package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Song {
	public var name:String;
	public var author:String = "";

	public var lfoOn:Bool = false;
	public var lfoRate:Int = 0;
	public var mode:Int = 0;
	public var driving:Bool = false;

	public var stallAt:Int = -1;
	public var stallFor:Int = 0;
	public var stallEvery:Float = 735;

	public final tempo:Tempo;

	public final patterns:Array<Pattern> = [];
	public final tracks:Array<Track> = [];
	public final instruments:Array<Instrument> = [];
	public final banks:Array<Bank> = [];
	public final samples:Array<Sample> = [];

	public final rack:Vector<Int> = new Vector<Int>(Part.COUNT);
	public static inline final LOUDEST = 127;

	public final muted:Vector<Bool> = new Vector<Bool>(Part.COUNT);
	public final soloed:Vector<Bool> = new Vector<Bool>(Part.COUNT);
	public final volume:Vector<Int> = new Vector<Int>(Part.COUNT);
	public final pan:Vector<Int> = new Vector<Int>(Part.COUNT);

	public static inline final LEFT = 2;
	public static inline final RIGHT = 1;
	public static inline final BOTH = 3;

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

	public function add(pattern:Pattern):Pattern {
		patterns.push(pattern);
		return pattern;
	}

	public function track(track:Track):Track {
		tracks.push(track);
		return track;
	}

	public function instrument(instrument:Instrument):Instrument {
		instruments.push(instrument);
		bank(0).add(instruments.length - 1);
		return instrument;
	}

	public function bank(index:Int):Bank {
		while (banks.length <= index) {
			banks.push(new Bank(banks.length == 0 ? "Default" : "bank " + banks.length));
		}

		return banks[index];
	}

	public function banked(name:String, kept:Bool = true):Bank {
		for (held in banks) if (held.name == name) return held;

		final made = new Bank(name, kept);
		banks.push(made);

		return made;
	}

	public function bankOf(index:Int):Int {
		for (at in 0...banks.length) if (banks[at].holds(index)) return at;
		return 0;
	}

	public function sample(sample:Sample):Sample {
		samples.push(sample);
		return sample;
	}

	public function patternAt(index:Int):Null<Pattern> {
		return index < 0 || index >= patterns.length ? null : patterns[index];
	}

	public function patchOf(part:Part):Null<Patch> {
		final held = instrumentAt(rack[part.index()]);
		return held == null ? null : held.patch;
	}

	public function instrumentAt(index:Int):Null<Instrument> {
		return index < 0 || index >= instruments.length ? null : instruments[index];
	}

	public function sampleAt(index:Int):Null<Sample> {
		return index < 0 || index >= samples.length ? null : samples[index];
	}

	public function chosen(part:Part, note:Note):Null<Instrument> {
		final named = note.instrument >= 0 ? note.instrument : rack[part.index()];
		return instrumentAt(named);
	}

	function soloing():Bool {
		for (i in 0...Part.COUNT) if (soloed[i]) return true;
		return false;
	}

	public function audible(part:Part):Bool {
		final index = part.index();
		if (soloing()) return soloed[index];
		return !muted[index];
	}

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
				made.add(new Clip(out.patterns.length - 1, clip.at, clip.length, 0));
			}

			out.track(made);
		}

		return out;
	}

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

	public function retick(ppqn:Int):Void {
		final want = ppqn < 1 ? 96 : ppqn;
		final was = tempo.ppqn;

		if (want == was) return;

		stretch(want / was);
		tempo.resolve(want);
	}

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

	static function holds(lane:Lane):Bool {
		if (lane.notes.length > 0) return true;

		for (line in lane.automation) {
			if (line.points.length < 2) continue;

			final first = line.points[0].value;
			for (point in line.points) if (point.value != first) return true;
		}

		return false;
	}

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

	static inline function moved(value:Int, by:Int):Int {
		final held = value + by;
		return held < 0 ? 0 : held;
	}

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
			}
		}

		for (index in 0...tempo.at.length) tempo.at[index] = scaled(tempo.at[index], by);
	}

	static inline function scaled(value:Int, by:Float):Int {
		final held = Math.round(value * by);
		return held < 0 ? 0 : held;
	}

	public function ends():Int {
		var most = 0;
		for (track in tracks) if (track.ends() > most) most = track.ends();
		return most;
	}
}
