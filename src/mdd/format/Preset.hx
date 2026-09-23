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
	public static inline final MAGIC = "MDP3";

	/**
		The four bytes a preset file written before a preset carried lanes opens with. One still
		reads, with no lanes on any preset.
	**/
	public static inline final UNMOVED = "MDP2";

	/**
		The four bytes a preset file written before a bank carried tags of its own opens with. One
		still reads, as a bank with no tags.
	**/
	public static inline final UNTAGGED = "MDP1";

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
		@param tags The bank's own tags, which every preset in it answers to as well, or null.
		@return The file.
	**/
	public static function write(bank:String, presets:Array<Instrument>,
			samples:Array<Null<Sample>>, ?tags:Array<String>):Bytes {
		final out = new BytesBuffer();
		final many = tags == null ? 0 : (tags.length > 255 ? 255 : tags.length);

		out.addString(MAGIC);
		said(out, bank);

		out.addByte(many);
		for (at in 0...many) said(out, tags[at]);

		whole(out, presets.length, 2);

		for (index in 0...presets.length) {
			final held = presets[index];
			final sample = index < samples.length ? samples[index] : null;

			out.addByte(held.kind.index());
			whole(out, held.icon + 1, 2);
			said(out, held.name);

			out.addByte(held.tags.length > 255 ? 255 : held.tags.length);
			for (at in 0...(held.tags.length > 255 ? 255 : held.tags.length)) said(out, held.tags[at]);

			sounded(out, held, sample);
			moved(out, held);
		}

		return out.getBytes();
	}

	/**
		Writes the lanes a preset moves on every note: how many, then each one's parameter, its time
		base, its loop and its points. A preset with none writes a single nought.

		@param out Where it goes.
		@param held The preset.
	**/
	static function moved(out:BytesBuffer, held:Instrument):Void {
		final many = held.lanes.length > 255 ? 255 : held.lanes.length;
		out.addByte(many);

		for (index in 0...many) {
			final line = held.lanes[index];
			final count = line.points.length > 0xFFFF ? 0xFFFF : line.points.length;

			out.addByte(line.target & 0xFF);
			out.addByte(line.slot & 0xFF);
			out.addByte(line.synced ? 1 : 0);
			whole(out, line.loop + 1, 2);
			whole(out, count, 2);

			for (at in 0...count) {
				final point = line.points[at];

				whole(out, point.at, 4);
				whole(out, point.value, 2);
				out.addByte(point.shape & 0xFF);
				out.addByte(point.tension & 0xFF);
				out.addByte(point.steps & 0xFF);
			}
		}
	}

	/**
		Reads the lanes `moved` wrote into a preset.

		@param from Where to read.
		@param into The preset.
	**/
	static function unmoved(from:BytesInput, into:Instrument):Void {
		final many = from.readByte();

		for (index in 0...many) {
			final target = from.readByte();
			final slot = from.readByte();
			final line = new mdd.song.Automation(target, slot);

			line.synced = from.readByte() != 0;
			line.loop = from.readUInt16() - 1;

			final count = from.readUInt16();

			for (step in 0...count) {
				final at = from.readInt32();
				final value = from.readInt16();
				final point = new mdd.song.Point(at, value);

				point.shape = from.readByte();
				point.tension = signed(from.readByte());
				point.steps = from.readByte();
				line.points.push(point);
			}

			into.lanes.push(line);
		}
	}

	/**
		@return A byte read back as the signed number it was written from.
	**/
	static inline function signed(value:Int):Int {
		return value > 127 ? value - 256 : value;
	}

	/**
		Writes what a preset sounds like and nothing else: which of the three records it is, then
		the patch, the envelope or the recording. This is the tail of every preset in a file, and
		what a preset's identity is worked out over.

		@param out Where it goes.
		@param held The preset.
		@param sample The recording it plays, or null.
	**/
	static function sounded(out:BytesBuffer, held:Instrument, sample:Null<Sample>):Void {
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

	/**
		@param kind A part.
		@return The byte its family is written as at the head of an identity: 0 for FM, 1 for a
			square, 2 for the noise channel and 3 for the converter.
	**/
	static inline function family(kind:Part):Int {
		return kind.fm() ? 0 : (kind.square() ? 1 : (kind.noise() ? 2 : 3));
	}

	/**
		What a preset is, worked out from what it sounds like alone: the MD5 of its family byte
		followed by its sound record, as `sounded` writes it, and then its lanes as `moved` writes
		them where it has any, in lower case hexadecimal. A preset that moves nothing is the same
		preset it was before presets carried lanes.

		Nothing a reader chose goes into it, so the same sound saved under another name, with other
		tags or another icon, in another folder or another file, is the same preset. The layout is
		fixed and written down in `docs/notes/presets.md`, so anything that writes the same bytes
		gets the same answer, the way a FLAC signature is the MD5 of the samples whatever encoded
		them.

		@param held The preset.
		@param sample The recording it plays, for a converter preset, or null.
		@return Thirty two hexadecimal characters.
	**/
	public static function identity(held:Instrument, sample:Null<Sample>):String {
		final out = new BytesBuffer();

		out.addByte(family(held.kind));
		sounded(out, held, sample);
		if (held.lanes.length > 0) moved(out, held);

		return haxe.crypto.Md5.make(out.getBytes()).toHex();
	}

	/**
		Reads a bank out of one file.

		@param bytes The file.
		@return What it holds, or null where it is not a preset file this build reads.
	**/
	public static function read(bytes:Null<Bytes>):Null<Banked> {
		if (bytes == null || bytes.length < MAGIC.length + 4) return null;

		final opening = bytes.getString(0, MAGIC.length);
		if (opening != MAGIC && opening != UNMOVED && opening != UNTAGGED) return null;

		final from = new BytesInput(bytes, MAGIC.length, bytes.length - MAGIC.length);
		from.bigEndian = false;

		final out = new Banked();

		try {
			out.name = spoken(from);

			if (opening != UNTAGGED) {
				final tags = from.readByte();
				for (at in 0...tags) out.tags.push(spoken(from));
			}

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

				if (opening == MAGIC) unmoved(from, made);

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
