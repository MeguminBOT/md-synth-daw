package mdd.gate;

import mdd.format.Tfi;
import mdd.format.Wav;
import mdd.song.Patch;
import mdd.song.Sample;

@:unreflective
class LiftCheck {
	static final BRIEF:Array<String> = [
		"GHZ", "LZ", "MZ", "SLZ", "SYZ", "SBZ", "FZ",
		"EHZ", "CPZ", "ARZ", "CNZ", "HTZ", "MCZ", "OOZ", "MTZ", "SCZ", "WFZ", "DEZ", "HPZ"
	];

	static final ZONE:Array<String> = [
		"Green Hill Zone", "Labyrinth Zone", "Marble Zone", "Star Light Zone",
		"Spring Yard Zone", "Scrap Brain Zone", "Final Zone",
		"Emerald Hill Zone", "Chemical Plant Zone", "Aquatic Ruin Zone", "Casino Night Zone",
		"Hill Top Zone", "Mystic Cave Zone", "Oil Ocean Zone", "Metropolis Zone",
		"Sky Chase Zone", "Wing Fortress Zone", "Death Egg Zone", "Hidden Palace Zone"
	];

	static final STEP:Array<Int> = [9, 11, 0, 2, 4, 5, 7];

	public static function run(args:Array<String>):Int {
		final root = Gate.root;
		final where = root + "/vendor/smps";

		if (!sys.FileSystem.isDirectory(where)) {
			Sys.println("  lift          no vendor/smps to read");
			return 1;
		}

		final into = root + "/assets/presets";
		mdd.host.Paths.make(into);

		for (name in sys.FileSystem.readDirectory(into)) {
			if (name.indexOf(".json") >= 0) sys.FileSystem.deleteFile(into + "/" + name);
		}

		final games = sys.FileSystem.readDirectory(where);
		games.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		var total = 0;
		var banks = 0;

		for (game in games) {
			if (!sys.FileSystem.isDirectory(where + "/" + game)) continue;

			total += banked(where + "/" + game, into, game);
			banks++;
		}

		Sys.println("  lift          " + total + " presets across " + banks + " banks");
		return 0;
	}

	static function banked(where:String, into:String, game:String):Int {
		final patches:Array<Patch> = [];
		final tagged:Array<Array<String>> = [];
		final pitches:Array<Array<Int>> = [];

		var seen = 0;

		final music = where + "/music";

		if (sys.FileSystem.isDirectory(music)) {
			final files = sys.FileSystem.readDirectory(music);
			files.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

			for (one in files) {
				if (one.toLowerCase().indexOf(".asm") < 0) continue;
				seen += voiced(music + "/" + one, titled(one), patches, tagged, pitches);
			}
		}

		final medians:Array<Int> = [];
		final across:Array<Int> = [];

		for (held in pitches) {
			final one = median(held);

			medians.push(one);
			if (one >= 0) across.push(one);
		}

		across.sort(function(one:Int, two:Int):Int return one - two);

		final middle = across.length == 0 ? 0 : across[across.length >> 1];

		final names:Array<String> = [];
		final kinds:Array<String> = [];
		final counts:Array<Int> = [];

		for (index in 0...patches.length) {
			final kind = charactered(patches[index], medians[index], middle);
			final at = kinds.indexOf(kind);

			if (at < 0) {
				kinds.push(kind);
				counts.push(1);
			} else counts[at]++;

			names.push(kind + " " + (at < 0 ? 1 : counts[at]));
		}

		final samples:Array<Sample> = [];
		final struck:Array<Array<String>> = [];

		sampled(where + "/dac", samples, struck);

		sys.io.File.saveContent(into + "/" + filed(game),
			written(game, names, tagged, patches, samples, struck));

		Sys.println("  lift          " + game + ": " + seen + " voices, " + patches.length
			+ " kept, " + samples.length + " samples, median note " + middle);

		return patches.length + samples.length;
	}

	static function sampled(where:String, into:Array<Sample>, tags:Array<Array<String>>):Void {
		if (!sys.FileSystem.isDirectory(where)) return;

		final files = sys.FileSystem.readDirectory(where);
		files.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (one in files) {
			if (one.toLowerCase().indexOf(".wav") < 0) continue;

			final wav = Wav.read(sys.io.File.getBytes(where + "/" + one));
			if (wav.frames < 1 || wav.rate < 1) continue;

			final sample = new Sample(spelt(titled(one)), wav.rate, 60);
			sample.hold(wav.bytes(wav.rate));

			into.push(sample);
			tags.push(sample.length() > 12000 ? ["Voice"] : ["Drums", "Percussion"]);
		}
	}

	static function voiced(file:String, track:String, patches:Array<Patch>,
			tags:Array<Array<String>>, pitches:Array<Array<Int>>):Int {
		final lines = sys.io.File.getContent(file).split("
");
		final held:Array<Int> = [];

		final local:Array<Patch> = [];
		final heard:Array<Array<Int>> = [];

		var patch:Patch = null;
		var mode = "";
		var voice = -1;

		for (raw in lines) {
			final line = trimmed(raw);
			if (line == "" || line.charAt(0) == ";") continue;

			final label = channelled(line);
			if (label != "") mode = label;

			if (starts(line, "smpsSetvoice")) {
				numbers(line, held);
				voice = held.length == 0 ? -1 : held[0];
				continue;
			}

			if (starts(line, "smpsVc")) {
				final field = fielded(line);
				numbers(line, held);

				if (field == "Algorithm") patch = new Patch();
				if (patch == null) continue;

				takes(patch, field, held);

				if (field != "TotalLevel") continue;

				local.push(patch);
				patch = null;

				continue;
			}

			if (mode != "FM" || voice < 0 || !starts(line, "dc.b")) continue;

			while (heard.length <= voice) heard.push([]);
			noted(line, heard[voice]);
		}

		for (index in 0...local.length) {
			var at = -1;
			for (which in 0...patches.length) {
				if (Tfi.same(patches[which], local[index])) at = which;
			}

			if (at < 0) {
				patches.push(local[index]);
				tags.push(labelled(track));
				pitches.push([]);

				at = patches.length - 1;
			} else {
				for (tag in labelled(track)) {
					if (tags[at].indexOf(tag) < 0) tags[at].push(tag);
				}
			}

			if (index < heard.length) for (one in heard[index]) pitches[at].push(one);
		}

		return local.length;
	}

	static function takes(patch:Patch, field:String, held:Array<Int>):Void {
		if (held.length == 0) return;

		switch (field) {
			case "Algorithm": patch.algorithm = held[0] & 7;
			case "Feedback": patch.feedback = held[0] & 7;
			case "Detune": spread(patch.detune, held);
			case "CoarseFreq": spread(patch.multiple, held);
			case "RateScale": spread(patch.keyScale, held);
			case "AttackRate": spread(patch.attack, held);
			case "DecayRate1": spread(patch.decay, held);
			case "DecayRate2": spread(patch.sustain, held);
			case "DecayLevel": spread(patch.sustainLevel, held);
			case "ReleaseRate": spread(patch.release, held);
			case "TotalLevel": spread(patch.totalLevel, held);
			case "AmpMod":
				for (slot in 0...Patch.SLOTS) {
					patch.tremolo[slot] = slot < held.length && held[slot] != 0;
				}
			default:
		}
	}

	static inline function spread(into:haxe.ds.Vector<Int>, held:Array<Int>):Void {
		for (slot in 0...Patch.SLOTS) if (slot < held.length) into[slot] = held[slot];
	}

	static function charactered(patch:Patch, pitch:Int, middle:Int):String {
		var attack = 0;
		var sustainLevel = 0;
		var carriers = 0;

		for (slot in 0...Patch.SLOTS) {
			if (!patch.carries(slot)) continue;

			attack += patch.attack[slot];
			sustainLevel += patch.sustainLevel[slot];

			carriers++;
		}

		if (carriers == 0) return "Voice";

		attack = Std.int(attack / carriers);
		sustainLevel = Std.int(sustainLevel / carriers);

		var ringing = 0;

		for (slot in 0...Patch.SLOTS) {
			if (patch.carries(slot)) continue;
			if (patch.multiple[slot] > ringing) ringing = patch.multiple[slot];
		}

		if (pitch >= 0 && pitch < middle - 12) return "Bass";
		if (attack < 14) return "Pad";
		if (patch.algorithm == 7) return "Organ";
		if (ringing >= 8) return "Bell";
		if (patch.algorithm == 5 || patch.algorithm == 6) return "Brass";
		if (sustainLevel >= 8) return "Pluck";
		if (pitch >= 0 && pitch > middle + 12) return "Chime";

		return "Lead";
	}

	static function noted(line:String, into:Array<Int>):Void {
		var at = 0;

		while (at < line.length) {
			if (line.charCodeAt(at) != 110) {
				at++;
				continue;
			}

			final letter = stepped(line.charCodeAt(at + 1));

			if (letter < 0) {
				at++;
				continue;
			}

			var read = at + 2;
			var semitone = letter;

			if (line.charCodeAt(read) == 98) {
				semitone--;
				read++;
			}

			var sign = 1;

			if (line.charCodeAt(read) == 45) {
				sign = -1;
				read++;
			}

			final digit = line.charCodeAt(read);

			if (digit == null || digit < 48 || digit > 57) {
				at++;
				continue;
			}

			into.push(sign * (digit - 48) * 12 + semitone);
			at = read + 1;
		}
	}

	static inline function stepped(code:Null<Int>):Int {
		if (code == null || code < 65 || code > 71) return -1;
		return STEP[code - 65];
	}

	static function median(held:Array<Int>):Int {
		if (held.length == 0) return -1;

		final sorted = held.copy();
		sorted.sort(function(one:Int, two:Int):Int return one - two);

		return sorted[sorted.length >> 1];
	}

	static function channelled(line:String):String {
		final colon = line.indexOf(":");
		if (colon < 1) return "";

		final under = line.lastIndexOf("_", colon);
		if (under < 0) return "";

		final tail = line.substring(under + 1, colon);

		if (starts(tail, "FM")) return "FM";
		if (starts(tail, "PSG")) return "PSG";
		if (starts(tail, "DAC")) return "DAC";

		return "";
	}

	static function fielded(line:String):String {
		var at = 6;

		while (at < line.length) {
			final code = line.charCodeAt(at);
			if (code == null || code <= 32) break;
			at++;
		}

		return line.substring(6, at);
	}

	static function numbers(line:String, into:Array<Int>):Void {
		into.resize(0);

		var at = 0;

		while (at < line.length) {
			if (line.charCodeAt(at) != 36) {
				at++;
				continue;
			}

			at++;

			var value = 0;
			var got = 0;

			while (at < line.length) {
				final digit = hexed(line.charCodeAt(at));
				if (digit < 0) break;

				value = value * 16 + digit;
				got++;
				at++;
			}

			if (got > 0) into.push(value);
		}
	}

	static inline function hexed(code:Null<Int>):Int {
		if (code == null) return -1;
		if (code >= 48 && code <= 57) return code - 48;
		if (code >= 97 && code <= 102) return code - 87;
		if (code >= 65 && code <= 70) return code - 55;

		return -1;
	}

	static function labelled(track:String):Array<String> {
		final bare = track.length > 3 && track.substr(track.length - 3) == " 2P"
			? track.substring(0, track.length - 3) : track;

		final at = BRIEF.indexOf(bare);
		if (at < 0) return [track];

		return track == bare ? [ZONE[at], bare] : [ZONE[at], bare, track];
	}

	static function trimmed(line:String):String {
		var from = 0;
		var to = line.length;

		while (from < to && line.charCodeAt(from) <= 32) from++;
		while (to > from && line.charCodeAt(to - 1) <= 32) to--;

		return line.substring(from, to);
	}

	static inline function starts(line:String, want:String):Bool {
		return line.length >= want.length && line.substr(0, want.length) == want;
	}

	static function spelt(name:String):String {
		if (name.length == 0) return name;
		return name.charAt(0).toUpperCase() + name.substring(1).toLowerCase();
	}

	static function titled(file:String):String {
		var out = file;

		final dot = out.lastIndexOf(".");
		if (dot > 0) out = out.substring(0, dot);

		final dash = out.indexOf(" - ");
		if (dash >= 0) out = out.substring(dash + 3);

		return out;
	}

	static function filed(name:String):String {
		var out = "";

		for (index in 0...name.length) {
			final one = name.charAt(index).toLowerCase();
			final code = one.charCodeAt(0);

			if (code == null) continue;

			final letter = (code >= 97 && code <= 122) || (code >= 48 && code <= 57);
			out += letter ? one : "-";
		}

		return out + ".json";
	}

	static function written(game:String, names:Array<String>, tags:Array<Array<String>>,
			patches:Array<Patch>, samples:Array<Sample>, struck:Array<Array<String>>):String {
		final out = new StringBuf();

		out.add("{\n  \"name\": \"" + game + "\",\n  \"presets\": [\n");

		for (index in 0...patches.length) {
			out.add("    { \"name\": \"" + names[index] + "\", \"tags\": [");
			out.add(listed(tags[index]));
			out.add("], \"tfi\": \"");

			final held = Tfi.write(patches[index]);
			for (at in 0...held.length) out.add(digits(held.get(at)));

			out.add("\" }");
			if (index + 1 < patches.length || samples.length > 0) out.add(",");

			out.add("\n");
		}

		for (index in 0...samples.length) {
			final sample = samples[index];

			out.add("    { \"name\": \"" + sample.name + "\", \"tags\": [");
			out.add(listed(struck[index]));
			out.add("], \"rate\": " + sample.rate + ", \"root\": " + sample.root + ", \"pcm\": \"");

			final bytes = haxe.io.Bytes.alloc(sample.length());
			for (at in 0...sample.length()) bytes.set(at, sample.bytes[at] & 0xFF);

			out.add(haxe.crypto.Base64.encode(bytes));
			out.add("\" }");

			if (index + 1 < samples.length) out.add(",");
			out.add("\n");
		}

		out.add("  ]\n}\n");
		return out.toString();
	}

	static function listed(tags:Array<String>):String {
		var out = "";

		for (at in 0...tags.length) {
			if (at > 0) out += ", ";
			out += "\"" + tags[at] + "\"";
		}

		return out;
	}

	static function digits(value:Int):String {
		final held = "0123456789abcdef";
		return held.charAt((value >> 4) & 15) + held.charAt(value & 15);
	}
}
