package mdd.song;

@:unreflective
final class Automation {
	public static inline final LEVEL = 0;
	public static inline final SIDES = 1;
	public static inline final TUNE = 2;
	public static inline final TIMBRE = 3;
	public static inline final ATTACK = 4;
	public static inline final DECAY = 5;
	public static inline final SUSTAIN = 6;
	public static inline final RELEASE = 7;
	public static inline final LOOP = 8;
	public static inline final WIRING = 9;

	public static final BASES:Array<Int> = [0x40, 0, 0, 0x30, 0x50, 0x60, 0x70, 0x80, 0x90,
		0xB0];

	public static inline function operates(target:Int):Bool {
		return target == LEVEL || (target >= TIMBRE && target <= WIRING);
	}

	public static inline final ROOM = 8192;

	public var target:Int;
	public var slot:Int;
	public final points:Array<Point> = [];

	public function new(target:Int, slot:Int = 0) {
		this.target = target;
		this.slot = slot;
	}

	public function add(point:Point):Point {
		var at = points.length;
		while (at > 0 && points[at - 1].at > point.at) at--;

		if (at > 0 && points[at - 1].at == point.at) {
			points[at - 1].value = point.value;
			return points[at - 1];
		}

		points.insert(at, point);
		return point;
	}

	public function marks(tick:Int):Bool {
		final at = seek(tick);
		return at < points.length && points[at].at == tick;
	}

	public function heldAt(tick:Int):Int {
		if (points.length == 0) return -1;

		final at = seek(tick + 1);
		return points[at < 1 ? 0 : at - 1].value;
	}

	public function seek(tick:Int):Int {
		var low = 0;
		var high = points.length;

		while (low < high) {
			final middle = (low + high) >> 1;

			if (points[middle].at < tick) low = middle + 1;
			else high = middle;
		}

		return low;
	}

	public function held(target:Int, slot:Int):Bool {
		return this.target == target && this.slot == slot;
	}

	public function valueAt(tick:Int):Int {
		if (points.length == 0) return -1;
		if (tick <= points[0].at) return points[0].value;

		var last = points[0];

		for (i in 1...points.length) {
			final point = points[i];
			if (point.at > tick) {
				final span = point.at - last.at;
				if (span <= 0) return point.value;

				final part = (tick - last.at) / span;
				return last.value + Std.int((point.value - last.value) * part);
			}
			last = point;
		}

		return last.value;
	}
}
