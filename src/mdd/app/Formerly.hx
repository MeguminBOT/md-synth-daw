package mdd.app;

import haxe.Int64;
import mdd.song.Instrument;
import mdd.song.Library;
import mdd.song.Patch;
import mdd.song.Sample;
import mdd.song.Song;

@:unreflective

/**
	The identity a preset was given before it was worked out from its sound alone, kept for one
	job: carrying across what was keyed on it. That is a star in the settings, and which preset a
	channel in an older project came from.

	It hashed the name, the kind of part, the icon and the tags beside the sound, with FNV-1a taken
	twice from two seeds and an avalanche on the end, so renaming a preset made it another preset.
	Nothing is written with it any more.
**/
final class Formerly {
	static final PRIME:Int64 = Int64.make(0x00000100, 0x000001B3);

	/**
		Moves every star keyed on a former identity onto the identity the same preset has now.

		@param stars The stars.
		@param library Every preset installed, which is what a star could have been put on.
		@return How many stars moved.
	**/
	public static function stars(stars:Favourites, library:Library):Int {
		if (stars.count() == 0) return 0;

		var moved = 0;

		for (at in 0...library.names.length) {
			final held = library.instruments[at];

			for (which in 0...held.length) {
				final now = held[which].id;
				final was = identity(held[which], library.samples[at][which]);

				if (now == "" || was == now || !stars.favours(was)) continue;

				stars.favour(now, true);
				stars.favour(was, false);
				moved++;
			}
		}

		return moved;
	}

	/**
		Points every channel in a piece that names the preset it came from by a former identity at
		the identity that preset has now, looking for it among the installed presets and the piece's
		own. A channel whose origin is found under its present identity is left alone.

		@param song The piece, just read.
		@param library Every preset installed.
		@return How many channels were pointed again.
	**/
	public static function origins(song:Song, library:Library):Int {
		final known:Array<String> = [];

		for (held in library.instruments) for (one in held) known.push(one.id);
		for (one in song.instruments) known.push(one.id);

		var formerly:Null<Map<String, String>> = null;
		var moved = 0;

		for (one in song.instruments) {
			if (one.from == "" || known.indexOf(one.from) >= 0) continue;

			if (formerly == null) formerly = former(song, library);

			final now = formerly.get(one.from);
			if (now == null) continue;

			one.from = now;
			moved++;
		}

		return moved;
	}

	/**
		@param song A piece.
		@param library Every preset installed.
		@return Each preset's former identity, answering the identity it has now.
	**/
	static function former(song:Song, library:Library):Map<String, String> {
		final out = new Map<String, String>();

		for (at in 0...library.names.length) {
			final held = library.instruments[at];

			for (which in 0...held.length) {
				out.set(identity(held[which], library.samples[at][which]), held[which].id);
			}
		}

		for (one in song.instruments) out.set(identity(one, song.sampleAt(one.sample)), one.id);

		return out;
	}

	/**
		@param held A preset.
		@param sample The recording it plays, or null.
		@return The identity it would have been given before identity was taken from the sound.
	**/
	public static function identity(held:Instrument, sample:Null<Sample>):String {
		var one = Int64.make(0x9E3779B9, 0x7F4A7C15);
		var two = Int64.make(0xC2B2AE3D, 0x27D4EB4F);

		one = said(one, held.name);
		two = said(two, held.name);
		one = whole(one, held.kind.index());
		two = whole(two, held.kind.index());
		one = whole(one, held.icon);
		two = whole(two, held.icon);

		for (tag in held.tags) {
			one = said(one, tag);
			two = said(two, tag);
		}

		final patch = held.patch;

		if (patch != null) {
			for (which in 0...Patch.DIALS) {
				one = whole(one, patch.dial(which));
				two = whole(two, patch.dial(which));
			}

			for (slot in 0...Patch.SLOTS) {
				for (row in 0...Patch.ROWS) {
					one = whole(one, patch.reads(slot, row));
					two = whole(two, patch.reads(slot, row));
				}

				one = whole(one, patch.tremolo[slot] ? 1 : 0);
				two = whole(two, patch.tremolo[slot] ? 1 : 0);
			}
		}

		final shape = held.envelope;

		if (shape != null) {
			for (step in shape.steps) {
				one = whole(one, step);
				two = whole(two, step);
			}

			one = whole(one, shape.loop);
			two = whole(two, shape.loop);
			one = whole(one, shape.speed);
			two = whole(two, shape.speed);
			one = whole(one, shape.noise);
			two = whole(two, shape.noise);
		}

		if (sample != null) {
			one = whole(one, sample.rate);
			two = whole(two, sample.rate);
			one = whole(one, sample.root);
			two = whole(two, sample.root);
			one = whole(one, sample.loop);
			two = whole(two, sample.loop);

			for (at in 0...sample.length()) {
				one = whole(one, sample.bytes[at]);
				two = whole(two, sample.bytes[at]);
			}
		}

		return spelt(settled(one)) + spelt(settled(two));
	}

	/**
		@param held What has been fed so far.
		@param value A whole number to feed it, every byte of it, least significant first.
		@return The hash with that number in it.
	**/
	static function whole(held:Int64, value:Int):Int64 {
		var out = held;

		out = (out ^ Int64.ofInt(value & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >> 8) & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >> 16) & 0xFF)) * PRIME;
		out = (out ^ Int64.ofInt((value >>> 24) & 0xFF)) * PRIME;

		return out;
	}

	/**
		@param held What has been fed so far.
		@param value Text to feed it, its length first and then each character code.
		@return The hash with that text in it.
	**/
	static function said(held:Int64, value:String):Int64 {
		var out = whole(held, value.length);

		for (at in 0...value.length) out = whole(out, value.charCodeAt(at));

		return out;
	}

	/**
		@param held A fed hash.
		@return It mixed, so that every bit of what went in reaches every bit of what comes out.
	**/
	static function settled(held:Int64):Int64 {
		var out = held;

		out = (out ^ (out >>> 33)) * Int64.make(0xFF51AFD7, 0xED558CCD);
		out = (out ^ (out >>> 33)) * Int64.make(0xC4CEB9FE, 0x1A85EC53);

		return out ^ (out >>> 33);
	}

	/**
		@param held A hash.
		@return It as sixteen hexadecimal characters.
	**/
	static function spelt(held:Int64):String {
		return StringTools.hex(held.high, 8).toLowerCase()
			+ StringTools.hex(held.low, 8).toLowerCase();
	}
}
