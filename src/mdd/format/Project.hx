package mdd.format;

import haxe.ds.Vector;
import haxe.io.Bytes;
import mdd.song.Automation;
import mdd.song.Bank;
import mdd.song.Clip;
import mdd.song.Envelope;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Patch;
import mdd.song.Pattern;
import mdd.song.Point;
import mdd.song.Sample;
import mdd.song.Song;
import mdd.song.Track;
import sys.FileSystem;
import sys.io.File;

/**
	The project file: the song as JSON, with the samples beside it.

	It is written to be byte identical between two saves of the same song, which is
	why the key order is decided here rather than by a map, and why a packed project
	carries a fixed 1980 date rather than a real timestamp. A zip date field cannot
	hold anything before 1980 anyway, and `haxe.zip.Writer` throws rather than saying
	so.
**/
class Project {
	public static inline final VERSION = 2;
	static inline final STRUCTURE = "project.json";
	static inline final BULK = "chunks/bulk.mdc";
	public static inline final SAMPLES = "samples";

	static final EPOCH:Date = new Date(1980, 0, 1, 0, 0, 0);

	/**
		The longest a sample may declare itself.

		The length in the document is a hint: the bytes arrive separately, from a chunk or
		from a file beside it, and replace whatever this reserved. Taken at its word it is
		an allocation of any size a file cares to name, so a document of a few hundred
		bytes asks for gigabytes and the process is killed before anything is read. This
		is a hundred and sixty seconds at the fastest rate the converter runs at, which is
		far past anything a cartridge holds and still only sixteen megabytes.
	**/
	static inline final LONGEST = 1 << 22;

	/**
		The most a packed project is allowed to turn into.

		A project is a zip, and a zip says nothing honest about how much it holds until it
		has been unpacked. Deflate reaches about a thousand to one on a run of one byte, so
		a small file that arrives by mail unpacks into more memory than the machine has and
		the allocator kills the process. A real project of this size would carry an hour of
		samples.
	**/
	static inline final UNPACKED = 512 * 1024 * 1024;

	/**
		Keeps an index the document names inside the range the model has room for.

		Every one of these ends up as an array position. A part index reaches the per part
		state, which is a fixed vector, and a lane target indexes the register bases, which
		is a fixed array: neither is bounds checked once a release build has dropped the
		checks, so a number out of range is read out of bounds on the render thread rather
		than refused at the door. A file is not trusted to be one this application wrote.

		@param value What the document said.
		@param most One past the highest the model has room for.
		@param fallback What to use instead where it is out of range.
		@return A value that is safe to index with.
	**/
	static inline function within(value:Int, most:Int, fallback:Int = 0):Int {
		return value < 0 || value >= most ? fallback : value;
	}

	/**
		Writes the song as a JSON document, without the sample bytes.

		@param song The song to write.
		@return The document.
	**/
	public static function text(song:Song):String {
		return written(song, Needed.of(song));
	}

	/**
		Writes the song as JSON, carrying what a file has to carry.

		@param song The song to write.
		@param needed What it carries and where each preset and recording goes.
		@return The document.
	**/
	public static function written(song:Song, needed:Needed):String {
		final out = new Json();

		out.open();

		out.key("format");
		out.text("mdd");

		out.key("version");
		out.whole(VERSION);

		for (which in 0...Song.DESCRIPTIONS) {
			out.key(Song.DESCRIBED[which]);
			out.text(song.described(which));
		}

		out.key("lfo");
		out.whole((song.lfoOn ? 8 : 0) | (song.lfoRate & 7));

		out.key("mode");
		out.whole(song.mode);

		out.key("driving");
		out.flag(song.driving);

		out.key("drums");
		out.flag(song.drums);

		out.key("stall");
		out.list();
		out.whole(song.stallAt);
		out.whole(song.stallFor);
		out.number(song.stallEvery);
		out.ends();

		out.key("pan");
		out.list();
		for (i in 0...Part.COUNT) out.whole(song.pan[i]);
		out.ends();

		out.key("tempo");
		out.open();
		out.key("ppqn");
		out.whole(song.tempo.ppqn);
		out.key("rate");
		out.whole(song.tempo.rate);
		out.key("changes");
		out.list();

		for (i in 0...song.tempo.at.length) {
			out.open();
			out.key("at");
			out.whole(song.tempo.at[i]);
			out.key("beats");
			out.number(song.tempo.bpm[i]);
			out.close();
		}

		out.ends();
		out.close();

		out.key("rack");
		out.list();
		for (i in 0...Part.COUNT) out.whole(needed.instrument(song.rack[i]));
		out.ends();

		out.key("muted");
		out.list();
		for (i in 0...Part.COUNT) out.flag(song.muted[i]);
		out.ends();

		out.key("soloed");
		out.list();
		for (i in 0...Part.COUNT) out.flag(song.soloed[i]);
		out.ends();

		out.key("volume");
		out.list();
		for (i in 0...Part.COUNT) out.whole(song.volume[i]);
		out.ends();

		out.key("instruments");
		out.list();
		for (instrument in needed.instruments) wroteInstrument(out, instrument, needed);
		out.ends();

		out.key("banks");
		out.list();

		final holding:Array<Int> = [];

		for (bank in song.banks) {
			holding.resize(0);

			for (index in bank.instruments) {
				final at = needed.instrument(index);
				if (at >= 0) holding.push(at);
			}

			if (holding.length == 0) continue;

			out.open();
			out.key("name");
			out.text(bank.name);
			out.key("instruments");
			out.wholes(holding);
			out.close();
		}

		out.ends();

		out.key("samples");
		out.list();

		for (sample in needed.samples) {
			out.open();
			out.key("name");
			out.text(sample.name);
			out.key("rate");
			out.whole(sample.rate);
			out.key("root");
			out.whole(sample.root);
			out.key("loop");
			out.whole(sample.loop);
			out.key("length");
			out.whole(sample.length());
			out.close();
		}

		out.ends();

		out.key("patterns");
		out.list();
		for (pattern in song.patterns) wrotePattern(out, pattern, needed);
		out.ends();

		out.key("tracks");
		out.list();

		for (track in song.tracks) {
			out.open();
			out.key("name");
			out.text(track.name);
			out.key("colour");
			out.whole(track.colour);
			out.key("icon");
			out.whole(track.icon);
			out.key("muted");
			out.flag(track.muted);
			out.key("clips");
			out.list();

			for (clip in track.clips) {
				out.open();
				out.key("pattern");
				out.whole(clip.pattern);
				out.key("at");
				out.whole(clip.at);
				out.key("length");
				out.whole(clip.length);
				out.key("transpose");
				out.whole(clip.transpose);
				out.key("offset");
				out.whole(clip.offset);

				final line = clip.line;

				if (clip.kind != Clip.PATTERN && line != null) {
					final swaps = line.target == Automation.INSTRUMENT;

					out.key("drives");
					out.whole(clip.part);
					out.key("target");
					out.whole(line.target);
					out.key("slot");
					out.whole(line.slot);
					out.key("points");
					out.list();

					for (point in line.points) wrotePoint(out, point, swaps ? needed : null);

					out.ends();
				}

				out.close();
			}

			out.ends();
			out.close();
		}

		out.ends();
		out.close();

		return out.toString();
	}

	/**
		Writes one instrument.

		@param out Where it goes.
		@param instrument The instrument.
	**/
	public static function wroteInstrument(out:Json, instrument:Instrument,
			?needed:Needed):Void {
		out.open();

		out.key("name");
		out.text(instrument.name);

		out.key("kind");
		out.whole(instrument.kind.index());

		if (instrument.from != "") {
			out.key("from");
			out.text(instrument.from);
		}

		out.key("sample");
		out.whole(needed == null ? instrument.sample : needed.sample(instrument.sample));

		out.key("icon");
		out.whole(instrument.icon);

		if (instrument.tags.length > 0) {
			out.key("tags");
			out.list();

			for (tag in instrument.tags) out.text(tag);
			out.ends();
		}

		if (instrument.patch != null) {
			final patch = instrument.patch;

			out.key("patch");
			out.open();

			out.key("algorithm");
			out.whole(patch.algorithm);
			out.key("feedback");
			out.whole(patch.feedback);
			out.key("ams");
			out.whole(patch.ams);
			out.key("pms");
			out.whole(patch.pms);
			out.key("slots");
			out.list();

			for (slot in 0...Patch.SLOTS) {
				out.open();
				out.key("detune");
				out.whole(patch.detune[slot]);
				out.key("multiple");
				out.whole(patch.multiple[slot]);
				out.key("totalLevel");
				out.whole(patch.totalLevel[slot]);
				out.key("keyScale");
				out.whole(patch.keyScale[slot]);
				out.key("attack");
				out.whole(patch.attack[slot]);
				out.key("decay");
				out.whole(patch.decay[slot]);
				out.key("sustain");
				out.whole(patch.sustain[slot]);
				out.key("sustainLevel");
				out.whole(patch.sustainLevel[slot]);
				out.key("release");
				out.whole(patch.release[slot]);
				out.key("ssg");
				out.whole(patch.ssg[slot]);
				out.key("tremolo");
				out.flag(patch.tremolo[slot]);
				out.close();
			}

			out.ends();
			out.close();
		}

		if (instrument.envelope != null) {
			final envelope = instrument.envelope;

			out.key("envelope");
			out.open();
			out.key("steps");
			out.wholes(envelope.steps);
			out.key("loop");
			out.whole(envelope.loop);
			out.key("speed");
			out.whole(envelope.speed);
			out.key("noise");
			out.whole(envelope.noise);
			out.close();
		}

		out.close();
	}

	/**
		Writes one pattern and every lane in it.

		@param out Where it goes.
		@param pattern The pattern.
	**/
	static function wrotePattern(out:Json, pattern:Pattern, needed:Needed):Void {
		out.open();

		out.key("name");
		out.text(pattern.name);
		out.key("colour");
		out.whole(pattern.colour);
		out.key("part");
		out.whole(pattern.part);
		out.key("length");
		out.whole(pattern.length);
		out.key("lanes");
		out.list();

		for (index in 0...Part.COUNT) {
			final lane = pattern.lanes[index];

			out.open();
			out.key("part");
			out.whole(index);
			out.key("notes");
			out.list();

			for (note in lane.notes) {
				out.open();
				out.key("at");
				out.whole(note.at);
				out.key("length");
				out.whole(note.length);
				out.key("pitch");
				out.whole(note.pitch);
				out.key("velocity");
				out.whole(note.velocity);
				out.key("instrument");
				out.whole(needed.instrument(note.instrument));

				if (note.tied) {
					out.key("tied");
					out.flag(true);
				}

				out.close();
			}

			out.ends();
			out.key("automation");
			out.list();

			for (line in lane.automation) {
				final swaps = line.target == Automation.INSTRUMENT;

				out.open();
				out.key("target");
				out.whole(line.target);
				out.key("slot");
				out.whole(line.slot);
				out.key("points");
				out.list();

				for (point in line.points) wrotePoint(out, point, swaps ? needed : null);

				out.ends();
				out.close();
			}

			out.ends();
			out.close();
		}

		out.ends();
		out.close();
	}

	/**
		Reads a song out of a JSON document.

		@param said The document.
		@return The song. A missing field reads as its default rather than faulting.
	**/
	public static function read(said:String):Song {
		final node = Json.parse(said);
		final song = new Song(node.get("name").saying("untitled"));

		for (which in Song.ARTIST...Song.DESCRIPTIONS) {
			song.describes(which, node.get(Song.DESCRIBED[which]).saying(""));
		}

		final lfo = node.get("lfo").whole(0);
		song.lfoOn = (lfo & 8) != 0;
		song.lfoRate = lfo & 7;
		song.mode = node.get("mode").whole(0);

		final stall = node.get("stall");
		song.driving = node.get("driving").truth(false);
		song.drums = node.get("drums").truth(false);
		song.stallAt = stall.at(0).whole(-1);
		song.stallFor = stall.at(1).whole(0);
		song.stallEvery = stall.at(2).real(735);

		final sides = node.get("pan");

		for (i in 0...Part.COUNT) {
			if (i >= sides.length()) break;

			final held = sides.at(i).whole(Song.BOTH);
			song.pan[i] = held < 1 || held > 3 ? Song.BOTH : held;
		}

		final tempo = node.get("tempo");
		song.tempo.resolve(tempo.get("ppqn").whole(96));
		song.tempo.rate = tempo.get("rate").whole(60);

		final changes = tempo.get("changes");
		for (i in 0...changes.length()) {
			final change = changes.at(i);
			song.tempo.set(change.get("at").whole(0), change.get("beats").real(120));
		}

		final rack = node.get("rack");
		final muted = node.get("muted");
		final soloed = node.get("soloed");
		final volume = node.get("volume");

		for (i in 0...Part.COUNT) {
			song.rack[i] = rack.at(i).whole(-1);
			song.muted[i] = muted.at(i).truth(false);
			song.soloed[i] = soloed.at(i).truth(false);
			song.volume[i] = volume.at(i).whole(Song.LOUDEST);
		}

		final instruments = node.get("instruments");
		for (i in 0...instruments.length()) song.instrument(readInstrument(instruments.at(i)));

		final banks = node.get("banks");

		if (banks.length() > 0) {
			song.banks.resize(0);

			for (i in 0...banks.length()) {
				final held = banks.at(i);
				final bank = song.banked(held.get("name").saying(""));

				final named = held.get("instruments");
				for (at in 0...named.length()) bank.add(named.at(at).whole(0));
			}
		}

		final samples = node.get("samples");
		for (i in 0...samples.length()) {
			final held = samples.at(i);
			final sample = new Sample(held.get("name").saying(""), held.get("rate").whole(8000),
				held.get("root").whole(60));

			final many = held.get("length").whole(0);

			sample.loop = held.get("loop").whole(-1);
			sample.hold(new Vector<Int>(many < 0 ? 0 : (many > LONGEST ? LONGEST : many)));
			song.sample(sample);
		}

		final patterns = node.get("patterns");
		for (i in 0...patterns.length()) song.add(readPattern(patterns.at(i)));

		final tracks = node.get("tracks");

		for (i in 0...tracks.length()) {
			final held = tracks.at(i);
			final track = new Track(held.get("name").saying(""));

			track.colour = held.get("colour").whole(-1);
			track.icon = held.get("icon").whole(-1);
			track.muted = held.get("muted").truth(false);

			final clips = held.get("clips");

			for (at in 0...clips.length()) {
				final clip = clips.at(at);
				final made = new Clip(clip.get("pattern").whole(0), clip.get("at").whole(0),
					clip.get("length").whole(0), clip.get("transpose").whole(0),
					clip.get("offset").whole(0));

				final drives = clip.get("drives").whole(-1);

				if (drives >= 0) {
					made.kind = Clip.AUTOMATION;
					made.part = within(drives, Part.COUNT);

					final line = new Automation(
						within(clip.get("target").whole(0), Automation.BASES.length),
						within(clip.get("slot").whole(0), Automation.SLOTS));

					final points = clip.get("points");
					for (index in 0...points.length()) line.add(taken(points.at(index)));

					made.line = line;
				}

				track.add(made);
			}

			song.track(track);
		}

		identified(song, false);

		return song;
	}

	/**
		Works out the identity of every preset in a song of one kind: those that play a recording, or
		those that play none.

		A converter preset's identity reaches every byte it plays, and a file's recordings arrive
		after its document, so the two are taken apart. Taken while the document is read, it hashed a
		buffer of the right length with nothing in it, and every hit read back as a different preset
		from the same hit anywhere else. A document read on its own leaves those presets without one,
		which `Library.same` reads as matching by name and kind.

		@param song The song.
		@param sampled Whether the presets that play a recording are the ones to do.
	**/
	static function identified(song:Song, sampled:Bool):Void {
		for (instrument in song.instruments) {
			if ((instrument.sample >= 0) != sampled) continue;

			instrument.identifies(sampled ? song.sampleAt(instrument.sample) : null);
		}
	}

	/**
		@param node One instrument out of the document.
		@return The instrument.
	**/
	public static function readInstrument(node:Node):Instrument {
		final kind:Part = within(node.get("kind").whole(0), Part.COUNT);
		final instrument = new Instrument(node.get("name").saying(""), kind);

		instrument.sample = node.get("sample").whole(-1);
		instrument.icon = node.get("icon").whole(-1);
		instrument.from = node.get("from").saying("");

		final tagged = node.get("tags");

		for (index in 0...tagged.length()) {
			final said = tagged.at(index).saying("");
			if (said != "") instrument.tags.push(said);
		}


		if (node.has("patch")) {
			final held = node.get("patch");
			final patch = instrument.patch == null ? new Patch() : instrument.patch;

			patch.algorithm = held.get("algorithm").whole(0);
			patch.feedback = held.get("feedback").whole(0);
			patch.ams = held.get("ams").whole(0);
			patch.pms = held.get("pms").whole(0);

			final slots = held.get("slots");

			for (slot in 0...Patch.SLOTS) {
				final one = slots.at(slot);
				patch.detune[slot] = one.get("detune").whole(0);
				patch.multiple[slot] = one.get("multiple").whole(1);
				patch.totalLevel[slot] = one.get("totalLevel").whole(127);
				patch.keyScale[slot] = one.get("keyScale").whole(0);
				patch.attack[slot] = one.get("attack").whole(31);
				patch.decay[slot] = one.get("decay").whole(0);
				patch.sustain[slot] = one.get("sustain").whole(0);
				patch.sustainLevel[slot] = one.get("sustainLevel").whole(0);
				patch.release[slot] = one.get("release").whole(15);
				patch.ssg[slot] = one.get("ssg").whole(0);
				patch.tremolo[slot] = one.get("tremolo").truth(false);
			}

			instrument.patch = patch;
		} else {
			instrument.patch = null;
		}

		if (node.has("envelope")) {
			final held = node.get("envelope");
			final envelope = new Envelope();

			final steps = held.get("steps");
			for (i in 0...steps.length()) envelope.steps.push(steps.at(i).whole(0));

			envelope.loop = held.get("loop").whole(-1);
			envelope.speed = held.get("speed").whole(1);
			envelope.noise = held.get("noise").whole(4);

			instrument.envelope = envelope;
		} else {
			instrument.envelope = null;
		}

		return instrument;
	}

	/**
		Writes one automation point, leaving out whatever is at its default so the file
		stays small.

		@param out Where it goes.
		@param point The point.
		@param needed Where each preset goes in the file, for a point on a preset lane, whose
			value is a preset rather than a number. Null for every other lane.
	**/
	static function wrotePoint(out:Json, point:Point, needed:Null<Needed>):Void {
		out.open();
		out.key("at");
		out.whole(point.at);
		out.key("value");
		out.whole(needed == null ? point.value : needed.instrument(point.value));

		if (point.shape != Automation.HOLD) {
			out.key("shape");
			out.whole(point.shape);
		}

		if (point.tension != 0) {
			out.key("tension");
			out.whole(point.tension);
		}

		if (point.steps != 0) {
			out.key("steps");
			out.whole(point.steps);
		}

		out.close();
	}

	/**
		@param node One point out of the document.
		@return The point.
	**/
	static function taken(node:Node):Point {
		final made = new Point(node.get("at").whole(0), node.get("value").whole(0));

		made.shape = node.get("shape").whole(Automation.HOLD);
		made.tension = node.get("tension").whole(0);
		made.steps = node.get("steps").whole(0);

		return made;
	}

	/**
		@param node One pattern out of the document.
		@return The pattern, with every lane it carried.
	**/
	static function readPattern(node:Node):Pattern {
		final pattern = new Pattern(node.get("name").saying(""), node.get("length").whole(384),
			node.get("colour").whole(-1));

		pattern.part = node.get("part").whole(-1);

		final lanes = node.get("lanes");

		for (i in 0...lanes.length()) {
			final held = lanes.at(i);
			final part = held.get("part").whole(i);
			if (part < 0 || part >= Part.COUNT) continue;

			final lane = pattern.lanes[part];
			final notes = held.get("notes");

			for (at in 0...notes.length()) {
				final note = notes.at(at);
				final made = new Note(note.get("at").whole(0), note.get("length").whole(0),
					note.get("pitch").whole(60), note.get("velocity").whole(100),
					note.get("instrument").whole(-1));

				made.tied = note.get("tied").truth(false);
				lane.add(made);
			}

			final lines = held.get("automation");

			for (at in 0...lines.length()) {
				final line = lines.at(at);
				final automation = new Automation(
					within(line.get("target").whole(0), Automation.BASES.length),
					within(line.get("slot").whole(0), Automation.SLOTS));

				final points = line.get("points");

				for (index in 0...points.length()) {
					automation.add(taken(points.at(index)));
				}

				lane.automation.push(automation);
			}
		}

		return pattern;
	}

	/**
		Writes every sample the song carries into one block.

		A save writes one file per sample instead, and this is what says whether a
		piece has changed since the last one. A piece saved before that carries the
		block rather than the files, so `unbulk` still reads one back.

		@param song The song.
		@return The block.
	**/
	public static function bulk(song:Song):Bytes {
		return bulked(Needed.of(song));
	}

	/**
		Writes the block of samples a file carries.

		@param needed What the file carries and where each recording goes in it.
		@return The block.
	**/
	public static function bulked(needed:Needed):Bytes {
		final chunks = new Chunks();

		for (index in 0...needed.samples.length) {
			final sample = needed.samples[index];
			final body = Bytes.alloc(4 + sample.length());

			body.setInt32(0, index);
			for (i in 0...sample.length()) body.set(4 + i, sample.bytes[i] & 0xFF);

			chunks.add("SMPL", body);
		}

		return chunks.bytes();
	}

	/**
		Reads that block back into the song samples.

		@param song The song, with its samples already declared.
		@param bytes The block.
		@return How many samples were filled in.
	**/
	public static function unbulk(song:Song, bytes:Bytes):Int {
		var taken = 0;

		for (chunk in Chunks.read(bytes)) {
			if (chunk.tag != "SMPL" || chunk.body.length < 4) continue;

			final index = chunk.body.getInt32(0);
			final sample = song.sampleAt(index);
			if (sample == null) continue;

			final held = new Vector<Int>(chunk.body.length - 4);
			for (i in 0...held.length) held[i] = chunk.body.get(4 + i);

			sample.hold(held);
			taken++;
		}

		return taken;
	}

	/**
		@param sample A sample.
		@return Its bytes.
	**/
	public static function sampleBytes(sample:Sample):Bytes {
		final out = Bytes.alloc(sample.length());
		for (i in 0...sample.length()) out.set(i, sample.bytes[i] & 0xFF);
		return out;
	}

	/**
		Writes a song as a folder: the document, and one file per sample.

		@param song The song to write.
		@param into The folder to write into.
	**/
	public static function saveFolder(song:Song, into:String):Void {
		final needed = Needed.of(song);

		tree(into);
		tree(into + "/" + SAMPLES);

		for (index in 0...needed.samples.length) {
			File.saveBytes(into + "/" + SAMPLES + "/" + index + ".pcm",
				sampleBytes(needed.samples[index]));
		}

		sweeps(into + "/" + SAMPLES, needed.samples.length);

		final aside = into + "/" + STRUCTURE + PARTIAL;

		File.saveContent(aside, written(song, needed));
		swaps(aside, into + "/" + STRUCTURE);
	}

	/**
		Removes the sample files a previous save wrote that this one did not, so a
		folder does not keep what is no longer named.

		@param where The sample folder.
		@param kept How many samples the piece now carries.
	**/
	static function sweeps(where:String, kept:Int):Void {
		if (!FileSystem.exists(where)) return;

		var index = kept;

		while (true) {
			final path = where + "/" + index + ".pcm";
			if (!FileSystem.exists(path)) break;

			swept(path);
			index++;
		}
	}

	/**
		Puts a file written beside its name in place of it, which is what makes a save
		either whole or not there at all.

		@param aside The file that was just written.
		@param onto What it replaces.
	**/
	static function swaps(aside:String, onto:String):Void {
		if (FileSystem.exists(onto)) FileSystem.deleteFile(onto);
		FileSystem.rename(aside, onto);
	}

	/**
		Reads a song written as a folder.

		@param from The folder.
		@return The song.
	**/
	public static function openFolder(from:String):Song {
		final song = read(File.getContent(from + "/" + STRUCTURE));
		final packed = from + "/" + BULK;

		if (FileSystem.exists(packed)) unbulk(song, File.getBytes(packed));

		for (index in 0...song.samples.length) {
			final path = from + "/" + SAMPLES + "/" + index + ".pcm";
			if (!FileSystem.exists(path)) continue;

			final bytes = File.getBytes(path);
			final held = new Vector<Int>(bytes.length);
			for (i in 0...bytes.length) held[i] = bytes.get(i);

			song.samples[index].hold(held);
		}

		identified(song, true);

		return song;
	}

	/**
		Writes a song as a single zip.

		@param song The song to write.
		@param into The file to write.
	**/
	public static function savePacked(song:Song, into:String):Void {
		final needed = Needed.of(song);
		final entries = new List<haxe.zip.Entry>();

		entries.add(entry(STRUCTURE, Bytes.ofString(written(song, needed))));

		for (index in 0...needed.samples.length) {
			entries.add(entry(SAMPLES + "/" + index + ".pcm",
				sampleBytes(needed.samples[index])));
		}

		final aside = into + PARTIAL;
		final out = File.write(aside, true);

		try {
			new haxe.zip.Writer(out).write(entries);
		} catch (e:Dynamic) {
			out.close();
			swept(aside);

			throw e;
		}

		out.close();

		swaps(aside, into);
	}

	static inline final PARTIAL = ".part";

	/**
		Deletes one file, and says nothing where it will not go.

		@param where The file.
	**/
	static function swept(where:String):Void {
		try {
			if (FileSystem.exists(where)) FileSystem.deleteFile(where);
		} catch (e:Dynamic) {}
	}

	/**
		Builds one zip entry with a fixed date, so two saves of the same song give the
		same bytes.

		@param name The name inside the archive.
		@param body Its contents.
		@return The entry.
	**/
	static function entry(name:String, body:Bytes):haxe.zip.Entry {
		return {
			fileName: name,
			fileSize: body.length,
			fileTime: EPOCH,
			compressed: false,
			dataSize: body.length,
			data: body,
			crc32: haxe.crypto.Crc32.make(body),
			extraFields: null
		};
	}

	/**
		Reads a song written as a single zip.

		@param from The file.
		@return The song.
	**/
	public static function openPacked(from:String):Song {
		final entries = haxe.zip.Reader.readZip(new haxe.io.BytesInput(File.getBytes(from)));

		var said = "";
		var unpacked = 0;

		final held:Map<String, Bytes> = new Map();

		for (entry in entries) {
			final body = haxe.zip.Reader.unzip(entry);

			unpacked += body.length;

			if (unpacked > UNPACKED) {
				throw "not a project worth opening: it unpacks to more than "
					+ Std.int(UNPACKED / (1024 * 1024)) + " MB";
			}

			if (entry.fileName == STRUCTURE) said = body.toString();
			else held.set(entry.fileName, body);
		}

		final song = read(said);

		if (held.exists(BULK)) unbulk(song, held.get(BULK));

		for (index in 0...song.samples.length) {
			final name = SAMPLES + "/" + index + ".pcm";
			if (!held.exists(name)) continue;

			final bytes = held.get(name);
			final hold = new Vector<Int>(bytes.length);
			for (i in 0...bytes.length) hold[i] = bytes.get(i);

			song.samples[index].hold(hold);
		}

		identified(song, true);

		return song;
	}

	/**
		Writes a song, as a folder or as a zip depending on the path.

		@param song The song to write.
		@param into Where to write it.
	**/
	public static function save(song:Song, into:String):Void {
		if (StringTools.endsWith(into.toLowerCase(), "." + mdd.Config.SUFFIX)) {
			savePacked(song, into);
		} else {
			saveFolder(song, into);
		}
	}

	/**
		Reads a song, from a folder or a zip depending on the path.

		@param from Where to read it from.
		@return The song.
	**/
	public static function open(from:String):Song {
		if (FileSystem.exists(from) && FileSystem.isDirectory(from)) return openFolder(from);
		return openPacked(from);
	}

	/**
		Makes a folder and every folder above it.

		@param path The folder.
	**/
	static function tree(path:String):Void {
		if (FileSystem.exists(path)) return;

		final parent = haxe.io.Path.directory(path);
		if (parent != "" && parent != path) tree(parent);
		FileSystem.createDirectory(path);
	}
}
