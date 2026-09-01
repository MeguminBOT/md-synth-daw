package mdd.check;

import mdd.song.Note;
import mdd.song.Part;

@:unreflective
final class Diagnostic {
	public static inline final WARNING = 0;
	public static inline final FAULT = 1;

	public var severity(default, null):Int;
	public var part(default, null):Part;
	public var at(default, null):Int;

	public var saying(default, null):String;
	public var reason(default, null):String;
	public var remedy(default, null):String;

	public var pattern(default, null):Int;
	public var note(default, null):Null<Note>;

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

	public inline function linked():Bool {
		return note != null && pattern >= 0;
	}

	public function line():String {
		return part.name() + " at " + at + ": " + saying;
	}
}
