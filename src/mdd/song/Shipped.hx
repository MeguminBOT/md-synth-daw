package mdd.song;

/**
	The default bank, built in code rather than read from a file, so a new song has
	something to play before anything is loaded.

	The FM patches here are register values, and the square and noise entries are
	envelopes: lists of attenuation steps a driver would write on a frame timer.
**/
@:unreflective
final class Shipped {
	/**
		Field 0 of a packed patch: detune.
	**/
	public static inline final DETUNE = 0;
	static inline final MULTIPLE = 1;

	/**
		Field 2 of a packed patch: total level.
	**/
	public static inline final LEVEL = 2;
	static inline final SCALING = 3;

	/**
		Field 4 of a packed patch: attack rate.
	**/
	public static inline final ATTACK = 4;

	/**
		Field 5 of a packed patch: decay rate.
	**/
	public static inline final DECAY = 5;

	/**
		Field 6 of a packed patch: sustain rate.
	**/
	public static inline final SUSTAIN = 6;
	static inline final SUSTAIN_LEVEL = 7;

	/**
		Field 8 of a packed patch: release rate.
	**/
	public static inline final RELEASE = 8;

	/**
		Field 9 of a packed patch: the SSG-EG nibble.
	**/
	public static inline final SSG = 9;

	/**
		How many fields each operator takes.
	**/
	public static inline final FIELDS = 10;

	static final FM_NAMES:Array<String> = ["Grand", "Electric piano", "Round bass",
		"Slap bass", "Brass section", "Strings", "Drawbar organ", "Square lead",
		"Bell", "Marimba", "Choir", "Warm pad", "Clavinet", "Glass lead", "Tom",
		"Metal hit"];

	static final FM_PATCHES:Array<Array<Int>> = [
		[2, 4,
			0, 1, 34, 1, 31, 9, 4, 3, 8, 0,
			0, 2, 42, 0, 31, 11, 4, 4, 8, 0,
			0, 1, 36, 0, 31, 10, 3, 3, 8, 0,
			0, 1, 10, 1, 31, 8, 2, 2, 9, 0],

		[5, 3,
			0, 4, 40, 0, 31, 14, 6, 6, 9, 0,
			0, 1, 20, 0, 31, 10, 4, 3, 8, 0,
			3, 1, 26, 0, 31, 12, 4, 4, 8, 0,
			5, 1, 24, 0, 31, 11, 4, 4, 8, 0],

		[3, 6,
			0, 1, 30, 0, 31, 12, 5, 4, 10, 0,
			3, 1, 36, 0, 31, 14, 6, 5, 10, 0,
			0, 1, 44, 0, 31, 10, 4, 3, 10, 0,
			0, 1, 6, 0, 31, 9, 3, 2, 11, 0],

		[4, 5,
			0, 2, 26, 1, 31, 16, 8, 6, 12, 0,
			0, 1, 8, 1, 31, 12, 5, 4, 11, 0,
			3, 1, 32, 0, 31, 18, 9, 7, 12, 0,
			0, 1, 10, 1, 31, 10, 4, 3, 11, 0],

		[2, 5,
			0, 1, 32, 0, 22, 6, 2, 2, 7, 0,
			0, 1, 38, 0, 20, 7, 2, 3, 7, 0,
			3, 1, 36, 0, 21, 6, 2, 2, 7, 0,
			0, 1, 12, 0, 24, 5, 1, 1, 8, 0],

		[4, 3,
			0, 1, 36, 0, 17, 4, 1, 1, 6, 0,
			0, 1, 16, 0, 16, 3, 1, 1, 6, 0,
			4, 1, 38, 0, 18, 4, 1, 1, 6, 0,
			3, 1, 18, 0, 15, 3, 1, 1, 6, 0],

		[7, 0,
			0, 1, 22, 0, 31, 0, 0, 0, 9, 0,
			0, 2, 28, 0, 31, 0, 0, 0, 9, 0,
			0, 4, 32, 0, 31, 0, 0, 0, 9, 0,
			0, 8, 38, 0, 31, 0, 0, 0, 9, 0],

		[7, 7,
			0, 1, 14, 0, 31, 4, 0, 1, 8, 0,
			0, 1, 30, 0, 31, 6, 0, 2, 8, 0,
			0, 2, 40, 0, 31, 8, 0, 3, 8, 0,
			0, 3, 46, 0, 31, 10, 0, 4, 8, 0],

		[5, 0,
			0, 7, 34, 0, 31, 8, 3, 3, 6, 0,
			0, 2, 20, 0, 31, 6, 2, 2, 5, 0,
			3, 5, 30, 0, 31, 7, 3, 3, 5, 0,
			5, 11, 34, 0, 31, 9, 4, 4, 6, 0],

		[4, 2,
			0, 5, 30, 1, 31, 20, 12, 8, 14, 0,
			0, 1, 12, 1, 31, 17, 10, 6, 13, 0,
			0, 9, 38, 1, 31, 22, 13, 9, 14, 0,
			0, 2, 16, 1, 31, 18, 11, 7, 13, 0],

		[4, 2,
			3, 1, 40, 0, 14, 3, 1, 1, 5, 0,
			0, 1, 20, 0, 13, 2, 1, 1, 5, 0,
			5, 1, 42, 0, 15, 3, 1, 1, 5, 0,
			2, 1, 22, 0, 12, 2, 1, 1, 5, 0],

		[4, 3,
			3, 1, 44, 0, 11, 2, 1, 1, 4, 0,
			0, 1, 24, 0, 10, 2, 1, 1, 4, 0,
			5, 2, 46, 0, 12, 2, 1, 1, 4, 0,
			1, 1, 26, 0, 9, 1, 1, 1, 4, 0],

		[3, 7,
			0, 2, 24, 1, 31, 14, 8, 5, 12, 0,
			3, 3, 34, 1, 31, 16, 9, 6, 12, 0,
			0, 1, 40, 1, 31, 13, 7, 5, 12, 0,
			0, 1, 8, 1, 31, 12, 6, 4, 13, 0],

		[6, 4,
			0, 3, 28, 0, 31, 10, 4, 4, 8, 0,
			0, 1, 18, 0, 31, 8, 3, 3, 7, 0,
			3, 4, 34, 0, 31, 11, 5, 4, 8, 0,
			5, 6, 38, 0, 31, 12, 5, 5, 8, 0],

		[3, 7,
			0, 1, 20, 2, 31, 18, 10, 6, 14, 0,
			0, 1, 32, 2, 31, 20, 11, 7, 14, 0,
			3, 1, 36, 2, 31, 19, 10, 6, 14, 0,
			0, 1, 6, 2, 31, 16, 9, 5, 15, 0],

		[7, 7,
			0, 13, 26, 0, 31, 24, 14, 10, 15, 0,
			0, 9, 32, 0, 31, 25, 15, 11, 15, 0,
			3, 11, 30, 0, 31, 24, 14, 10, 15, 0,
			5, 15, 34, 0, 31, 26, 15, 11, 15, 0]
	];

	static final SQUARE_NAMES:Array<String> = ["Square lead", "Square pluck", "Square pad",
		"Square bass", "Square echo", "Square organ"];

	static final SQUARE_SHAPES:Array<Array<Int>> = [
		[0, 0, 1, 1, 2, 2, 3, 3],
		[0, 1, 2, 4, 6, 8, 10, 12, 15],
		[5, 4, 3, 2, 1, 0],
		[0, 0, 0, 1, 2, 3, 4, 6, 9, 15],
		[0, 5, 1, 7, 3, 9, 6, 12, 15],
		[1]
	];

	static final SQUARE_LOOPS:Array<Int> = [4, -1, 5, -1, -1, 0];

	static final NOISE_NAMES:Array<String> = ["Hat", "Snare", "Rumble"];

	static final NOISE_SHAPES:Array<Array<Int>> = [
		[0, 4, 8, 12, 15],
		[0, 2, 5, 9, 13, 15],
		[0, 1, 2, 3, 4, 5, 7, 9, 12, 15]
	];

	static final NOISE_KINDS:Array<Int> = [4, 5, 1];

	static final FM_ICONS:Array<Int> = [
		mdd.Icon.PIANO, mdd.Icon.PIANO, mdd.Icon.BASS, mdd.Icon.BASS,
		mdd.Icon.TRUMPET, mdd.Icon.VIOLIN, mdd.Icon.PIPE, mdd.Icon.WAVE_SQUARE,
		mdd.Icon.BELL, mdd.Icon.IDIOPHONE, mdd.Icon.MICROPHONE, mdd.Icon.WAVE_SINE,
		mdd.Icon.SYNTHESIZER, mdd.Icon.WAVE_TRIANGLE, mdd.Icon.TOM, mdd.Icon.CYMBAL
	];

	static final SQUARE_ICONS:Array<Int> = [
		mdd.Icon.WAVE_SQUARE, mdd.Icon.NOTE, mdd.Icon.WAVE_SINE, mdd.Icon.BASS,
		mdd.Icon.SPEAKER, mdd.Icon.PIPE
	];

	static final NOISE_ICONS:Array<Int> = [mdd.Icon.HI_HAT, mdd.Icon.SNARE, mdd.Icon.WAVE_NOISE];

	/**
		Puts every default instrument into a song and gathers them into one bank.

		@param song The song to add them to.
		@return The bank they were gathered into.
	**/
	public static function into(song:Song):Bank {
		final bank = song.banked("Default");

		for (index in 0...FM_NAMES.length) {
			final instrument = new Instrument(FM_NAMES[index], Part.Fm1);
			instrument.patch = patched(FM_PATCHES[index]);
			instrument.icon = FM_ICONS[index];
			instrument.identifies(null);

			song.instrument(instrument);
			bank.add(song.instruments.length - 1);
		}

		for (index in 0...SQUARE_NAMES.length) {
			final instrument = new Instrument(SQUARE_NAMES[index], Part.Psg1);
			final envelope = instrument.envelope;

			instrument.icon = SQUARE_ICONS[index];

			if (envelope != null) {
				for (step in SQUARE_SHAPES[index]) envelope.steps.push(step);
				envelope.loop = SQUARE_LOOPS[index];
			}

			instrument.identifies(null);
			song.instrument(instrument);
			bank.add(song.instruments.length - 1);
		}

		for (index in 0...NOISE_NAMES.length) {
			final instrument = new Instrument(NOISE_NAMES[index], Part.Noise);
			final envelope = instrument.envelope;

			instrument.icon = NOISE_ICONS[index];

			if (envelope != null) {
				for (step in NOISE_SHAPES[index]) envelope.steps.push(step);
				envelope.noise = NOISE_KINDS[index];
			}

			instrument.identifies(null);
			song.instrument(instrument);
			bank.add(song.instruments.length - 1);
		}

		return bank;
	}

	/**
		Unpacks one of the tables above into a patch.

		@param fields The algorithm, the feedback, and ten fields per operator.
		@return The patch.
	**/
	public static function patched(fields:Array<Int>):Patch {
		final patch = new Patch();

		patch.algorithm = fields[0] & 7;
		patch.feedback = fields[1] & 7;

		for (slot in 0...Patch.SLOTS) {
			final at = 2 + slot * FIELDS;

			patch.detune[slot] = fields[at + DETUNE] & 7;
			patch.multiple[slot] = fields[at + MULTIPLE] & 0x0F;
			patch.totalLevel[slot] = fields[at + LEVEL] & 0x7F;
			patch.keyScale[slot] = fields[at + SCALING] & 3;
			patch.attack[slot] = fields[at + ATTACK] & 0x1F;
			patch.decay[slot] = fields[at + DECAY] & 0x1F;
			patch.sustain[slot] = fields[at + SUSTAIN] & 0x1F;
			patch.sustainLevel[slot] = fields[at + SUSTAIN_LEVEL] & 0x0F;
			patch.release[slot] = fields[at + RELEASE] & 0x0F;
			patch.ssg[slot] = fields[at + SSG] & 0x0F;
		}

		patch.rests();

		return patch;
	}

	/**
		@param song The song to look in.
		@return The first FM instrument, by index, or -1 where there is none.
	**/
	public static function firstFm(song:Song):Int {
		for (index in 0...song.instruments.length) {
			if (song.instruments[index].patch != null) return index;
		}

		return -1;
	}

	/**
		@param song The song to look in.
		@return The first square instrument, by index, or -1 where there is none.
	**/
	public static function firstSquare(song:Song):Int {
		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			if (held.envelope != null && held.kind.square()) return index;
		}

		return -1;
	}

	/**
		@param song The song to look in.
		@return The first noise instrument, by index, or -1 where there is none.
	**/
	public static function firstNoise(song:Song):Int {
		for (index in 0...song.instruments.length) {
			final held = song.instruments[index];
			if (held.envelope != null && held.kind.noise()) return index;
		}

		return -1;
	}
}
