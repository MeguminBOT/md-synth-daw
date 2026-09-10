package mdd.gate;

import haxe.io.Bytes;
import mdd.format.Gzip;
import mdd.format.Tfi;
import mdd.format.Transcription;
import mdd.format.Vgm;
import mdd.play.Stream;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Patch;
import sys.FileSystem;
import sys.io.File;

@:unreflective

/**
	Gathers a preset bank out of a folder of recordings.

	A patch is the value of the registers at a key on, so what comes out is exactly
	what the chip was set to and nothing is guessed. The names are the part that is
	guessed: a family is worked out from the shape of the envelope and the pitch the
	patch was played at, which is close but is not a person listening to it. The tags
	are exact, and they are what a reader actually searches by, because they name the
	tracks the sound came out of.

	The gate does not run this. It writes an asset, and an asset that rewrote itself on
	every run would show up as churn in a history that should only move when somebody
	decided something.
**/
final class Gathered {
	/**
		Reads every recording in a folder and writes the bank they hold.

		@param args The folder, what to call the bank, where to write it, and where to put
			a table of what each patch measured, which is what the naming was fitted on.
		@return Nought where the bank was written.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 3) {
			Sys.println("  usage: mdd gate gather <folder> <name> <file>");
			return 1;
		}

		final where = args[0];
		final called = args[1];
		final into = args[2];

		if (!FileSystem.isDirectory(where)) {
			Sys.println("  no folder at " + where);
			return 1;
		}

		Sys.println("  gather");
		Sys.println("    reading " + where);

		final held = new Gathered(called);

		for (name in listed(where)) held.takes(where + "/" + name);

		held.writes(into);
		if (args.length > 3) held.measures(args[3]);

		return 0;
	}

	/**
		@param where A folder.
		@return Every recording in it, in name order.
	**/
	static function listed(where:String):Array<String> {
		final out:Array<String> = [];

		for (name in FileSystem.readDirectory(where)) {
			final held = name.toLowerCase();
			if (StringTools.endsWith(held, ".vgm") || StringTools.endsWith(held, ".vgz")) {
				out.push(name);
			}
		}

		out.sort(function(one:String, two:String):Int return one < two ? -1 : 1);
		return out;
	}

	final called:String;

	final keys:Array<String> = [];
	final patches:Array<Patch> = [];
	final tags:Array<Array<String>> = [];
	final pitches:Array<Int> = [];
	final counted:Array<Int> = [];

	var read:Int = 0;
	var seen:Int = 0;

	function new(called:String) {
		this.called = called;
	}

	/**
		Reads one recording and folds what it holds into the bank.

		@param path The file.
	**/
	function takes(path:String):Void {
		final title = titled(path);
		final stream = new Stream(1 << 22);

		var made:Null<Transcription> = null;

		try {
			final vgm = Vgm.read(Gzip.opened(File.getBytes(path)), stream);
			made = Transcription.of(stream, vgm.rate, title);
		} catch (e:Dynamic) {
			Sys.println("    " + title + ": " + e);
			return;
		}

		final song = made.song;
		final total:Array<Int> = [];
		final many:Array<Int> = [];

		for (index in 0...song.instruments.length) {
			total.push(0);
			many.push(0);
		}

		for (pattern in song.patterns) {
			for (which in 0...Part.COUNT) {
				final part:Part = which;
				if (!part.fm()) continue;

				for (note in pattern.lane(part).notes) {
					final at = note.instrument;
					if (at < 0 || at >= total.length) continue;

					total[at] += note.pitch;
					many[at]++;
				}
			}
		}

		var added = 0;

		for (index in 0...song.instruments.length) {
			final instrument = song.instruments[index];
			final patch = instrument.patch;

			if (patch == null || !instrument.kind.fm()) continue;
			if (many[index] < LEAST) continue;

			seen++;
			if (folds(patch, title, Std.int(total[index] / many[index]), many[index])) {
				added++;
			}
		}

		read++;
		Sys.println("    " + StringTools.rpad(title, " ", 42) + added + " new of "
			+ song.instruments.length);
	}

	/**
		How many notes a patch has to sound before it is worth keeping. A driver writes
		a patch it never plays often enough that the bank fills with silence otherwise.
	**/
	static inline final LEAST = 4;

	/**
		Puts a patch in the bank, or adds a tag to the one already there.

		@param patch The patch, as the driver wrote it. What is kept is a copy brought up
			so its loudest carrier sits at full, which is how the shipped banks hold one
			and is what lets the same sound written at two volumes match as one.
		@param title What the recording is called.
		@param pitch The mean pitch it was keyed at.
		@param many How many notes it sounded.
		@return Whether it was one the bank did not already hold.
	**/
	function folds(patch:Patch, title:String, pitch:Int, many:Int):Bool {
		final held = patch.copy();
		held.raises();

		final key = hexed(Tfi.write(held));
		final at = keys.indexOf(key);

		if (at >= 0) {
			for (tag in tagged(title)) {
				if (tags[at].indexOf(tag) < 0) tags[at].push(tag);
			}

			pitches[at] = Std.int((pitches[at] * counted[at] + pitch * many)
				/ (counted[at] + many));

			counted[at] += many;
			return false;
		}

		keys.push(key);
		patches.push(held);
		tags.push(tagged(title));
		pitches.push(pitch);
		counted.push(many);

		return true;
	}

	/**
		@param bytes A patch.
		@return Its bytes as hex, which is how a bank carries one.
	**/
	static function hexed(bytes:Bytes):String {
		final out = new StringBuf();

		for (index in 0...bytes.length) {
			out.add(StringTools.hex(bytes.get(index), 2).toLowerCase());
		}

		return out.toString();
	}

	/**
		@param path A file.
		@return What the track is called, with the leading number taken off.
	**/
	static function titled(path:String):String {
		var held = haxe.io.Path.withoutDirectory(path);
		held = haxe.io.Path.withoutExtension(held);

		final at = held.indexOf(" - ");
		return at < 0 ? held : held.substr(at + 3);
	}

	/**
		@param title What a track is called.
		@return What to tag a sound from it with: the track, and the initials of a zone
			name where it has one, because that is what a reader types.
	**/
	static function tagged(title:String):Array<String> {
		final out = [title];
		final words = title.split(" ");
		final initials = new StringBuf();

		var counted = 0;

		for (word in words) {
			if (word.length == 0) continue;

			final first = word.charAt(0);
			if (first != first.toUpperCase()) continue;

			initials.add(first);
			counted++;

			if (word == "Zone") break;
		}

		final short = initials.toString();
		if (counted >= 3 && title.indexOf("Zone") >= 0 && short != title) out.push(short);

		return out;
	}

	static final FAMILIES:Array<String> = ["Bass", "Organ", "Lead", "Guitar", "Bell",
		"Flute"];

	static final ICONS:Array<String> = ["bass", "pipe", "synthesizer", "guitar",
		"bell", "woodwind"];

	/**
		Works out which family a patch belongs to.

		This is the one guessed part of a bank, and it is worth knowing how far it can be
		trusted. The rules were fitted against the two banks somebody named by ear, and
		measured back against them:

			Sonic the Hedgehog     33 of  54   61 per cent, against 26 for the commonest name
			Sonic the Hedgehog 2   74 of 118   63 per cent, against 34

		So roughly two names in three land where a person would put them. The patches and
		the tags are exact; a name is a starting point, and renaming one is an edit to a
		line of the bank.

		What separates them is how quickly the carriers open, how loud the modulator sits
		against them, and the pitch the patch was actually played at, which is what tells
		a bass from a lead built out of the same envelope.

		@param patch The patch, already brought up to full.
		@param pitch The mean pitch it was keyed at.
		@return Which family, by index into `FAMILIES`.
	**/
	static function family(patch:Patch, pitch:Int):Int {
		var carriers = 0;
		var modulators = 0;

		var attack = 0.0;
		var sustain = 0.0;
		var level = 0.0;
		var multiple = 0.0;

		for (slot in 0...Patch.SLOTS) {
			if (patch.carries(slot)) {
				carriers++;
				attack += patch.attack[slot];
				sustain += patch.sustain[slot];
			} else {
				modulators++;
				level += patch.totalLevel[slot];
				multiple += patch.multiple[slot];
			}
		}

		if (carriers == 0) return FLUTE;

		final opens = attack / carriers;
		final held = sustain / carriers;
		final loud = modulators == 0 ? 0.0 : level / modulators;
		final deep = modulators == 0 ? 0.0 : multiple / modulators;

		if (opens < INSTANT) {
			if (loud < FORWARD) return patch.algorithm >= 5 ? ORGAN : LEAD;
			return held >= LINGERS ? GUITAR : FLUTE;
		}

		if (pitch < LOW) return deep >= FOLDED ? BASS : ORGAN;
		return loud >= BRIGHT ? LEAD : BELL;
	}

	static inline final BASS = 0;
	static inline final ORGAN = 1;
	static inline final LEAD = 2;
	static inline final GUITAR = 3;
	static inline final BELL = 4;
	static inline final FLUTE = 5;

	static inline final INSTANT = 28.0;
	static inline final FORWARD = 23.0;
	static inline final LINGERS = 4.3333;
	static inline final LOW = 65;
	static inline final FOLDED = 0.6667;
	static inline final BRIGHT = 32.5;

	/**
		Writes the bank out, in the shape the shipped ones are written in.

		@param into The file to write.
	**/
	function writes(into:String):Void {
		final counts:Array<Int> = [];
		for (index in 0...FAMILIES.length) counts.push(0);

		final out = new StringBuf();

		out.add("{\n");
		out.add("  \"name\": " + quoted(called) + ",\n");
		out.add("  \"presets\": [\n");

		final order = ordered();

		for (place in 0...order.length) {
			final at = order[place];
			final which = family(patches[at], pitches[at]);

			counts[which]++;

			out.add("    {\"name\": " + quoted(FAMILIES[which] + " " + counts[which])
				+ ", \"icon\": " + quoted(ICONS[which])
				+ ", \"tags\": [");

			for (index in 0...tags[at].length) {
				if (index > 0) out.add(", ");
				out.add(quoted(tags[at][index]));
			}

			out.add("], \"tfi\": " + quoted(keys[at]) + "}");
			out.add(place == order.length - 1 ? "\n" : ",\n");
		}

		out.add("  ]\n");
		out.add("}\n");

		File.saveContent(into, out.toString());

		Sys.println("    " + read + " recordings, " + seen + " patches played, "
			+ keys.length + " kept after matching");

		for (index in 0...FAMILIES.length) {
			if (counts[index] > 0) {
				Sys.println("      " + StringTools.rpad(FAMILIES[index], " ", 10)
					+ counts[index]);
			}
		}

		Sys.println("    wrote " + into);
	}

	/**
		Writes what every patch measured, so the naming can be fitted against a bank
		somebody named by ear rather than guessed at.

		@param into The file to write.
	**/
	function measures(into:String):Void {
		final out = new StringBuf();
		out.add("tfi	pitch	notes	tracks
");

		for (index in 0...keys.length) {
			out.add(keys[index] + "	" + pitches[index] + "	" + counted[index]
				+ "	" + tags[index].length + "
");
		}

		File.saveContent(into, out.toString());
		Sys.println("    wrote " + into);
	}

	/**
		@return The bank in the order it is written: by family, then by how much of the
			soundtrack used it, so the sounds a reader wants first are first.
	**/
	function ordered():Array<Int> {
		final out:Array<Int> = [];
		for (index in 0...keys.length) out.push(index);

		out.sort(function(one:Int, two:Int):Int {
			final first = family(patches[one], pitches[one]);
			final second = family(patches[two], pitches[two]);

			if (first != second) return first - second;
			if (tags[two].length != tags[one].length) {
				return tags[two].length - tags[one].length;
			}

			return counted[two] - counted[one];
		});

		return out;
	}

	/**
		@param said Any text.
		@return It as a JSON string, with what JSON cannot hold plainly escaped.
	**/
	static function quoted(said:String):String {
		final out = new StringBuf();
		out.addChar('"'.code);

		for (index in 0...said.length) {
			final code = said.charCodeAt(index);
			if (code == null) continue;

			if (code == '"'.code || code == '\\'.code) out.addChar('\\'.code);
			out.addChar(code);
		}

		out.addChar('"'.code);
		return out.toString();
	}
}
