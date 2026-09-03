package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Song {
	public var name:String;
	public var author:String = "";

	public var lfoOn:Bool = false;
	public var lfoRate:Int = 0;
	public var mode:Int = 0;

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

	public function soloing():Bool {
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
			final made = new Track(track.name, track.held);
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

		final scale = want / was;

		for (pattern in patterns) {
			pattern.length = scaled(pattern.length, scale);

			for (index in 0...Part.COUNT) {
				final lane = pattern.lane(index);

				for (note in lane.notes) {
					note.at = scaled(note.at, scale);
					note.length = scaled(note.length, scale);
				}

				for (line in lane.automation) {
					for (point in line.points) point.at = scaled(point.at, scale);
				}
			}
		}

		for (track in tracks) {
			for (clip in track.clips) {
				clip.at = scaled(clip.at, scale);
				clip.length = scaled(clip.length, scale);
			}
		}

		for (index in 0...tempo.at.length) tempo.at[index] = scaled(tempo.at[index], scale);

		tempo.resolve(want);
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
