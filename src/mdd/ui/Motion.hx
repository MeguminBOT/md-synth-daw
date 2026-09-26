package mdd.ui;

@:unreflective

/**
	One animated number: where it is, where it is going, and how long it has left.

	It wakes the widget that owns it while it runs, so an animation redraws without
	anything having to poll for one, and it settles to its target and stops rather than
	running for ever.
**/
final class Motion {
	/**
		How long something takes to arrive. Leaving is faster, because waiting for a thing
		to go is worse than waiting for it to come.
	**/
	public static inline final ENTER = 0.180;
	static inline final LEAVING = 0.70;

	/**
		Where it is now.
	**/
	public var value(default, null):Float;

	/**
		Where it started.
	**/
	public var from(default, null):Float;

	/**
		Where it is going.
	**/
	public var to(default, null):Float;

	/**
		How long the whole run takes.
	**/
	public var duration(default, null):Float = 0;

	/**
		How much of that has passed.
	**/
	public var elapsed(default, null):Float = 0;

	/**
		Whether this one animates at all, or jumps straight to its target.
	**/
	public var moves(default, null):Bool;
	var reshapes(default, null):Bool;

	/**
		Whether it is moving now.
	**/
	public var running(default, null):Bool = false;

	var onSettle:Null<Motion -> Void> = null;

	final subject:Null<Widget>;

	/**
		Builds a motion that wakes a widget while it runs.

		@param subject The widget to wake, or null for none.
		@param start Where it begins.
		@param moves Whether it animates rather than jumping.
		@param reshapes Whether a change here has to lay the widget out again rather than only
			redraw it.
	**/
	public function new(subject:Null<Widget>, start:Float = 0, moves:Bool = false,
			reshapes:Bool = false) {
		this.subject = subject;
		this.moves = moves;
		this.reshapes = reshapes;
		value = start;
		from = start;
		to = start;
	}

	/**
		@param part How far through, 0 to 1.
		@return How far along the curve that is.
	**/
	public static inline function ease(part:Float):Float {
		final left = 1 - part;
		return 1 - left * left * left;
	}

	/**
		@param duration How long arriving takes.
		@return How long leaving should take, which is less.
	**/
	public static inline function leaving(duration:Float):Float {
		return duration * LEAVING;
	}

	/**
		Starts a run towards a value.

		@param target Where to go.
		@param duration How long to take.
		@param flow How much motion the interface is allowed. `None` jumps.
		@return False where it is already there.
	**/
	public function run(target:Float, duration:Float, flow:Flow):Bool {
		to = target;

		if (duration <= 0 || flow == Flow.None || (flow == Flow.Reduced && moves)) {
			settle();
			return false;
		}

		if (value == target) {
			settle();
			return false;
		}

		from = value;
		this.duration = duration;
		elapsed = 0;
		running = true;
		return true;
	}

	/**
		Moves it on. Call once a frame while it runs.

		@param seconds How long since the last call.
	**/
	public function advance(seconds:Float):Void {
		if (!running) return;

		elapsed += seconds;

		if (elapsed >= duration) {
			settle();
			return;
		}

		value = from + (to - from) * ease(elapsed / duration);
		wake();
	}

	/**
		Asks whatever owns this to redraw, because the value has moved.
	**/
	inline function wake():Void {
		if (subject == null) return;
		if (reshapes) subject.relayout();
		else subject.invalidate();
	}

	/**
		Jumps to the target and stops.
	**/
	public function settle():Void {
		final was = value;
		value = to;
		from = to;
		elapsed = duration;
		running = false;

		if (was != value) wake();
		if (onSettle != null) onSettle(this);
	}

	/**
		Puts it at a value and stops, with nothing animating.

		@param at Where to hold it.
	**/
	public function hold(at:Float):Void {
		value = at;
		from = at;
		to = at;
		elapsed = 0;
		running = false;
	}
}
