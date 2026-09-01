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

	public function ends():Int {
		var most = 0;
		for (track in tracks) if (track.ends() > most) most = track.ends();
		return most;
	}
}
