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

class Project {
	public static inline final VERSION = 1;
	static inline final STRUCTURE = "project.json";
	static inline final BULK = "chunks/bulk.mdc";
	public static inline final SAMPLES = "samples";

	static final EPOCH:Date = new Date(1980, 0, 1, 0, 0, 0);

	public static function text(song:Song):String {
		final out = new Json();

		out.open();

		out.key("format");
		out.text("mdd");

		out.key("version");
		out.whole(VERSION);

		out.key("name");
		out.text(song.name);

		out.key("author");
		out.text(song.author);

		out.key("lfo");
		out.whole((song.lfoOn ? 8 : 0) | (song.lfoRate & 7));

		out.key("mode");
		out.whole(song.mode);

		out.key("driving");
		out.flag(song.driving);

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
		for (i in 0...Part.COUNT) out.whole(song.rack[i]);
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
		for (instrument in song.instruments) wroteInstrument(out, instrument);
		out.ends();

		out.key("banks");
		out.list();

		for (bank in song.banks) {
			out.open();
			out.key("name");
			out.text(bank.name);
			out.key("kept");
			out.flag(bank.kept);
			out.key("instruments");
			out.wholes(bank.instruments);
			out.close();
		}

		out.ends();

		out.key("samples");
		out.list();

		for (sample in song.samples) {
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
		for (pattern in song.patterns) wrotePattern(out, pattern);
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
					out.key("drives");
					out.whole(clip.part);
					out.key("target");
					out.whole(line.target);
					out.key("slot");
					out.whole(line.slot);
					out.key("points");
					out.list();

					for (point in line.points) written(out, point);

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

	static function wroteInstrument(out:Json, instrument:Instrument):Void {
		out.open();

		out.key("name");
		out.text(instrument.name);

		out.key("kind");
		out.whole(instrument.kind.index());

		out.key("sample");
		out.whole(instrument.sample);

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

	static function wrotePattern(out:Json, pattern:Pattern):Void {
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
				out.whole(note.instrument);

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
				out.open();
				out.key("target");
				out.whole(line.target);
				out.key("slot");
				out.whole(line.slot);
				out.key("points");
				out.list();

				for (point in line.points) written(out, point);

				out.ends();
				out.close();
			}

			out.ends();
			out.close();
		}

		out.ends();
		out.close();
	}

	public static function read(said:String):Song {
		final node = Json.parse(said);
		final song = new Song(node.get("name").saying("untitled"));

		song.author = node.get("author").saying("");

		final lfo = node.get("lfo").whole(0);
		song.lfoOn = (lfo & 8) != 0;
		song.lfoRate = lfo & 7;
		song.mode = node.get("mode").whole(0);

		final stall = node.get("stall");
		song.driving = node.get("driving").truth(false);
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
				final bank = song.banked(held.get("name").saying(""),
					held.get("kept").truth(true));

				final named = held.get("instruments");
				for (at in 0...named.length()) bank.add(named.at(at).whole(0));
			}
		}

		final samples = node.get("samples");
		for (i in 0...samples.length()) {
			final held = samples.at(i);
			final sample = new Sample(held.get("name").saying(""), held.get("rate").whole(8000),
				held.get("root").whole(60));

			sample.loop = held.get("loop").whole(-1);
			sample.hold(new Vector<Int>(held.get("length").whole(0)));
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
					made.part = drives;

					final line = new Automation(clip.get("target").whole(0),
						clip.get("slot").whole(0));

					final points = clip.get("points");
					for (index in 0...points.length()) line.add(taken(points.at(index)));

					made.line = line;
				}

				track.add(made);
			}

			song.track(track);
		}

		return song;
	}

	static function readInstrument(node:Node):Instrument {
		final kind:Part = node.get("kind").whole(0);
		final instrument = new Instrument(node.get("name").saying(""), kind);

		instrument.sample = node.get("sample").whole(-1);
		instrument.icon = node.get("icon").whole(-1);

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

	static function written(out:Json, point:Point):Void {
		out.open();
		out.key("at");
		out.whole(point.at);
		out.key("value");
		out.whole(point.value);

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

	static function taken(node:Node):Point {
		final made = new Point(node.get("at").whole(0), node.get("value").whole(0));

		made.shape = node.get("shape").whole(Automation.HOLD);
		made.tension = node.get("tension").whole(0);
		made.steps = node.get("steps").whole(0);

		return made;
	}

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
				final automation = new Automation(line.get("target").whole(0),
					line.get("slot").whole(0));

				final points = line.get("points");

				for (index in 0...points.length()) {
					automation.add(taken(points.at(index)));
				}

				lane.automation.push(automation);
			}
		}

		return pattern;
	}

	public static function bulk(song:Song):Bytes {
		final chunks = new Chunks();

		for (index in 0...song.samples.length) {
			final sample = song.samples[index];
			final body = Bytes.alloc(4 + sample.length());

			body.setInt32(0, index);
			for (i in 0...sample.length()) body.set(4 + i, sample.bytes[i] & 0xFF);

			chunks.add("SMPL", body);
		}

		return chunks.bytes();
	}

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

	public static function sampleBytes(sample:Sample):Bytes {
		final out = Bytes.alloc(sample.length());
		for (i in 0...sample.length()) out.set(i, sample.bytes[i] & 0xFF);
		return out;
	}

	public static function saveFolder(song:Song, into:String):Void {
		tree(into);
		tree(into + "/chunks");
		tree(into + "/" + SAMPLES);

		File.saveContent(into + "/" + STRUCTURE, text(song));
		File.saveBytes(into + "/" + BULK, bulk(song));

		for (index in 0...song.samples.length) {
			File.saveBytes(into + "/" + SAMPLES + "/" + index + ".pcm",
				sampleBytes(song.samples[index]));
		}
	}

	public static function openFolder(from:String):Song {
		final song = read(File.getContent(from + "/" + STRUCTURE));

		for (index in 0...song.samples.length) {
			final path = from + "/" + SAMPLES + "/" + index + ".pcm";
			if (!FileSystem.exists(path)) continue;

			final bytes = File.getBytes(path);
			final held = new Vector<Int>(bytes.length);
			for (i in 0...bytes.length) held[i] = bytes.get(i);

			song.samples[index].hold(held);
		}

		return song;
	}

	public static function savePacked(song:Song, into:String):Void {
		final entries = new List<haxe.zip.Entry>();

		entries.add(entry(STRUCTURE, Bytes.ofString(text(song))));
		entries.add(entry(BULK, bulk(song)));

		for (index in 0...song.samples.length) {
			entries.add(entry(SAMPLES + "/" + index + ".pcm", sampleBytes(song.samples[index])));
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

		if (FileSystem.exists(into)) FileSystem.deleteFile(into);
		FileSystem.rename(aside, into);
	}

	static inline final PARTIAL = ".part";

	static function swept(where:String):Void {
		try {
			if (FileSystem.exists(where)) FileSystem.deleteFile(where);
		} catch (e:Dynamic) {}
	}

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

	public static function openPacked(from:String):Song {
		final entries = haxe.zip.Reader.readZip(new haxe.io.BytesInput(File.getBytes(from)));

		var said = "";
		final held:Map<String, Bytes> = new Map();

		for (entry in entries) {
			final body = haxe.zip.Reader.unzip(entry);
			if (entry.fileName == STRUCTURE) said = body.toString();
			else held.set(entry.fileName, body);
		}

		final song = read(said);

		for (index in 0...song.samples.length) {
			final name = SAMPLES + "/" + index + ".pcm";
			if (!held.exists(name)) continue;

			final bytes = held.get(name);
			final hold = new Vector<Int>(bytes.length);
			for (i in 0...bytes.length) hold[i] = bytes.get(i);

			song.samples[index].hold(hold);
		}

		return song;
	}

	public static function save(song:Song, into:String):Void {
		if (StringTools.endsWith(into.toLowerCase(), "." + mdd.Config.SUFFIX)) {
			savePacked(song, into);
		} else {
			saveFolder(song, into);
		}
	}

	public static function open(from:String):Song {
		if (FileSystem.exists(from) && FileSystem.isDirectory(from)) return openFolder(from);
		return openPacked(from);
	}

	static function tree(path:String):Void {
		if (FileSystem.exists(path)) return;

		final parent = haxe.io.Path.directory(path);
		if (parent != "" && parent != path) tree(parent);
		FileSystem.createDirectory(path);
	}
}
