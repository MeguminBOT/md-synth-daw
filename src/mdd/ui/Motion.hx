package mdd.ui;

@:unreflective
final class Motion {
	static inline final QUICK = 0.120;
	public static inline final ENTER = 0.180;
	static inline final LEAVING = 0.70;

	public var value(default, null):Float;
	public var from(default, null):Float;
	public var to(default, null):Float;
	public var duration(default, null):Float = 0;
	public var elapsed(default, null):Float = 0;
	public var moves(default, null):Bool;
	var reshapes(default, null):Bool;
	public var running(default, null):Bool = false;

	var onSettle:Null<Motion -> Void> = null;

	final subject:Null<Widget>;

	public function new(subject:Null<Widget>, start:Float = 0, moves:Bool = false,
			reshapes:Bool = false) {
		this.subject = subject;
		this.moves = moves;
		this.reshapes = reshapes;
		value = start;
		from = start;
		to = start;
	}

	public static inline function ease(part:Float):Float {
		final left = 1 - part;
		return 1 - left * left * left;
	}

	public static inline function leaving(duration:Float):Float {
		return duration * LEAVING;
	}

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

	inline function wake():Void {
		if (subject == null) return;
		if (reshapes) subject.relayout();
		else subject.invalidate();
	}

	public function settle():Void {
		final was = value;
		value = to;
		from = to;
		elapsed = duration;
		running = false;

		if (was != value) wake();
		if (onSettle != null) onSettle(this);
	}

	public function hold(at:Float):Void {
		value = at;
		from = at;
		to = at;
		elapsed = 0;
		running = false;
	}
}
