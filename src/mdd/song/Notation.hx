package mdd.song;

/**
	How note names are written: with sharps or with flats, and with English letters or German
	ones, where B natural is H and B flat is B.

	A style is one number carrying both choices, which is what the session keeps and the
	preferences set. Nothing here holds any state, so every view spells and reads notes through it.
**/
final class Notation {
	/**
		Accidentals: a raised note is written with a sharp.
	**/
	public static inline final SHARPS = 0;

	/**
		Accidentals: a lowered note is written with a flat.
	**/
	public static inline final FLATS = 1;

	/**
		Letters: C to B.
	**/
	public static inline final ENGLISH = 0;

	/**
		Letters: C to H, where B natural is H and B flat is B.
	**/
	public static inline final GERMAN = 1;

	static final NAMES:Array<Array<String>> = [
		["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"],
		["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"],
		["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "H"],
		["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "B", "H"]
	];

	static final SPELT:Array<Array<String>> = spellings(false);
	static final CELLS:Array<Array<String>> = spellings(true);

	/**
		Every MIDI note's name and octave in every style, made once, so a view spelling a screen of
		notes every frame allocates nothing doing it.

		@param cells Whether to pad a one letter name with a dash, as a tracker cell writes it.
		@return The names, by style and then by pitch.
	**/
	static function spellings(cells:Bool):Array<Array<String>> {
		final made:Array<Array<String>> = [];

		for (style in 0...4) {
			final names:Array<String> = [];

			for (pitch in 0...128) {
				final held = NAMES[style][pitch % 12];
				names.push((cells && held.length < 2 ? held + "-" : held) + (Std.int(pitch / 12) - 1));
			}

			made.push(names);
		}

		return made;
	}

	/**
		@param accidentals `SHARPS` or `FLATS`.
		@param letters `ENGLISH` or `GERMAN`.
		@return The style carrying both.
	**/
	public static inline function styled(accidentals:Int, letters:Int):Int {
		return (accidentals & 1) | ((letters & 1) << 1);
	}

	/**
		@param style A style.
		@return `SHARPS` or `FLATS`.
	**/
	public static inline function accidentalsOf(style:Int):Int {
		return style & 1;
	}

	/**
		@param style A style.
		@return `ENGLISH` or `GERMAN`.
	**/
	public static inline function lettersOf(style:Int):Int {
		return (style >> 1) & 1;
	}

	/**
		@param step A pitch class, 0 for C, wrapping either way.
		@param style How notes are written.
		@return Its name, with no octave.
	**/
	public static function name(step:Int, style:Int):String {
		return NAMES[style & 3][((step % 12) + 12) % 12];
	}

	/**
		@param pitch A MIDI note number.
		@param style How notes are written.
		@return Its name and the octave general MIDI counts it in, where 60 is C4.
	**/
	public static function spelt(pitch:Int, style:Int):String {
		final held = pitch < 0 ? 0 : pitch;
		if (held < 128) return SPELT[style & 3][held];

		return name(held % 12, style) + (Std.int(held / 12) - 1);
	}

	/**
		@param pitch A MIDI note number.
		@param style How notes are written.
		@return The name as a tracker cell writes it, padded to two characters with a dash and then
			the octave, or three dashes outside the MIDI range.
	**/
	public static function cell(pitch:Int, style:Int):String {
		if (pitch < 0 || pitch > 127) return "---";

		return CELLS[style & 3][pitch];
	}

	/**
		Reads a typed note: a letter in either case, then a sharp, a flat, a dash or nothing, then an
		octave.

		@param said What was typed.
		@param style How notes are written, which decides whether B is B natural or B flat and
			whether H is a note at all.
		@return The MIDI note number, or -1 where it reads as no note.
	**/
	public static function read(said:String, style:Int):Int {
		final held = StringTools.trim(said);
		if (held.length < 2) return -1;

		final german = lettersOf(style) == GERMAN;

		var step = switch (held.charAt(0).toUpperCase()) {
			case "C": 0;
			case "D": 2;
			case "E": 4;
			case "F": 5;
			case "G": 7;
			case "A": 9;
			case "B": german ? 10 : 11;
			case "H": german ? 11 : -1;
			case _: -1;
		}

		if (step < 0) return -1;

		var index = 1;
		final next = held.charAt(1);

		if (next == "#") {
			step++;
			index = 2;
		} else if (next == "b") {
			step--;
			index = 2;
		} else if (next == "-") {
			index = 2;
		}

		final octave = Std.parseInt(held.substr(index, 1));
		if (octave == null) return -1;

		final pitch = (octave + 1) * 12 + step;
		return pitch < 0 || pitch > 127 ? -1 : pitch;
	}
}
