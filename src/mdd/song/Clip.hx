package mdd.song;

/**
	One placement of a pattern on a track, or one automation lane a track drives.

	A clip carries where inside its pattern it starts, so cutting one in two keeps the
	music where it was rather than restarting it.
**/
@:unreflective
final class Clip {
	/**
		Kind: this clip plays a pattern.
	**/
	public static inline final PATTERN = 0;

	/**
		Kind: this clip drives one automation lane of a channel it does not otherwise own.
	**/
	public static inline final AUTOMATION = 1;

	/**
		Which pattern it plays, by index.
	**/
	public var pattern:Int;

	/**
		Where it sits on the track, in ticks.
	**/
	public var at:Int;

	/**
		How long it lasts, in ticks.
	**/
	public var length:Int;

	/**
		Semitones to shift every note in it by.
	**/
	public var transpose:Int;

	/**
		How far into the pattern this clip starts, which is what a slice leaves behind.
	**/
	public var offset:Int;

	/**
		Whether it plays a pattern or drives automation.
	**/
	public var kind:Int = PATTERN;

	/**
		Which part it drives, for an automation clip. Not used by a pattern clip.
	**/
	public var part:Int = -1;

	/**
		The lane it drives, for an automation clip.
	**/
	public var line:Null<Automation> = null;

	/**
		Builds a clip that plays a pattern.

		@param pattern Which pattern, by index.
		@param at Where it sits, in ticks.
		@param length How long it lasts, in ticks.
		@param transpose Semitones to shift its notes by.
		@param offset How far into the pattern it starts.
	**/
	public function new(pattern:Int, at:Int, length:Int, transpose:Int = 0, offset:Int = 0) {
		this.pattern = pattern;
		this.at = at;
		this.length = length;
		this.transpose = transpose;
		this.offset = offset;
	}

	/**
		Builds a clip that drives one automation lane rather than playing a pattern.

		@param part Which part it drives.
		@param target Which channel the lane belongs to, or -1 for the part's own.
		@param slot Which lane of that channel.
		@param at Where it sits, in ticks.
		@param length How long it lasts, in ticks.
		@return The new clip.
	**/
	public static function drives(part:Part, target:Int, slot:Int, at:Int,
			length:Int):Clip {
		final out = new Clip(-1, at, length);

		out.kind = AUTOMATION;
		out.part = part.index();
		out.line = new Automation(target, slot);

		return out;
	}

	/**
		@return Whether this clip drives an automation lane, as against playing a
			pattern.
	**/
	public inline function automates():Bool {
		return kind == AUTOMATION && line != null;
	}

	/**
		@return A new clip with the same values, and its own copy of any lane it drives.
	**/
	public function copy():Clip {
		final out = new Clip(pattern, at, length, transpose, offset);

		out.kind = kind;
		out.part = part;

		if (line != null) {
			final made = new Automation(line.target, line.slot);
			for (point in line.points) made.add(point.copy());

			out.line = made;
		}

		return out;
	}

	/**
		@return The tick it finishes on.
	**/
	public inline function ends():Int {
		return at + length;
	}

	/**
		@return Where the pattern would have started if this clip were not offset, which is what
			places its notes.
	**/
	public inline function origin():Int {
		return at - offset;
	}
}
