package mdd.song;

@:unreflective
final class Clip {
	public static inline final PATTERN = 0;
	public static inline final AUTOMATION = 1;

	public var pattern:Int;
	public var at:Int;
	public var length:Int;
	public var transpose:Int;

	public var kind:Int = PATTERN;
	public var part:Int = -1;
	public var line:Null<Automation> = null;

	public function new(pattern:Int, at:Int, length:Int, transpose:Int = 0) {
		this.pattern = pattern;
		this.at = at;
		this.length = length;
		this.transpose = transpose;
	}

	public static function drives(part:Part, target:Int, slot:Int, at:Int,
			length:Int):Clip {
		final out = new Clip(-1, at, length);

		out.kind = AUTOMATION;
		out.part = part.index();
		out.line = new Automation(target, slot);

		return out;
	}

	public inline function drawn():Bool {
		return kind == AUTOMATION && line != null;
	}

	public function copy():Clip {
		final out = new Clip(pattern, at, length, transpose);

		out.kind = kind;
		out.part = part;

		if (line != null) {
			final made = new Automation(line.target, line.slot);
			for (point in line.points) made.add(point.copy());

			out.line = made;
		}

		return out;
	}

	public inline function ends():Int {
		return at + length;
	}
}
