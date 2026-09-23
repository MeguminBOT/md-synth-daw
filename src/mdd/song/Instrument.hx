package mdd.song;

/**
	What a note plays: a name, which kind of part it is for, and one of a patch, an
	envelope or a sample depending on that kind.
**/
@:unreflective
final class Instrument {
	/**
		What it is called.
	**/
	public var name:String;

	/**
		Which family of part it is for, which decides whether the patch, the envelope or
		the sample is the one that matters.
	**/
	public var kind:Part;

	/**
		Which icon it carries, or -1 for none.
	**/
	public var icon:Int = -1;

	/**
		Its FM patch, for an FM instrument.
	**/
	public var patch:Null<Patch> = null;

	/**
		Its envelope, for a square or noise instrument.
	**/
	public var envelope:Null<Envelope> = null;

	/**
		Which sample it plays, by index into the song, for a sample instrument.
	**/
	public var sample:Int = -1;

	/**
		Words the preset browser searches, beside the name.
	**/
	public final tags:Array<String> = [];

	/**
		What the preset moves on every note it plays, one lane a parameter, each starting again at
		the key on: the envelopes and LFOs of a synthesizer, written as automation. A lane measures
		its points in milliseconds or in beats and holds or loops once past its last, as its
		`synced` and `loop` say. Empty for a preset that moves nothing.
	**/
	public final lanes:Array<mdd.song.Automation> = [];

	/**
		What this preset is: thirty two hexadecimal characters over what it sounds like, which
		`identifies` works out. Two presets that sound different differ here, and two that sound the
		same are the same preset whatever each is called, however each is tagged, whatever folder
		each sits in and whichever of them a project carries. It is what the library matches on, so
		a name is only a label.

		It is a cache of the data rather than a mark on it: `identifies` is called wherever a preset
		is built, read or written, and nothing reads it off a file, so a file cannot claim to be a
		preset it is not.
	**/
	public var id:String = "";

	/**
		Which preset this one was loaded from, by that preset's identity, or an empty string where
		it came from none. An edited channel is no longer the preset it started as, and this is
		what still says where it started: what to put back where the same preset is chosen again,
		and what one parameter goes back to on its own.
	**/
	public var from:String = "";

	/**
		Works out what this preset is from what it sounds like, and keeps the answer in `id`.

		@param sample The recording it plays, for a converter preset, or null.
		@return The identity, as `mdd.format.Preset.identity` gives it.
	**/
	public function identifies(sample:Null<Sample>):String {
		id = mdd.format.Preset.identity(this, sample);
		return id;
	}

	/**
		Builds an instrument, with whichever of a patch or an envelope its kind needs.

		@param name What to call it.
		@param kind Which family of part it is for.
	**/
	public function new(name:String, kind:Part) {
		this.name = name;
		this.kind = kind;

		if (kind.fm()) patch = new Patch();
		else if (kind.square() || kind.noise()) envelope = new Envelope();
	}

	/**
		@param said What was typed into the search.
		@return Whether the name or any tag carries it, ignoring case.
	**/
	public function tagged(said:String):Bool {
		final want = said.toLowerCase();

		if (name.toLowerCase().indexOf(want) >= 0) return true;
		for (tag in tags) if (tag.toLowerCase().indexOf(want) >= 0) return true;

		return false;
	}

	/**
		@return A new instrument with its own copy of whatever it carries.
	**/
	/**
		Takes everything another preset holds, which is what loading one into a channel does and
		what putting a channel back to the preset it came from does. The recording is left alone,
		because a channel plays the one the song already holds rather than a copy of it.

		@param other The preset to take from.
	**/
	public function takes(other:Instrument):Void {
		name = other.name;
		icon = other.icon;
		id = other.id;
		from = other.id;

		patch = other.patch == null ? null : other.patch.copy();
		envelope = other.envelope == null ? null : other.envelope.copy();

		tags.resize(0);
		for (tag in other.tags) tags.push(tag);

		lanes.resize(0);
		for (line in other.lanes) lanes.push(line.copy());
	}

	/**
		@param target Which parameter.
		@param slot Which operator, for a per operator one.
		@return The lane moving it, or null where the preset does not move it.
	**/
	public function lane(target:Int, slot:Int):Null<mdd.song.Automation> {
		for (line in lanes) if (line.target == target && line.slot == slot) return line;
		return null;
	}

	/**
		The attenuation a step holds when it is silent, which is what a shorter envelope is read
		as holding past its end.
	**/
	static inline final QUIET = 15;

	/**
		How far apart on average counts as nothing in common, as a fraction of one over that
		distance. Two is half a range.
	**/
	static inline final SPREAD = 2.0;

	/**
		How alike two presets are, as a fraction of one.

		Every parameter counts once, and each is worth how far apart the two are over how far
		apart they could be, so a total level of 20 against 24 costs a thirty second of one field
		rather than the whole of it. The wiring is the exception: two patches on different
		algorithms are wired differently however close their operators read, so it counts as a
		whole field either way.

		Half a range apart on average scores nought rather than a half, because two patches drawn
		at random sit a third of a range apart on every field and would otherwise all read as two
		thirds alike. The number is shown as a percentage, so the range it uses has to be the one
		a reader can tell things apart in.

		A preset for another kind of part scores nought. What either is called, what it is tagged
		with and what it draws are no part of it: this is what the two sound like, not what they
		are filed as.

		@param other The preset to compare against.
		@return Nought where nothing matches, one where every parameter does.
	**/
	public function likeness(other:Instrument):Float {
		if (!kind.fm() && !kind.square() && !kind.noise() && !kind.sampled()) return 0;
		if (kind.fm() != other.kind.fm()) return 0;
		if (kind.square() != other.kind.square()) return 0;
		if (kind.noise() != other.kind.noise()) return 0;

		var apart = 0.0;
		var counted = 0;

		final patch = this.patch;
		final theirs = other.patch;

		if (patch != null && theirs != null) {
			apart += patch.algorithm == theirs.algorithm ? 0 : 1;
			counted++;

			for (which in 1...Patch.DIALS) {
				final most = Patch.mostDial(which);
				if (most <= 0) continue;

				apart += Math.abs(patch.dial(which) - theirs.dial(which)) / most;
				counted++;
			}

			for (slot in 0...Patch.SLOTS) {
				for (row in 0...Patch.ROWS) {
					final most = Patch.mostOf(row);
					if (most <= 0) continue;

					apart += Math.abs(patch.reads(slot, row) - theirs.reads(slot, row)) / most;
					counted++;
				}

				apart += patch.tremolo[slot] == theirs.tremolo[slot] ? 0 : 1;
				counted++;
			}
		}

		final envelope = this.envelope;
		final shape = other.envelope;

		if (envelope != null && shape != null) {
			final steps = envelope.steps.length;
			final held = shape.steps.length;
			final most = steps > held ? steps : held;

			for (step in 0...most) {
				final one = step < steps ? envelope.steps[step] : QUIET;
				final two = step < held ? shape.steps[step] : QUIET;

				apart += Math.abs(one - two) / QUIET;
				counted++;
			}

			apart += envelope.loop == shape.loop ? 0 : 1;
			apart += envelope.noise == shape.noise ? 0 : 1;
			apart += Math.abs(envelope.speed - shape.speed)
				/ Envelope.mostDial(Envelope.SPEED);
			counted += 3;
		}

		if (counted == 0) return sample >= 0 && other.sample >= 0 && sample == other.sample
			? 1 : 0;

		final out = 1 - apart / counted * SPREAD;
		return out < 0 ? 0 : (out > 1 ? 1 : out);
	}

	public function copy():Instrument {
		final out = new Instrument(name, kind);
		out.id = id;
		out.from = from;
		out.icon = icon;
		out.patch = patch == null ? null : patch.copy();
		out.envelope = envelope == null ? null : envelope.copy();
		out.sample = sample;

		for (tag in tags) out.tags.push(tag);
		for (line in lanes) out.lanes.push(line.copy());
		return out;
	}
}
