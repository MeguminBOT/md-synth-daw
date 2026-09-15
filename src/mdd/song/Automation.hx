package mdd.song;

/**
	One automation lane: which register of which channel it drives, and the points that
	say what it holds over time.

	A register that carries two things has to have one writer. `$B4` holds the stereo
	bits and both LFO sensitivities, so the lane owns the whole byte: with the patch
	owning the sensitivities and the mixer owning the stereo, every key on wrote a byte
	assembled from both and the automation then wrote over it, which read as panning
	that would not stay put.
**/
@:unreflective
final class Automation {
	/**
		Lane: total level, so loudness.
	**/
	public static inline final LEVEL = 0;

	/**
		Lane: register `$B4` whole, so the stereo bits and both LFO sensitivities.
	**/
	public static inline final SIDES = 1;

	/**
		Lane: pitch, as an offset from the note.
	**/
	public static inline final TUNE = 2;

	/**
		Lane: detune and multiple.
	**/
	public static inline final TIMBRE = 3;

	/**
		Lane: rate scaling and attack rate.
	**/
	public static inline final ATTACK = 4;

	/**
		Lane: tremolo and decay rate.
	**/
	public static inline final DECAY = 5;

	/**
		Lane: sustain rate.
	**/
	public static inline final SUSTAIN = 6;

	/**
		Lane: sustain level and release rate.
	**/
	public static inline final RELEASE = 7;

	/**
		Lane: the SSG-EG shape.
	**/
	public static inline final LOOP = 8;

	/**
		Lane: the algorithm and the feedback.
	**/
	public static inline final WIRING = 9;

	/**
		Lane: which preset the notes play, as an index into the song's own instruments, which
		the project carries whole and in order, so the index means the same preset on any
		machine. It is not one register: from the first point on every note plays the preset
		held here, whatever instrument it names, and the whole patch is written at its key on,
		which is how a driver changes voice. Before the first point a note plays what it names
		or what the rack holds. The converter has no such lane, because a kit picks its hit by
		the instrument each note names.
	**/
	public static inline final INSTRUMENT = 10;

	/**
		The register base each lane writes to, or nought for a lane that is not one
		register.
	**/
	public static final BASES:Array<Int> = [0x40, 0, 0, 0x30, 0x50, 0x60, 0x70, 0x80, 0x90,
		0xB0, 0];

	/**
		@param target A lane index.
		@return Whether it writes a per operator register rather than a per channel one.
	**/
	public static inline function operates(target:Int):Bool {
		return target == LEVEL || (target >= TIMBRE && target <= WIRING);
	}

	/**
		How many operators a slot may name. A lane that writes a per channel register
		leaves it at nought.
	**/
	public static inline final SLOTS = 4;

	/**
		How many points a lane may hold before it stops taking them.
	**/
	public static inline final ROOM = 8192;

	/**
		Shape: hold the value until the next point.
	**/
	public static inline final HOLD = 0;

	/**
		Shape: a straight line to the next point.
	**/
	public static inline final LINEAR = 1;

	/**
		Shape: a curve whose bend is the tension.
	**/
	public static inline final CURVE = 2;

	/**
		Shape: ease in and out.
	**/
	public static inline final SMOOTH = 3;

	/**
		Shape: a fixed number of equal steps.
	**/
	public static inline final STAIRS = 4;
	static inline final SMOOTH_STAIRS = 5;

	/**
		Shape: square between the two values.
	**/
	public static inline final PULSE = 6;

	/**
		Shape: a full sine between them.
	**/
	public static inline final WAVE = 7;

	/**
		Shape: half a sine between them.
	**/
	public static inline final HALF_SINE = 8;

	/**
		How many shapes there are.
	**/
	public static inline final SHAPES = 9;

	/**
		How many steps a stepped shape takes by default.
	**/
	public static inline final REPEATS = 4;

	/**
		The most steps a stepped shape may take.
	**/
	public static inline final MOST_REPEATS = 64;

	/**
		The hardest a curve may bend.
	**/
	public static inline final MOST_TENSION = 100;

	/**
		@param shape A shape.
		@return Whether it repeats a number of times rather than reaching the next point once.
	**/
	public static inline function stepped(shape:Int):Bool {
		return shape == STAIRS || shape == SMOOTH_STAIRS || shape == PULSE || shape == WAVE;
	}

	/**
		@param shape A shape.
		@return Whether it changes at all between the two points, as against holding.
	**/
	public static inline function moves(shape:Int):Bool {
		return shape != HOLD;
	}

	/**
		Which channel this lane drives, or -1 for the part's own.
	**/
	public var target:Int;

	/**
		Which lane of that channel, and for an operator lane which operator, packed in.
	**/
	public var slot:Int;

	/**
		The points, kept in tick order.
	**/
	public final points:Array<Point> = [];

	/**
		Builds an empty lane.

		@param target Which channel it drives, or -1 for the part's own.
		@param slot Which lane of that channel.
	**/
	public function new(target:Int, slot:Int = 0) {
		this.target = target;
		this.slot = slot;
	}

	/**
		Puts a point in, in tick order, unless the lane is full.

		@param point The point to add.
		@return The same point.
	**/
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

	/**
		Takes a point out.

		@param point The point to remove.
		@return False where it was not in this lane.
	**/
	public function remove(point:Point):Bool {
		return points.remove(point);
	}

	/**
		Puts the points back in tick order, which moving one can break.
	**/
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

	/**
		@param tick A tick.
		@return The point closest to it, or null where the lane is empty.
	**/
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

	/**
		@param tick A tick.
		@return Whether a point sits exactly there.
	**/
	public function marks(tick:Int):Bool {
		final at = seek(tick);
		return at < points.length && points[at].at == tick;
	}

	/**
		@param tick A tick.
		@return The value of the last point at or before it, without following any curve.
	**/
	public function heldAt(tick:Int):Int {
		if (points.length == 0) return -1;

		final at = seek(tick + 1);
		return points[at < 1 ? 0 : at - 1].value;
	}

	/**
		Finds a point by search rather than by walking every one, so a long lane costs
		no more to read than a short one.

		@param tick A tick.
		@return The index of the first point at or after it.
	**/
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

	/**
		@param target A channel, or -1.
		@param slot A lane of it.
		@return Whether this is that lane.
	**/
	public function held(target:Int, slot:Int):Bool {
		return this.target == target && this.slot == slot;
	}

	/**
		@param tick A tick.
		@return The value the lane holds there, following the curve between points.
	**/
	public function valueAt(tick:Int):Int {
		if (points.length == 0) return -1;
		if (tick <= points[0].at) return points[0].value;

		final at = seek(tick + 1);
		final from = points[at < 1 ? 0 : at - 1];

		if (at >= points.length) return from.value;

		return between(from, points[at], tick);
	}

	/**
		@param from The point the curve starts at.
		@param to The point it reaches.
		@param tick A tick between the two.
		@return The value there, under the first point shape.
	**/
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

	/**
		@param part How far between the two points, 0 to 1.
		@param tension How hard the curve bends, signed.
		@return That position bent by the tension.
	**/
	static function warped(part:Float, tension:Int):Float {
		if (tension == 0) return part;

		var much = tension / MOST_TENSION;
		if (much < -1) much = -1;
		if (much > 1) much = 1;

		if (much > 0) return Math.pow(part, 1 + much * 3);
		return 1 - Math.pow(1 - part, 1 - much * 3);
	}

	/**
		@param shape Which curve.
		@param part How far between the two points, 0 to 1.
		@param repeats How many steps a stepped shape takes.
		@return How far towards the second value the curve has reached, 0 to 1.
	**/
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
