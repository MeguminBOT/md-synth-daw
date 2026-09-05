package mdd.song;

import mdd.format.Json;
import mdd.format.Tfi;

@:unreflective
final class Library {
	public final names:Array<String> = [];
	public final instruments:Array<Array<Instrument>> = [];
	public final samples:Array<Array<Null<Sample>>> = [];

	public function new() {}

	public static inline final PREFIX = "bank.";

	public static function embedded():Library {
		final out = new Library();
		final held:Array<String> = [];

		for (name in haxe.Resource.listNames()) {
			if (name.length > PREFIX.length && name.substr(0, PREFIX.length) == PREFIX) {
				held.push(name);
			}
		}

		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		for (name in held) {
			final said = haxe.Resource.getString(name);
			if (said != null) out.reads(said);
		}

		return out;
	}

	public function reads(said:String):Int {
		final node = Json.parse(said);
		if (node == null) return 0;

		final named = node.get("name").saying("");
		if (named == "" || names.indexOf(named) >= 0) return 0;

		final made:Array<Instrument> = [];
		final held:Array<Null<Sample>> = [];

		final presets = node.get("presets");

		for (index in 0...presets.length()) {
			final one = presets.at(index);

			final pcm = one.get("pcm").saying("");
			final patch = pcm == "" ? patched(one.get("tfi").saying("")) : null;

			if (patch == null && pcm == "") continue;

			final sample = pcm == "" ? null : sampled(one.get("name").saying("hit"),
				pcm, one.get("rate").whole(8000), one.get("root").whole(60));

			if (patch == null && sample == null) continue;

			final instrument = new Instrument(one.get("name").saying("patch"),
				patch == null ? Part.Dac : Part.Fm1);

			if (patch != null) instrument.patch = patch;

			instrument.icon = mdd.Icon.NAMES.indexOf(one.get("icon").saying(""));

			final tags = one.get("tags");
			for (at in 0...tags.length()) {
				final tag = tags.at(at).saying("");
				if (tag != "") instrument.tags.push(tag);
			}

			made.push(instrument);
			held.push(sample);
		}

		if (made.length == 0) return 0;

		names.push(named);
		instruments.push(made);
		samples.push(held);

		return made.length;
	}

	public function into(song:Song):Int {
		var many = 0;

		for (at in 0...names.length) {
			var carries = false;
			for (bank in song.banks) {
				if (bank.name == names[at] && bank.instruments.length > 0) carries = true;
			}

			if (carries) continue;

			final bank = song.banked(names[at]);
			final held = instruments[at];

			for (which in 0...held.length) {
				final made = held[which].copy();
				final sample = samples[at][which];

				if (sample != null) {
					song.sample(sample.copy());
					made.sample = song.samples.length - 1;
				}

				song.instrument(made);

				final index = song.instruments.length - 1;

				song.bank(0).remove(index);
				bank.add(index);

				many++;
			}

			bank.kept = true;
		}

		return many;
	}

	public static inline final SUFFIX = ".json";
	public static inline final PATCH = ".tfi";

	public function within(where:String, saved:String):Int {
		if (where == "" || !sys.FileSystem.exists(where)) return 0;
		if (!sys.FileSystem.isDirectory(where)) return 0;

		final held = sys.FileSystem.readDirectory(where);
		held.sort(function(one:String, two:String):Int return one < two ? -1 : 1);

		var many = 0;

		for (name in held) {
			if (name.toLowerCase().indexOf(SUFFIX) < 0) continue;

			try {
				many += reads(sys.io.File.getContent(where + "/" + name));
			} catch (e:Dynamic) {}
		}

		final made:Array<Instrument> = [];

		for (name in held) {
			if (name.toLowerCase().indexOf(PATCH) < 0) continue;

			try {
				final patch = Tfi.read(sys.io.File.getBytes(where + "/" + name));
				if (patch == null) continue;

				final one = new Instrument(stem(name), Part.Fm1);

				one.patch = patch;
				one.icon = mdd.Icon.NAMES.indexOf("synthesizer");

				made.push(one);
			} catch (e:Dynamic) {}
		}

		if (made.length == 0) return many;

		var at = names.indexOf(saved);

		if (at < 0) {
			names.push(saved);
			instruments.push([]);
			samples.push([]);

			at = names.length - 1;
		}

		for (one in made) {
			instruments[at].push(one);
			samples[at].push(null);
		}

		return many + made.length;
	}

	static function stem(name:String):String {
		final dot = name.lastIndexOf(".");
		return dot > 0 ? name.substring(0, dot) : name;
	}

	public static function sampled(named:String, said:String, rate:Int, root:Int):Null<Sample> {
		if (said == "") return null;

		try {
			final bytes = haxe.crypto.Base64.decode(said);
			if (bytes.length < 16) return null;

			final held = new haxe.ds.Vector<Int>(bytes.length);
			for (at in 0...bytes.length) held[at] = bytes.get(at);

			final out = new Sample(named, rate < 1 ? 8000 : rate, root);
			out.hold(held);

			return out;
		} catch (e:Dynamic) {
			return null;
		}
	}

	public static function patched(said:String):Null<Patch> {
		if (said.length < Tfi.BYTES * 2) return null;

		final out = haxe.io.Bytes.alloc(Tfi.BYTES);

		for (at in 0...Tfi.BYTES) {
			out.set(at, digit(said, at * 2) * 16 + digit(said, at * 2 + 1));
		}

		return Tfi.read(out);
	}

	static function digit(said:String, at:Int):Int {
		final code = said.charCodeAt(at);
		if (code == null) return 0;

		if (code >= 48 && code <= 57) return code - 48;
		if (code >= 97 && code <= 102) return code - 87;
		if (code >= 65 && code <= 70) return code - 55;

		return 0;
	}

	public function count():Int {
		var many = 0;
		for (held in instruments) many += held.length;

		return many;
	}
}
