package mdd.song;

import mdd.format.Json;
import mdd.format.Tfi;

/**
	The preset banks: what ships inside the binary, and what a reader has put in their
	own presets folder.

	A library is read once and copied into a song, so a song never depends on a bank
	being installed to open.
**/
@:unreflective
final class Library {
	/**
		The name of each bank.
	**/
	public final names:Array<String> = [];

	/**
		The instruments in each bank.
	**/
	public final instruments:Array<Array<Instrument>> = [];

	/**
		The sample each instrument needs, where it needs one.
	**/
	public final samples:Array<Array<Null<Sample>>> = [];

	public function new() {}

	/**
		What a bank resource is called inside the binary.
	**/
	public static inline final PREFIX = "bank.";

	/**
		Reads every bank compiled into the binary.

		@return The library those banks make up.
	**/
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

	/**
		Reads one bank document and adds it.

		@param said The bank as JSON.
		@return How many instruments it carried.
	**/
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
			final noise = one.get("noise");
			final drawn = noise.get("steps");
			final beats = drawn.length();

			final patch = pcm == "" && beats == 0
				? patched(one.get("tfi").saying("")) : null;

			if (patch == null && pcm == "" && beats == 0) continue;

			final sample = pcm == "" ? null : sampled(one.get("name").saying("hit"),
				pcm, one.get("rate").whole(8000), one.get("root").whole(60));

			if (patch == null && sample == null && beats == 0) continue;

			final where = beats > 0 ? Part.Noise : (patch == null ? Part.Dac : Part.Fm1);
			final instrument = new Instrument(one.get("name").saying("patch"), where);

			if (patch != null) instrument.patch = patch;

			final envelope = instrument.envelope;

			if (beats > 0 && envelope != null) {
				for (step in 0...beats) envelope.steps.push(drawn.at(step).whole(15));

				envelope.turns(Envelope.NOISE, noise.get("mode").whole(7));
				envelope.turns(Envelope.SPEED, noise.get("speed").whole(1));
				envelope.turns(Envelope.LOOP, noise.get("loop").whole(-1));
			}

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

	/**
		Copies every bank into a song, with its own instruments and samples, so nothing
		is shared with the library afterwards.

		@param song The song to copy into.
		@return How many instruments were added.
	**/
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

	/**
		Reads a folder of bank documents and loose patch files, so a reader's own presets
		load beside the shipped ones rather than replacing them.

		@param where The folder to read.
		@param saved The name of the bank loose patches go into.
		@return How many instruments were read.
	**/
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

	/**
		@param name A file name.
		@return It without its suffix.
	**/
	static function stem(name:String):String {
		final dot = name.lastIndexOf(".");
		return dot > 0 ? name.substring(0, dot) : name;
	}

	/**
		Reads a sample out of a bank document.

		@param named What to call it.
		@param said The bytes, base64 encoded.
		@param rate The rate they were written at.
		@param root The MIDI note it sounds at that rate.
		@return The sample, or null where the text was not readable.
	**/
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

	/**
		Writes a bank document, in the layout `reads` takes back.

		Only sampled instruments are written for now, because that is what a kit is and
		what nothing else here could produce: the shipped banks were all written by
		programs outside the application.

		@param named What the bank is called.
		@param made The instruments, in the order they should appear.
		@param held The sample each one plays, in the same order. An entry with no
			sample is passed over.
		@return The document.
	**/
	public static function written(named:String, made:Array<Instrument>,
			held:Array<Null<Sample>>):String {
		final out = new mdd.format.Json();

		out.open();
		out.key("name");
		out.text(named);
		out.key("presets");
		out.list();

		for (index in 0...made.length) {
			final sample = index < held.length ? held[index] : null;
			if (sample == null || sample.length() == 0) continue;

			final one = made[index];

			out.open();

			out.key("name");
			out.text(one.name);

			if (one.icon >= 0 && one.icon < mdd.Icon.NAMES.length) {
				out.key("icon");
				out.text(mdd.Icon.NAMES[one.icon]);
			}

			out.key("tags");
			out.list();
			for (tag in one.tags) out.text(tag);
			out.ends();

			out.key("rate");
			out.whole(sample.rate);

			out.key("root");
			out.whole(sample.root);

			out.key("pcm");
			out.text(coded(sample));

			out.close();
		}

		out.ends();
		out.close();

		return out.toString();
	}

	/**
		@param sample A sample.
		@return Its bytes as base64, which is how a bank document carries them.
	**/
	static function coded(sample:Sample):String {
		final bytes = haxe.io.Bytes.alloc(sample.length());
		for (at in 0...sample.length()) bytes.set(at, sample.bytes[at] & 0xFF);

		return haxe.crypto.Base64.encode(bytes);
	}

	/**
		Reads a patch out of a bank document, in the same layout a TFI file uses.

		@param said The patch as hexadecimal.
		@return The patch, or null where the text was not readable.
	**/
	public static function patched(said:String):Null<Patch> {
		if (said.length < Tfi.BYTES * 2) return null;

		final out = haxe.io.Bytes.alloc(Tfi.BYTES);

		for (at in 0...Tfi.BYTES) {
			out.set(at, digit(said, at * 2) * 16 + digit(said, at * 2 + 1));
		}

		return Tfi.read(out);
	}

	/**
		@param said A string of hexadecimal.
		@param at Which character.
		@return Its value, or -1 where it is not a hexadecimal digit.
	**/
	static function digit(said:String, at:Int):Int {
		final code = said.charCodeAt(at);
		if (code == null) return 0;

		if (code >= 48 && code <= 57) return code - 48;
		if (code >= 97 && code <= 102) return code - 87;
		if (code >= 65 && code <= 70) return code - 55;

		return 0;
	}

	/**
		@return How many instruments the whole library holds.
	**/
	public function count():Int {
		var many = 0;
		for (held in instruments) many += held.length;

		return many;
	}
}
