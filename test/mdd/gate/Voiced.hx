package mdd.gate;

import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;
import mdd.song.Track;

/**
	Renders every preset in a bank playing an octave at a time and measures what came out.

		mdd gate voice <into folder> [bank]

	A preset is named for what it does, and the only way to tell whether a name is right is to
	play it. Each one is rendered through the same path an export uses, eight notes from C0 to C7,
	one file per preset, and each note is measured for how fast it arrives, whether it ends on its
	own, and how bright it is.

	What that catches is a name making a claim the sound does not keep: anything called a drum, a
	hit or a stab has to stop by itself, and a preset whose notes are still sounding when the note
	is over is not one of those whatever it is called.
**/
class Voiced {
	/**
		Which notes are played, as MIDI numbers, C0 to C7.
	**/
	static final OCTAVES:Array<Int> = [12, 24, 36, 48, 60, 72, 84, 96];

	/**
		How long each note is held and how far apart they start, in ticks of a 96 tick quarter.
	**/
	static inline final HELD = 96;
	static inline final APART = 192;

	/**
		Names that promise the sound ends on its own.
	**/
	static final PERCUSSIVE:Array<String> = ["kick", "drum", "snare", "hat", "crash", "cymbal",
		"stab", "pluck", "blast", "roll", "shaker", "ride", "china", "tick", "sparkle", "chime",
		"pizzicato", "music box", "bell"];

	/**
		@param args The folder to write into, then the bank to render.
		@return Nought where every preset was rendered.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 1) {
			Sys.println("  voice         voice <into folder> [bank]");
			return 1;
		}

		final folder = args[0];
		final want = args.length > 1 ? args[1] : Library.STARTERS;

		mdd.host.Paths.make(folder);

		final library = Library.embedded();
		final at = library.names.indexOf(want);

		if (at < 0) {
			Sys.println("  voice         no bank called " + want);
			return 1;
		}

		final held = library.instruments[at];

		Sys.println("  voice         " + held.length + " presets of " + want + ", C0 to C7");
		Sys.println("    " + StringTools.rpad("preset", " ", 16) + "  peak  rise  ends   bright"
			+ "  octaves  reading");

		var flagged = 0;

		for (index in 0...held.length) {
			if (sounded(folder, held[index], library.samples[at][index])) flagged++;
		}

		Sys.println("  voice         " + flagged + " of " + held.length
			+ " read as something other than their name says");

		return 0;
	}

	/**
		Renders one preset and says what it measured.

		@param folder Where the file goes.
		@param instrument The preset.
		@param sample What it plays, or null.
		@return Whether its name makes a claim the sound does not keep.
	**/
	static function sounded(folder:String, instrument:Instrument, sample:Null<mdd.song.Sample>):Bool {
		final song = new Song(instrument.name, 96, 120);
		final part = instrument.kind.square() ? Part.Psg1
			: (instrument.kind.noise() ? Part.Noise
			: (instrument.kind.sampled() ? Part.Dac : Part.Fm1));

		final made = instrument.copy();

		if (sample != null) {
			song.sample(sample.copy());
			made.sample = song.samples.length - 1;
		} else {
			made.sample = -1;
		}

		song.instrument(made);
		song.rack[part.index()] = 0;

		final pattern = song.add(new Pattern("octaves", APART * OCTAVES.length));

		for (index in 0...OCTAVES.length) {
			pattern.lane(part).add(new Note(index * APART, HELD, OCTAVES[index], 110, 0));
		}

		song.track(new Track("one")).add(new Clip(0, 0, pattern.length));

		final mixing = new Mixing();

		mixing.rate = 44100;
		mixing.stereo = false;
		mixing.normalise = false;
		mixing.padStart = 0;
		mixing.padEnd = 0.5;

		final out = Mixdown.of(song, mixing);
		final rate = out.rate;
		final step = Math.round(APART / 96.0 * 0.5 * rate);
		final gate = Math.round(HELD / 96.0 * 0.5 * rate);

		var peak = 0.0;
		var rise = 0.0;
		var ends = 0;
		var bright = 0.0;
		var heard = 0;

		for (index in 0...OCTAVES.length) {
			final from = index * step;
			final to = from + gate < out.frames ? from + gate : out.frames;
			if (from >= to) continue;

			var most = 0.0;
			var at = from;

			for (frame in from...to) {
				final value = Math.abs(out.samples[frame]);
				if (value <= most) continue;

				most = value;
				at = frame;
			}

			if (most < 0.002) continue;

			heard++;
			if (most > peak) peak = most;
			rise += (at - from) / rate * 1000;

			var tail = 0.0;
			final last = to - Math.round(rate * 0.02);

			for (frame in (last < from ? from : last)...to) {
				final value = Math.abs(out.samples[frame]);
				if (value > tail) tail = value;
			}

			if (tail > most * 0.5) ends++;

			var crossings = 0;

			for (frame in (from + 1)...to) {
				if ((out.samples[frame - 1] < 0) != (out.samples[frame] < 0)) crossings++;
			}

			bright += crossings / 2 / ((to - from) / rate);
		}

		final named = safely(instrument.name);
		final taken = new haxe.ds.Vector<cpp.Float32>(out.frames);

		for (frame in 0...out.frames) taken[frame] = out.samples[frame];

		sys.io.File.saveBytes(folder + "/" + named + ".wav",
			mdd.format.Wav.write(taken, out.frames, 1, rate));

		final many = heard == 0 ? 1 : heard;
		final holds = ends > OCTAVES.length / 2;
		final claims = percussive(instrument.name);
		final wrong = heard == 0 || (claims && holds);

		Sys.println("    " + StringTools.rpad(instrument.name, " ", 16)
			+ StringTools.lpad("" + Math.round(peak * 100), " ", 5) + "%"
			+ StringTools.lpad("" + Math.round(rise / many), " ", 5) + "ms"
			+ StringTools.lpad(holds ? "holds" : "stops", " ", 7)
			+ StringTools.lpad("" + Math.round(bright / many), " ", 7) + "Hz"
			+ StringTools.lpad(heard + "/" + OCTAVES.length, " ", 8) + "  "
			+ (heard == 0 ? "NOTHING SOUNDED" : (claims && holds
			? "named as a hit but never ends" : "")));

		return wrong;
	}

	/**
		@param name A preset name.
		@return Whether it promises a sound that ends on its own.
	**/
	static function percussive(name:String):Bool {
		final lower = name.toLowerCase();

		for (word in PERCUSSIVE) if (lower.indexOf(word) >= 0) return true;

		return false;
	}

	/**
		@param said A preset name.
		@return It with anything a file name cannot carry replaced by a hyphen.
	**/
	static function safely(said:String):String {
		var out = "";

		for (index in 0...said.length) {
			final code = said.charCodeAt(index);
			if (code == null) continue;

			final fine = code > 31 && code != 34 && code != 42 && code != 47 && code != 58
				&& code != 60 && code != 62 && code != 63 && code != 92 && code != 124;

			out += fine ? said.charAt(index) : "-";
		}

		return out;
	}
}
