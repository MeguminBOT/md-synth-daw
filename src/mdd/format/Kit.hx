package mdd.format;

import haxe.ds.Vector;
import mdd.song.Instrument;
import mdd.song.Part;

@:unreflective

/**
	A folder of recordings on its way to being a bank the converter can play.

	The whole of it is here rather than in the sheet that drives it, so what a kit
	becomes can be measured without a window open. Nothing is written until `written`
	is asked for.
**/
final class Kit {
	/**
		What the bank is called.
	**/
	public var name:String = "";

	/**
		The rate every hit is converted at unless it says otherwise.
	**/
	public var rate:Int = 11025;

	/**
		What every hit in it is tagged with, separated by commas. Empty tags the kit as
		drums, which is what a kit usually is.
	**/
	public var tags:String = "";

	/**
		Whether the keys are the ones general MIDI puts drums on. Off lays the hits out
		one after another from `BASE` instead, which is what a kit of anything other
		than drums wants.
	**/
	public var drums:Bool = true;

	/**
		The hits, in the order their names read until their keys are detected, and in key
		order from then on.
	**/
	public final slots:Array<Slot> = [];

	/**
		The settings every hit starts from.
	**/
	public final sampling:Sampling = new Sampling();

	/**
		Where a kit that is not drums starts laying its hits out.
	**/
	public static inline final BASE = 36;

	/**
		Builds an empty kit.
	**/
	public function new() {}

	/**
		Reads every wave file in a folder into slots, measuring each one.

		@param where The folder.
		@return How many were read.
	**/
	public function reads(where:String):Int {
		if (!sys.FileSystem.exists(where) || !sys.FileSystem.isDirectory(where)) return 0;

		final held = sys.FileSystem.readDirectory(where);
		held.sort(function(one:String, two:String):Int return mdd.Names.inOrder(one, two));

		var many = 0;

		for (one in held) {
			if (!StringTools.endsWith(one.toLowerCase(), ".wav")) continue;
			if (adds(where + "/" + one, titled(one))) many++;
		}

		if (name == "") name = titled(where);

		return many;
	}

	/**
		Reads one file into a slot and measures it.

		@param path The file.
		@param called What to call the hit.
		@return Whether it read.
	**/
	public function adds(path:String, called:String):Bool {
		var wav:Null<Wav> = null;

		try {
			wav = Wav.read(sys.io.File.getBytes(path));
		} catch (e:Dynamic) {
			return false;
		}

		if (wav == null || wav.frames == 0 || wav.rate < 1) return false;

		final slot = new Slot(path, called);
		final held = wav.mono();

		slot.was = wav.rate;
		slot.seconds = held.length / wav.rate;
		slot.peak = loudest(held);
		slot.pitch = pitched(held, wav.rate);
		slot.rings = ringing(held, wav.rate);

		slots.push(slot);
		return true;
	}

	/**
		Puts every hit on a key, from what it is called and from what was measured about it.

		A name that spells a note, `A#3`, `Eb4` or the `C-4` a tracker writes, is taken at its
		word in either mode, because a pack that names its keys has already said where each
		one goes. Middle C is `C4`, key 60, which is how the sheet spells a key back.

		The rest are worked out. With drums on, a name is read for its family, and what decides
		the order within one is whether the measurement defines the role or merely describes
		it. A hat that chokes is the closed one and a hat that rings is the open one, whatever
		either file is called, so those go by ring. Toms are ordered by pitch, so a fill runs
		low to high however they were numbered. A first crash is not defined by lasting longer
		than a second one, so those keep the order their names put them in. With drums off,
		they are laid one after another from `BASE` in the order their names read, stepping
		over any key a named hit already holds.

		The hits are left in key order, so the list reads low to high.

		@return How many were placed.
	**/
	public function detects():Int {
		final rest:Array<Slot> = [];
		final held:Array<Int> = [];

		var many = 0;

		for (slot in slots) {
			if (!slot.taken) continue;

			final key = noteIn(slot.name);

			if (key < 0) {
				rest.push(slot);
				continue;
			}

			slot.root = key;
			slot.icon = mdd.Icon.NAMES.indexOf(drums ? ICONS[familyOf(slot.name)] : "wave-saw");

			held.push(key);
			many++;
		}

		many += drums ? families(rest) : laid(rest, held);

		slots.sort(function(one:Slot, two:Slot):Int {
			if (one.root != two.root) return one.root - two.root;
			return mdd.Names.inOrder(one.name, two.name);
		});

		return many;
	}

	/**
		Puts hits on the keys general MIDI gives their family.

		@param held The hits whose names spell no note.
		@return How many were placed.
	**/
	static function families(held:Array<Slot>):Int {
		final sorted:Array<Array<Slot>> = [];
		for (index in 0...FAMILIES) sorted.push([]);

		for (slot in held) sorted[familyOf(slot.name)].push(slot);

		var many = 0;

		many += placed(sorted[HAT],
			function(one:Slot, two:Slot):Int return byRinging(one, two),
			sorted[HAT].length == 2 ? HAT_PAIR : HAT_KEYS, ICONS[HAT]);
		many += placed(sorted[TOM],
			function(one:Slot, two:Slot):Int return byPitch(one, two), TOM_KEYS, ICONS[TOM]);
		many += placed(sorted[SNARE],
			function(one:Slot, two:Slot):Int return byNamed(one, two), SNARE_KEYS, ICONS[SNARE]);
		many += placed(sorted[CRASH],
			function(one:Slot, two:Slot):Int return byNamed(one, two), CRASH_KEYS, ICONS[CRASH]);
		many += placed(sorted[RIDE],
			function(one:Slot, two:Slot):Int return byNamed(one, two), RIDE_KEYS, ICONS[RIDE]);
		many += placed(sorted[KICK],
			function(one:Slot, two:Slot):Int return byNamed(one, two), KICK_KEYS, ICONS[KICK]);
		many += placed(sorted[CLAP],
			function(one:Slot, two:Slot):Int return byNamed(one, two), CLAP_KEYS, ICONS[CLAP]);
		many += placed(sorted[BELL],
			function(one:Slot, two:Slot):Int return byNamed(one, two), BELL_KEYS, ICONS[BELL]);
		many += placed(sorted[REST],
			function(one:Slot, two:Slot):Int return byNamed(one, two), REST_KEYS, ICONS[REST]);

		return many;
	}

	/**
		Lays hits out one key after another from `BASE`, in the order their names read.

		@param rest The hits whose names spell no note.
		@param held The keys named hits already hold, which are stepped over.
		@return How many were placed.
	**/
	static function laid(rest:Array<Slot>, held:Array<Int>):Int {
		rest.sort(function(one:Slot, two:Slot):Int return mdd.Names.inOrder(one.name, two.name));

		final drawn = mdd.Icon.NAMES.indexOf("wave-saw");
		var at = BASE;

		for (slot in rest) {
			while (at < 127 && held.indexOf(at) >= 0) at++;

			slot.root = at > 127 ? 127 : at;
			slot.icon = drawn;

			at++;
		}

		return rest.length;
	}

	/**
		Converts every hit that is being taken.

		@return How many were converted.
	**/
	public function converts():Int {
		var many = 0;

		for (slot in slots) {
			slot.made = null;
			if (!slot.taken) continue;

			var wav:Null<Wav> = null;

			try {
				wav = Wav.read(sys.io.File.getBytes(slot.path));
			} catch (e:Dynamic) {
				continue;
			}

			if (wav == null || wav.frames == 0) continue;

			final held = sampling.copy();

			held.rate = slot.rate > 0 ? slot.rate : rate;
			held.cap = slot.cap;

			final made = held.takes(wav.mono(), wav.rate, slot.name);
			made.root = slot.root < 0 ? 60 : slot.root;

			slot.made = made;
			many++;
		}

		return many;
	}

	/**
		@return What the kit comes to, in bytes, counting only what is being taken and
			has been converted.
	**/
	public function bytes():Int {
		var many = 0;
		for (slot in slots) many += slot.bytes();

		return many;
	}

	/**
		@return How many hits are being taken.
	**/
	public function taken():Int {
		var many = 0;
		for (slot in slots) if (slot.taken) many++;

		return many;
	}

	/**
		@return What every hit is tagged with, with the blanks and the spaces around each
			one taken off. Drums where nothing was said.
	**/
	public function tagged():Array<String> {
		final out:Array<String> = [];

		for (one in tags.split(",")) {
			final held = StringTools.trim(one);
			if (held != "" && out.indexOf(held) < 0) out.push(held);
		}

		if (out.length == 0) out.push("Drums");

		return out;
	}

	/**
		@return Every hit that was converted, as a bank, or null where nothing was.
	**/
	public function banked():Null<mdd.format.Banked> {
		final out = new mdd.format.Banked();

		out.name = name == "" ? "Kit" : name;

		for (slot in slots) {
			final sample = slot.made;
			if (!slot.taken || sample == null || sample.length() == 0) continue;

			final one = new Instrument(slot.name, Part.Dac);

			one.icon = slot.icon;

			for (tag in tagged()) one.tags.push(tag);

			out.add(one, sample);
		}

		return out.presets.length == 0 ? null : out;
	}

	/**
		@return The bank document, which is empty where nothing was converted. This is what the
			shipped banks are edited as; what the application writes into a reader's own presets
			folder is records.
	**/
	public function written():String {
		final held = banked();
		if (held == null) return "";

		return mdd.song.Library.written(held.name, held.presets, held.samples);
	}

	static inline final KICK = 0;
	static inline final SNARE = 1;
	static inline final TOM = 2;
	static inline final HAT = 3;
	static inline final CRASH = 4;
	static inline final RIDE = 5;
	static inline final CLAP = 6;
	static inline final BELL = 7;
	static inline final REST = 8;
	static inline final FAMILIES = 9;

	static final KICK_KEYS:Array<Int> = [36, 35];
	static final SNARE_KEYS:Array<Int> = [38, 40];
	static final TOM_KEYS:Array<Int> = [41, 43, 45, 47, 48, 50];
	/**
		Closed, pedal and open, shortest ringing first.
	**/
	static final HAT_KEYS:Array<Int> = [42, 44, 46];

	/**
		Where there are only two, they are closed and open: a kit with one pedal hat and
		no open one is not a kit anybody ships.
	**/
	static final HAT_PAIR:Array<Int> = [42, 46];
	static final CRASH_KEYS:Array<Int> = [49, 57, 55];
	static final RIDE_KEYS:Array<Int> = [51, 59, 53];
	static final CLAP_KEYS:Array<Int> = [39];
	static final BELL_KEYS:Array<Int> = [56, 54];
	static final REST_KEYS:Array<Int> = [60, 61, 62, 63, 64, 65, 66, 67, 68, 69];

	/**
		What each family is drawn with, in the order the families are numbered.
	**/
	static final ICONS:Array<String> = ["kick", "snare", "tom", "hi-hat", "cymbal", "cymbal",
		"clap", "idiophone", "wave-saw"];

	/**
		How far above C each letter sits, in the order `LETTERS` spells them.
	**/
	static final STEPS:Array<Int> = [0, 2, 4, 5, 7, 9, 11];

	static inline final LETTERS = "CDEFGAB";

	/**
		@param called What a hit is called.
		@return Which family that name reads as.
	**/
	public static function familyOf(called:String):Int {
		final held = called.toLowerCase();

		if (has(held, "kick") || has(held, "bass drum") || has(held, "bd")) return KICK;
		if (has(held, "hat") || has(held, "hh")) return HAT;
		if (has(held, "crash") || has(held, "splash") || has(held, "china")) return CRASH;
		if (has(held, "ride")) return RIDE;
		if (has(held, "clap")) return CLAP;
		if (has(held, "cowbell") || has(held, "bell") || has(held, "tambourine")) return BELL;
		if (has(held, "tom")) return TOM;
		if (has(held, "snare") || has(held, "rim") || has(held, "side")
			|| has(held, "sd")) return SNARE;

		return REST;
	}

	static inline function has(held:String, want:String):Bool {
		return held.indexOf(want) >= 0;
	}

	/**
		Puts one family on its keys, in whichever order that family is decided by.

		@param held The hits in it.
		@param order What to sort them by.
		@param keys The keys they go on, in order.
		@param icon What to draw them with.
		@return How many were placed.
	**/
	static function placed(held:Array<Slot>, order:Slot -> Slot -> Int, keys:Array<Int>,
			icon:String):Int {
		if (held.length == 0) return 0;

		held.sort(function(one:Slot, two:Slot):Int return order(one, two));

		final drawn = mdd.Icon.NAMES.indexOf(icon);
		var many = 0;

		for (index in 0...held.length) {
			held[index].root = index < keys.length ? keys[index]
				: keys[keys.length - 1] + (index - keys.length + 1);
			held[index].icon = drawn;

			many++;
		}

		return many;
	}

	static function byRinging(one:Slot, two:Slot):Int {
		final apart = one.rings - two.rings;
		return apart < 0 ? -1 : (apart > 0 ? 1 : 0);
	}

	static function byPitch(one:Slot, two:Slot):Int {
		final apart = one.pitch - two.pitch;
		return apart < 0 ? -1 : (apart > 0 ? 1 : 0);
	}

	static function byNamed(one:Slot, two:Slot):Int {
		return mdd.Names.inOrder(one.name, two.name);
	}

	/**
		The key a name spells, where it spells one.

		A note is a letter from A to G, then a sharp, a flat or the dash a tracker writes, then
		one octave digit, standing apart from any letter or digit on either side, so neither
		`BD2` nor `Tom 1` reads as a note. The sharp and flat signs are read as `#` and `b`.
		Where a name spells more than one, the last is taken, since a name puts the instrument
		first. Middle C is `C4`.

		@param called What a hit is called.
		@return The key, or -1 where the name spells none or spells one outside the MIDI range.
	**/
	public static function noteIn(called:String):Int {
		final held = StringTools.replace(StringTools.replace(called, "♯", "#"), "♭", "b");
		final note = ~/(?:^|[^A-Za-z0-9])([A-Ga-g])([#b-]?)([0-9])(?![A-Za-z0-9])/;

		var found = -1;
		var from = 0;

		while (from < held.length && note.matchSub(held, from)) {
			final where = note.matchedPos();
			final letter = LETTERS.indexOf(note.matched(1).toUpperCase());
			final mark = note.matched(2);
			final octave:Int = Std.parseInt(note.matched(3));

			var key = (octave + 1) * 12 + STEPS[letter];

			if (mark == "#") key++;
			else if (mark == "b") key--;

			if (key >= 0 && key <= 127) found = key;

			from = where.pos + where.len;
		}

		return found;
	}

	/**
		@param path A file or folder path.
		@return Its last part with any suffix taken off.
	**/
	public static function titled(path:String):String {
		var held = StringTools.replace(path, "\\", "/");

		while (StringTools.endsWith(held, "/")) held = held.substr(0, held.length - 1);

		final cut = held.lastIndexOf("/");
		if (cut >= 0) held = held.substr(cut + 1);

		final dot = held.lastIndexOf(".");
		return dot > 0 ? held.substr(0, dot) : held;
	}

	/**
		Where a hit sits, by asking the recording directly at every frequency worth
		asking about rather than building a whole spectrum for four hundred of them.

		@param held The audio.
		@param rate The rate it is at.
		@return The loudest frequency between 40 and 500 Hz, or nought where there is
			not enough to read. The reading is shaped first, because a run cut square
			at both ends spreads every tone it holds across its neighbours and a low
			drum then reads as one of its own harmonics.
	**/
	static function pitched(held:Vector<Float>, rate:Int):Float {
		final many = held.length < Std.int(rate * 0.25) ? held.length : Std.int(rate * 0.25);
		if (many < 64) return 0;

		var best = 0.0;
		var where = 0.0;

		var hertz = 40.0;

		while (hertz <= 500) {
			final turn = 2 * Math.PI * hertz / rate;

			var real = 0.0;
			var made = 0.0;

			for (index in 0...many) {
				final at = turn * index;
				final shape = 0.5 - 0.5 * Math.cos(2 * Math.PI * index / (many - 1));
				final one = held[index] * shape;

				real += one * Math.cos(at);
				made += one * Math.sin(at);
			}

			final size = real * real + made * made;

			if (size > best) {
				best = size;
				where = hertz;
			}

			hertz += 2;
		}

		return where;
	}

	/**
		@param held The audio.
		@param rate The rate it is at.
		@return How long it takes to fall thirty decibels below its loudest, in seconds.
	**/
	static function ringing(held:Vector<Float>, rate:Int):Float {
		final peak = loudest(held);
		if (peak <= 0) return 0;

		final over = peak * 0.0316;

		var last = held.length - 1;
		while (last > 0 && size(held[last]) <= over) last--;

		return last / rate;
	}

	static inline function size(value:Float):Float {
		return value < 0 ? -value : value;
	}

	static function loudest(held:Vector<Float>):Float {
		var most = 0.0;

		for (index in 0...held.length) {
			final one = size(held[index]);
			if (one > most) most = one;
		}

		return most;
	}
}
