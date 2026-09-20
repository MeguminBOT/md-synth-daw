package mdd.format;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import haxe.io.BytesInput;
import mdd.song.Envelope;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Patch;
import mdd.song.Sample;

/**
	The preset format: one bank of presets as records rather than as text, for every kind of part
	there is.

	A record is what the part takes, in the order the part takes it. An FM preset is the four
	dials and ten fields an operator has; a square or the noise channel is its envelope; the
	converter is a recording, its bytes as they are played rather than spelt out as text. Reading
	one is a copy rather than a parse, and a bank is a third smaller than the same bank written
	as a document.

	Nothing in a file says what a preset is: `Instrument.identifies` works that out from the data
	once it is read, so a file cannot claim to be a preset it is not. Neither does anything say
	that a preset is a favourite, because a favourite is a reader's own mark on a preset rather
	than part of it, and putting it in the file would make the same preset two presets.

	Numbers are little endian, which is the only order the machines this runs on use.
**/
@:unreflective
final class Preset {
	/**
		What a preset file is called on disk, which the build names so that the desktop and the
		application agree on it. It holds one preset and names no bank.
	**/
	public static inline final SUFFIX = "." + mdd.Config.PRESET;

	/**
		What a bank of presets is called on disk. It is the same records with a name on the front,
		so one file carries a whole folder of them.
	**/
	public static inline final BANK = "." + mdd.Config.BANK;

	/**
		The four bytes a preset file opens with, which say both what it is and which version of it
		this is.
	**/
	public static inline final MAGIC = "MDP1";

	/**
		A record carrying an FM patch.
	**/
	static inline final PATCH = 0;

	/**
		A record carrying a square or noise envelope.
	**/
	static inline final ENVELOPE = 1;

	/**
		A record carrying a recording for the converter.
	**/
	static inline final SAMPLE = 2;

	/**
		The longest name or tag a record holds, which is as much as anyone reads.
	**/
	static inline final SAID = 4096;

	/**
		Writes a bank as one file.

		@param bank What the bank is called, or an empty string for a reader's own presets, which
			the folder names instead.
		@param presets The presets.
		@param samples What each of them plays, by the same index, or null.
		@return The file.
	**/
	public static function write(bank:String, presets:Array<Instrument>,
			samples:Array<Null<Sample>>):Bytes {
		final out = new BytesBuffer();

		out.addString(MAGIC);
		said(out, bank);
		whole(out, presets.length, 2);

		for (index in 0...presets.length) {
			final held = presets[index];
			final sample = index < samples.length ? samples[index] : null;

			out.addByte(held.kind.index());
			whole(out, held.icon + 1, 2);
			said(out, held.name);

			out.addByte(held.tags.length > 255 ? 255 : held.tags.length);
			for (at in 0...(held.tags.length > 255 ? 255 : held.tags.length)) said(out, held.tags[at]);

			final patch = held.patch;
			final envelope = held.envelope;

			if (held.kind.sampled() && sample != null) {
				out.addByte(SAMPLE);
				whole(out, sample.rate, 4);
				out.addByte(sample.root & 0xFF);
				whole(out, sample.loop + 1, 4);
				whole(out, sample.length(), 4);

				for (at in 0...sample.length()) out.addByte(sample.bytes[at] & 0xFF);
			} else if (envelope != null && !held.kind.fm()) {
				out.addByte(ENVELOPE);
				out.addByte(envelope.steps.length > 255 ? 255 : envelope.steps.length);

				for (at in 0...(envelope.steps.length > 255 ? 255 : envelope.steps.length)) {
					out.addByte(envelope.steps[at] & 0xFF);
				}

				whole(out, envelope.loop + 1, 2);
				out.addByte(envelope.speed & 0xFF);
				out.addByte(envelope.noise & 0xFF);
			} else {
				out.addByte(PATCH);
				patched(out, patch == null ? new Patch() : patch);
			}
		}

		return out.getBytes();
	}

	/**
		Reads a bank out of one file.

		@param bytes The file.
		@return What it holds, or null where it is not a preset file this build reads.
	**/
	public static function read(bytes:Null<Bytes>):Null<Banked> {
		if (bytes == null || bytes.length < MAGIC.length + 4) return null;
		if (bytes.getString(0, MAGIC.length) != MAGIC) return null;

		final from = new BytesInput(bytes, MAGIC.length, bytes.length - MAGIC.length);
		from.bigEndian = false;

		final out = new Banked();

		try {
			out.name = spoken(from);
			final many = from.readUInt16();

			for (index in 0...many) {
				final kind:Part = from.readByte();
				final icon = from.readUInt16() - 1;
				final made = new Instrument(spoken(from), kind);

				made.icon = icon;

				final tags = from.readByte();
				for (at in 0...tags) made.tags.push(spoken(from));

				var sample:Null<Sample> = null;

				switch (from.readByte()) {
					case SAMPLE:
						final rate = from.readInt32();
						final root = from.readByte();
						final loop = from.readInt32() - 1;
						final length = from.readInt32();

						if (length < 0 || length > bytes.length) return null;

						final held = new Sample(made.name, rate, root);
						final taken = new haxe.ds.Vector<Int>(length);
						final block = from.read(length);

						for (at in 0...length) taken[at] = block.get(at);

						held.hold(taken);
						held.loop = loop;
						sample = held;

					case ENVELOPE:
						final steps = from.readByte();
						final shape = made.envelope == null ? new Envelope() : made.envelope;

						shape.steps.resize(0);
						for (at in 0...steps) shape.steps.push(from.readByte());

						shape.loop = from.readUInt16() - 1;
						shape.speed = from.readByte();
						shape.noise = from.readByte();

						made.envelope = shape;

					case _:
						made.patch = unpatched(from);
				}

				made.identifies(sample);
				out.add(made, sample);
			}
		} catch (e:Dynamic) {
			return null;
		}

		return out;
	}

	static function patched(out:BytesBuffer, patch:Patch):Void {
		for (which in 0...Patch.DIALS) out.addByte(patch.dial(which) & 0xFF);

		for (slot in 0...Patch.SLOTS) {
			for (row in 0...Patch.ROWS) out.addByte(patch.reads(slot, row) & 0xFF);
			out.addByte(patch.tremolo[slot] ? 1 : 0);
		}
	}

	static function unpatched(from:BytesInput):Patch {
		final out = new Patch();

		for (which in 0...Patch.DIALS) out.turns(which, from.readByte());

		for (slot in 0...Patch.SLOTS) {
			for (row in 0...Patch.ROWS) out.writes(slot, row, from.readByte());
			out.tremolo[slot] = from.readByte() != 0;
		}

		return out;
	}

	/**
		Writes text as its length and then its bytes, so that reading one never runs into the next.
	**/
	static function said(out:BytesBuffer, value:String):Void {
		final held = Bytes.ofString(value);
		final length = held.length > SAID ? SAID : held.length;

		whole(out, length, 2);
		if (length > 0) out.addBytes(held, 0, length);
	}

	static function spoken(from:BytesInput):String {
		final length = from.readUInt16();
		return length == 0 ? "" : from.read(length).toString();
	}

	/**
		Writes a whole number over as many bytes as it is given, least significant first.
	**/
	static function whole(out:BytesBuffer, value:Int, bytes:Int):Void {
		for (at in 0...bytes) out.addByte((value >> (at * 8)) & 0xFF);
	}
}
