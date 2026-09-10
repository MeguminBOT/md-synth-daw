package mdd.check;

import mdd.song.Note;
import mdd.song.Part;

@:unreflective

/**
	One thing the song asks of the hardware that the hardware will not do.

	It carries the names of what is wrong, why, and what to do about it, along with the
	values those lines leave places for. The words themselves live in the string table,
	so a warning is read in whatever language is worn rather than the one the check was
	written in.

	It knows which note caused it, so clicking a warning selects the channel and the
	note rather than leaving the reader to find them.
**/
final class Diagnostic {
	/**
		Severity: it will sound, but not as written.
	**/
	public static inline final WARNING = 0;

	/**
		Severity: it will not sound at all.
	**/
	public static inline final FAULT = 1;

	/**
		`WARNING` or `FAULT`.
	**/
	public var severity(default, null):Int;

	/**
		Which part it is about.
	**/
	public var part(default, null):Part;

	/**
		Where in the song, in ticks.
	**/
	public var at(default, null):Int;

	/**
		Which string says what is wrong.
	**/
	public var saying(default, null):Int;

	/**
		Which string says why the hardware will not do it.
	**/
	public var reason(default, null):Int;

	/**
		Which string says what would fix it.
	**/
	public var remedy(default, null):Int;

	/**
		What goes in the numbered places those three leave, in order. All three draw
		from the one list, so a value the reason needs is numbered wherever it falls
		across the set rather than counted afresh in each line.
	**/
	public final values:Array<String>;

	/**
		Which pattern it is in, or -1 where it is not in one.
	**/
	public var pattern(default, null):Int;

	/**
		The note that caused it, where one did. This is what a warning links to.
	**/
	public var note(default, null):Null<Note>;

	/**
		Records one diagnostic.

		@param severity `WARNING` or `FAULT`.
		@param part Which part it is about.
		@param at Where in the song, in ticks.
		@param saying Which string says what is wrong.
		@param reason Which string says why.
		@param remedy Which string says what would fix it.
		@param values What goes in the places those three leave.
		@param pattern Which pattern, or -1.
		@param note The note that caused it, or null.
	**/
	public function new(severity:Int, part:Part, at:Int, saying:Int, reason:Int,
			remedy:Int, values:Array<String>, pattern:Int = -1,
			note:Null<Note> = null) {
		this.severity = severity;
		this.part = part;
		this.at = at;
		this.saying = saying;
		this.reason = reason;
		this.remedy = remedy;
		this.values = values;
		this.pattern = pattern;
		this.note = note;
	}

	/**
		@return Whether it names a note, so clicking it can select something.
	**/
	public inline function linked():Bool {
		return note != null && pattern >= 0;
	}
}
