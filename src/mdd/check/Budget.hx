package mdd.check;

import haxe.ds.Vector;
import mdd.play.Stream;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;

@:unreflective
final class Budget {
	public final profile:Profile;

	public final found:Array<Diagnostic> = [];
	public final troubles:Array<Note> = [];

	public final busy:Vector<Int> = new Vector<Int>(Part.COUNT);

	public var operators(default, null):Int = 0;
	public var sampleBytes(default, null):Int = 0;
	public var faults(default, null):Int = 0;

	public function new(profile:Profile) {
		this.profile = profile;
		for (i in 0...Part.COUNT) busy[i] = 0;
	}

	public function clear():Void {
		found.resize(0);
		troubles.resize(0);
		operators = 0;
		sampleBytes = 0;
		faults = 0;

		for (i in 0...Part.COUNT) busy[i] = 0;
	}

	public inline function warnings():Int {
		return found.length;
	}

	public function troubled(note:Note):Bool {
		for (held in troubles) if (held == note) return true;
		return false;
	}

	function raise(severity:Int, part:Part, at:Int, saying:String, reason:String,
			remedy:String = "", pattern:Int = -1, note:Null<Note> = null):Void {
		found.push(new Diagnostic(severity, part, at, saying, reason, remedy, pattern, note));
		if (severity == Diagnostic.FAULT) faults++;
		if (note != null) troubles.push(note);
	}

	public function overSong(song:Song):Int {
		clear();

		for (index in 0...song.patterns.length) overPattern(song, index);

		for (sample in song.samples) sampleBytes += sample.length();

		if (profile.sampleBytes > 0 && sampleBytes > profile.sampleBytes) {
			raise(Diagnostic.WARNING, Part.Dac, 0,
				"the samples come to " + sampleBytes + " bytes",
				profile.name + " holds " + profile.sampleBytes,
				"shorten a sample or lower its rate");
		}

		return found.length;
	}

	function overPattern(song:Song, index:Int):Void {
		final pattern = song.patterns[index];

		for (which in 0...Part.COUNT) {
			final part:Part = which;
			final lane = pattern.lane(part);
			if (lane.notes.length == 0) continue;

			busy[which] += lane.notes.length;

			if (!profile.carries(part)) {
				raise(Diagnostic.FAULT, part, lane.notes[0].at,
					lane.notes.length + " notes are written for a part that is not there",
					profile.name + " has no " + part.name(),
					"move them to a part it has", index, lane.notes[0]);
				continue;
			}

			overlapping(index, part, lane.notes);
			ranged(index, part, lane.notes);
		}

		final dac = pattern.lane(Part.Dac);
		final sixth = pattern.lane(Part.Fm6);

		if (dac.notes.length > 0 && sixth.notes.length > 0) {
			for (note in sixth.notes) {
				for (sampled in dac.notes) {
					if (note.at >= sampled.ends() || sampled.at >= note.ends()) continue;

					raise(Diagnostic.FAULT, Part.Fm6, note.at,
						"FM6 cannot sound while the DAC holds it",
						"the converter replaces the sixth channel rather than joining it",
						"move the note to another FM channel, or move the sample", index, note);
					break;
				}
			}
		}

		for (which in 0...6) {
			final part:Part = which;
			if (!pattern.used(part)) continue;

			final instrument = song.instrumentAt(song.rack[which]);
			if (instrument == null || instrument.patch == null) continue;

			for (slot in 0...4) if (instrument.patch.totalLevel[slot] < 127) operators++;
		}
	}

	function overlapping(pattern:Int, part:Part, notes:Array<Note>):Void {
		var sounding = -1;
		var held:Null<Note> = null;

		for (note in notes) {
			if (note.at < sounding && held != null) {
				raise(Diagnostic.WARNING, part, note.at,
					"this note cannot sound",
					part.name() + " is one voice and is still holding a note from "
					+ held.at,
					"shorten the note before it, or move this one to another channel",
					pattern, note);
				continue;
			}

			sounding = note.ends();
			held = note;
		}
	}

	function ranged(pattern:Int, part:Part, notes:Array<Note>):Void {
		for (note in notes) {
			if (part.square()) {
				if (note.pitch >= profile.lowestSquare) continue;

				raise(Diagnostic.WARNING, part, note.at,
					"this note is below what a square can count to",
					"the lowest a ten bit period reaches is note " + profile.lowestSquare,
					"raise it an octave", pattern, note);
				continue;
			}

			if (!part.fm()) continue;
			if (note.pitch >= profile.lowestFm && note.pitch <= profile.highestFm) continue;

			raise(Diagnostic.WARNING, part, note.at,
				"this note is outside what a block can reach",
				"the FM part covers notes " + profile.lowestFm + " to " + profile.highestFm,
				"move it inside that range", pattern, note);
		}
	}

	public function overStream(stream:Stream):Int {
		clear();

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			final kind = stream.kindAt(index);
			final port = stream.portAt(index);
			final value = stream.valueAt(index);
			final at = stream.tickAt(index);

			if (kind == Stream.PSG) {
				if (profile.carries(Part.Psg1)) continue;

				raise(Diagnostic.FAULT, Part.Psg1, at,
					"a write reached a part that is not there",
					profile.name + " has no SN76489", "choose a profile that has one");
				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			if (half == 0 && address == 0x28) {
				if (profile.keyed(value & 7)) continue;

				raise(Diagnostic.FAULT, keyedPart(value & 7), at,
					"a key on names a channel that is not there",
					profile.name + " has no channel " + ((value & 7) & 3)
					+ " in half " + (((value & 4) != 0) ? 1 : 0),
					"move the note to a channel it has");
				continue;
			}

			if (profile.holds(half, address)) continue;

			raise(Diagnostic.FAULT, halfPart(half, address), at,
				"a write reached a register the part does not have",
				"register " + StringTools.hex(address, 2) + " in half " + half
				+ " is not on " + profile.name,
				"choose a profile that has it");
		}

		return found.length;
	}

	static function keyedPart(select:Int):Part {
		final within = select & 3;
		if (within == 3) return Part.Fm1;
		return within + ((select & 4) != 0 ? 3 : 0);
	}

	static function halfPart(half:Int, address:Int):Part {
		final held = Stream.ymPart(half, address);
		return held < 0 ? Part.Fm1 : held;
	}
}
