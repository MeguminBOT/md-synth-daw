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

	public static inline final HOLD = 0;
	public static inline final LINEAR = 1;
	public static inline final CURVE = 2;
	public static inline final SMOOTH = 3;
	public static inline final STAIRS = 4;
	public static inline final SMOOTH_STAIRS = 5;
	public static inline final PULSE = 6;
	public static inline final WAVE = 7;
	public static inline final HALF_SINE = 8;
	public static inline final SHAPES = 9;

	public static inline final REPEATS = 4;
	public static inline final MOST_REPEATS = 64;
	public static inline final MOST_TENSION = 100;

	public static inline function stepped(shape:Int):Bool {
		return shape == STAIRS || shape == SMOOTH_STAIRS || shape == PULSE || shape == WAVE;
	}

	public static inline function moves(shape:Int):Bool {
		return shape != HOLD;
	}

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

	public function remove(point:Point):Bool {
		return points.remove(point);
	}

	public function sort():Void {
		for (index in 1...points.length) {
			final point = points[index];
			var at = index;

			while (at > 0 && points[at - 1].at > point.at) {
				points[at] = points[at - 1];
				at--;
			}

			points[at] = point;
		}
	}

	public function nearest(tick:Int):Null<Point> {
		if (points.length == 0) return null;

		var found = points[0];
		var least = tick - found.at;
		if (least < 0) least = -least;

		for (point in points) {
			var away = tick - point.at;
			if (away < 0) away = -away;

			if (away >= least) continue;

			least = away;
			found = point;
		}

		return found;
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

		final at = seek(tick + 1);
		final from = points[at < 1 ? 0 : at - 1];

		if (at >= points.length) return from.value;

		return between(from, points[at], tick);
	}

	public static function between(from:Point, to:Point, tick:Int):Int {
		if (from.shape == HOLD) return from.value;

		final span = to.at - from.at;
		if (span <= 0) return to.value;

		var part = (tick - from.at) / span;
		if (part < 0) part = 0;
		if (part > 1) part = 1;

		final much = shaped(from.shape, warped(part, from.tension), from.repeats());
		return from.value + Math.round((to.value - from.value) * much);
	}

	public static function warped(part:Float, tension:Int):Float {
		if (tension == 0) return part;

		var much = tension / MOST_TENSION;
		if (much < -1) much = -1;
		if (much > 1) much = 1;

		if (much > 0) return Math.pow(part, 1 + much * 3);
		return 1 - Math.pow(1 - part, 1 - much * 3);
	}

	public static function shaped(shape:Int, part:Float, repeats:Int):Float {
		return switch (shape) {
			case LINEAR: part;
			case CURVE: part;
			case SMOOTH: part * part * (3 - 2 * part);
			case HALF_SINE: 0.5 - 0.5 * Math.cos(Math.PI * part);

			case STAIRS:
				final held = Math.floor(part * repeats);
				(held > repeats ? repeats : held) / repeats;

			case SMOOTH_STAIRS:
				final reach = part * repeats;
				final held = Math.floor(reach);
				final inner = reach - held;

				(held + inner * inner * (3 - 2 * inner)) / repeats;

			case PULSE:
				Math.floor(part * repeats * 2) % 2 == 0 ? 0.0 : 1.0;

			case WAVE:
				0.5 - 0.5 * Math.cos(2 * Math.PI * part * repeats);

			case _: 0.0;
		}
	}
}
