package mdd.gate;

import haxe.io.Bytes;
import sys.io.File;

@:unreflective

/**
	Builds a drum kit for the converter out of nothing but arithmetic.

	Every hit here is synthesised rather than recorded: a swept sine for a drum, a
	shaped burst of noise for a cymbal, two squares for a bell. That is how the drums on
	this machine were made in the first place, and it is the only way to ship a kit with
	no question hanging over where the audio came from. Nothing is sampled from anything
	and nothing is borrowed.

	The noise is drawn from a counter with a fixed seed, so the same bank comes out byte
	for byte on every run and a rebuild is not a change.

	The gate does not run this. It writes an asset, and an asset that rewrote itself on
	every run would show up as churn in a history that should only move when somebody
	decided something.
**/
final class Kitted {
	/**
		The rate the hits are written at, in hertz.

		A driver on the real machine wrote the converter somewhere between eight and
		sixteen kilohertz, and this sits in the middle of that: enough for a cymbal to
		keep its edge without spending bytes a drum cannot hear.
	**/
	static inline final RATE = 11025;

	/**
		Writes the kit.

		@param args Where to write it.
		@return Nought where the bank was written.
	**/
	public static function run(args:Array<String>):Int {
		if (args.length < 1) {
			Sys.println("  usage: mdd gate kit <file>");
			return 1;
		}

		Sys.println("  kit");

		final out = new StringBuf();

		out.add("{\n");
		out.add("  \"name\": \"Drum Kit\",\n");
		out.add("  \"presets\": [\n");

		final lines:Array<String> = [];

		lines.push(written("Kick", "kick", 36, kicked()));
		lines.push(written("Rim", "snare", 37, rimmed()));
		lines.push(written("Snare", "snare", 38, snared()));
		lines.push(written("Clap", "clap", 39, clapped()));
		lines.push(written("Tom low", "tom", 41, tommed(98)));
		lines.push(written("Hat closed", "hi-hat", 42, hatted(0.045, 0.9)));
		lines.push(written("Tom mid", "tom", 45, tommed(147)));
		lines.push(written("Hat pedal", "hi-hat", 44, hatted(0.075, 0.8)));
		lines.push(written("Hat open", "hi-hat", 46, hatted(0.32, 0.75)));
		lines.push(written("Tom high", "tom", 48, tommed(220)));
		lines.push(written("Crash", "cymbal", 49, crashed(0.85, 0)));
		lines.push(written("Ride", "cymbal", 51, crashed(0.55, 520)));
		lines.push(written("Cowbell", "idiophone", 56, belled()));

		for (index in 0...lines.length) {
			out.add("    " + lines[index]);
			out.add(index == lines.length - 1 ? "\n" : ",\n");
		}

		out.add("  ]\n");
		out.add("}\n");

		File.saveContent(args[0], out.toString());

		Sys.println("    " + lines.length + " hits, " + total + " bytes at " + RATE
			+ " Hz");
		Sys.println("    wrote " + args[0]);

		return 0;
	}

	static var total:Int = 0;

	/**
		Turns one hit into the line a bank carries it on.

		@param name What to call it.
		@param icon Which icon it takes.
		@param root The note it answers to, which is where general MIDI puts that drum.
		@param held The hit, from minus one to one.
		@return The line.
	**/
	static function written(name:String, icon:String, root:Int,
			held:Array<Float>):String {
		final bytes = eight(held);
		total += bytes.length;

		return "{\"name\": \"" + name + "\", \"icon\": \"" + icon
			+ "\", \"tags\": [\"Drums\", \"Percussion\"], \"rate\": " + RATE
			+ ", \"root\": " + root + ", \"pcm\": \""
			+ haxe.crypto.Base64.encode(bytes) + "\"}";
	}

	/**
		Brings a hit up to full and writes it as the unsigned bytes the converter takes.

		@param held The hit, from minus one to one.
		@return Its bytes, centred on 128.
	**/
	static function eight(held:Array<Float>):Bytes {
		var most = 0.0;

		for (value in held) {
			final much = value < 0 ? -value : value;
			if (much > most) most = much;
		}

		final gain = most <= 0 ? 0.0 : 127.0 / most;
		final out = Bytes.alloc(held.length);

		for (index in 0...held.length) {
			final value = Math.round(held[index] * gain) + 128;
			out.set(index, value < 0 ? 0 : (value > 255 ? 255 : value));
		}

		return out;
	}

	/**
		@param seconds How long.
		@return How many samples that is.
	**/
	static inline function many(seconds:Float):Int {
		return Std.int(RATE * seconds);
	}

	/**
		@param index Which sample.
		@param seconds How long the fall takes to reach a thousandth.
		@return How loud the hit is there, from one down to nothing.
	**/
	static inline function falls(index:Int, seconds:Float):Float {
		return Math.exp(-6.9 * (index / RATE) / seconds);
	}

	var seed:Int = 0;

	static var noise:Int = 0;

	/**
		@return The next noise sample, from minus one to one. It comes from a counter with
			a fixed seed rather than anything random, so the bank is the same every run.
	**/
	static function hiss():Float {
		noise = (noise * 1103515245 + 12345) & 0x3FFFFFFF;
		return (noise >> 14 & 0xFFFF) / 32768.0 - 1.0;
	}

	/**
		Starts the noise again, so a hit does not depend on what was built before it.
	**/
	static function fresh():Void {
		noise = 0x2F19;
	}

	/**
		@return A kick: a sine falling from a slap to a thump, with a click on the front
			so it carries through a mix that has no room at the bottom.
	**/
	static function kicked():Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(0.22);

		var phase = 0.0;

		for (index in 0...length) {
			final at = index / RATE;
			final hz = 48 + 90 * Math.exp(-at / 0.028);

			phase += 2 * Math.PI * hz / RATE;

			var value = Math.sin(phase) * falls(index, 0.20);
			if (index < many(0.004)) value += hiss() * 0.5 * falls(index, 0.003);

			held.push(value);
		}

		return held;
	}

	/**
		@return A snare: two tones for the drum and a long burst of noise for the wires
			under it.
	**/
	static function snared():Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(0.18);

		for (index in 0...length) {
			final at = index / RATE;

			final body = (Math.sin(2 * Math.PI * 185 * at)
				+ Math.sin(2 * Math.PI * 331 * at) * 0.7) * falls(index, 0.085) * 0.5;

			held.push(body + hiss() * falls(index, 0.16) * 0.65);
		}

		return held;
	}

	/**
		@param hz What it is tuned to.
		@return A tom: a sine falling a little as it dies, which is what a drum head does.
	**/
	static function tommed(hz:Float):Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(0.34);

		var phase = 0.0;

		for (index in 0...length) {
			final at = index / RATE;
			final falling = hz * (1 + 0.55 * Math.exp(-at / 0.045));

			phase += 2 * Math.PI * falling / RATE;

			var value = Math.sin(phase) * falls(index, 0.30);
			if (index < many(0.003)) value += hiss() * 0.35 * falls(index, 0.002);

			held.push(value);
		}

		return held;
	}

	/**
		@param seconds How long it rings.
		@param much How much of the noise is kept after the edge is taken off the bottom.
		@return A hat: noise with the low end differenced away, which is what leaves a
			cymbal rather than a rush of air.
	**/
	static function hatted(seconds:Float, much:Float):Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(seconds);

		var was = 0.0;

		for (index in 0...length) {
			final now = hiss();
			final edge = now - was * much;

			was = now;
			held.push(edge * falls(index, seconds * 0.55));
		}

		return held;
	}

	/**
		@return A clap: three short bursts a few milliseconds apart and then the room
			behind them, which is what makes it read as hands rather than noise.
	**/
	static function clapped():Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(0.19);

		final apart = many(0.009);
		var was = 0.0;

		for (index in 0...length) {
			final now = hiss();
			final edge = now - was * 0.4;

			was = now;

			var loud = falls(index, 0.15) * 0.45;

			for (burst in 0...3) {
				final began = burst * apart;
				if (index < began || index > began + apart) continue;

				loud += falls(index - began, 0.006);
			}

			held.push(edge * loud);
		}

		return held;
	}

	/**
		@return A rim: a click with just enough tone in it to have a pitch.
	**/
	static function rimmed():Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(0.045);

		for (index in 0...length) {
			final at = index / RATE;

			final tone = Math.sin(2 * Math.PI * 1720 * at) * 0.6
				+ Math.sin(2 * Math.PI * 415 * at) * 0.4;

			held.push((tone + hiss() * 0.5) * falls(index, 0.018));
		}

		return held;
	}

	/**
		@param seconds How long it rings.
		@param ping What to put under it, in hertz, or nought for none. A ride has a
			stick on it where a crash is all wash.
		@return A cymbal.
	**/
	static function crashed(seconds:Float, ping:Float):Array<Float> {
		fresh();

		final held:Array<Float> = [];
		final length = many(seconds);

		var was = 0.0;

		for (index in 0...length) {
			final at = index / RATE;
			final now = hiss();
			final edge = now - was * 0.82;

			was = now;

			var value = edge * falls(index, seconds * 0.6);

			if (ping > 0) {
				value += Math.sin(2 * Math.PI * ping * at) * falls(index, 0.05) * 0.5;
			}

			held.push(value);
		}

		return held;
	}

	/**
		@return A cowbell: two tones a fifth and a bit apart, each built from the odd
			harmonics a square would have. A square written straight out folds everything
			above half the rate back down as a whistle that is not a cowbell, so only the
			partials that fit are put in.
	**/
	static function belled():Array<Float> {
		final held:Array<Float> = [];
		final length = many(0.26);

		for (index in 0...length) {
			final at = index / RATE;

			held.push((squared(540, at) * 0.6 + squared(800, at) * 0.4)
				* falls(index, 0.22) * 0.7);
		}

		return held;
	}

	/**
		@param hz What it is tuned to.
		@param at How far into the hit.
		@return A square built from the odd harmonics that fit under half the rate.
	**/
	static function squared(hz:Float, at:Float):Float {
		var out = 0.0;
		var harmonic = 1;

		while (hz * harmonic < RATE * 0.45) {
			out += Math.sin(2 * Math.PI * hz * harmonic * at) / harmonic;
			harmonic += 2;
		}

		return out;
	}
}
