package mdd.song;

import haxe.ds.Vector;

@:unreflective
final class Song {
	public var name:String;
	public var author:String = "";

	public final tempo:Tempo;

	public final patterns:Array<Pattern> = [];
	public final tracks:Array<Track> = [];
	public final instruments:Array<Instrument> = [];
	public final samples:Array<Sample> = [];

	public final rack:Vector<Int> = new Vector<Int>(Part.COUNT);
	public final muted:Vector<Bool> = new Vector<Bool>(Part.COUNT);
	public final soloed:Vector<Bool> = new Vector<Bool>(Part.COUNT);

	public function new(name:String = "untitled", ppqn:Int = 96, beats:Float = 120) {
		this.name = name;
		tempo = new Tempo(ppqn, beats);

		for (i in 0...Part.COUNT) {
			rack[i] = -1;
			muted[i] = false;
			soloed[i] = false;
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
		return instrument;
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
		out.tempo.rate = tempo.rate;

		for (i in 1...tempo.at.length) out.tempo.set(tempo.at[i], tempo.bpm[i]);

		for (instrument in instruments) out.instrument(instrument.copy());
		for (sample in samples) out.sample(sample.copy());

		for (i in 0...Part.COUNT) {
			out.rack[i] = rack[i];
			out.muted[i] = muted[i];
			out.soloed[i] = soloed[i];
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

	public function ends():Int {
		var most = 0;
		for (track in tracks) if (track.ends() > most) most = track.ends();
		return most;
	}
}
