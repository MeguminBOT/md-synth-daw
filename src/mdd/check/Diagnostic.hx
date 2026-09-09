package mdd.check;

import mdd.song.Note;
import mdd.song.Part;

@:unreflective

/**
	One thing the song asks of the hardware that the hardware will not do.

	It carries what is wrong, why, and what to do about it, and it knows which note
	caused it, so clicking a warning selects the channel and the note rather than
	leaving the reader to find them.
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
		What is wrong, in one line.
	**/
	public var saying(default, null):String;

	/**
		Why the hardware will not do it.
	**/
	public var reason(default, null):String;

	/**
		What would fix it.
	**/
	public var remedy(default, null):String;

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
		@param saying What is wrong.
		@param reason Why.
		@param remedy What would fix it.
		@param pattern Which pattern, or -1.
		@param note The note that caused it, or null.
	**/
	public function new(severity:Int, part:Part, at:Int, saying:String, reason:String,
			remedy:String = "", pattern:Int = -1, note:Null<Note> = null) {
		this.severity = severity;
		this.part = part;
		this.at = at;
		this.saying = saying;
		this.reason = reason;
		this.remedy = remedy;
		this.pattern = pattern;
		this.note = note;
	}

	/**
		@return Whether it names a note, so clicking it can select something.
	**/
	public inline function linked():Bool {
		return note != null && pattern >= 0;
	}

	/**
		@return The whole diagnostic on one line, for a report.
	**/
	public function line():String {
		return part.name() + " at " + at + ": " + saying;
	}
}
