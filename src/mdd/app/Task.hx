package mdd.app;

import haxe.atomic.AtomicInt;

@:unreflective
final class Task {
	public static inline final IDLE = 0;
	static inline final RUNNING = 1;
	static inline final DONE = 2;
	public static inline final FAILED = 3;

	static inline final UNKNOWN = -1;
	public static inline final WHOLE = 1000;

	public var label:Locale = 0;
	public var detail:String = "";
	public var said:String = "";

	public var cancellable:Bool = false;

	final held:AtomicInt = new AtomicInt(IDLE);
	final reached:AtomicInt = new AtomicInt(UNKNOWN);
	final stopping:AtomicInt = new AtomicInt(0);

	public function new() {}

	public function begins(label:Locale, detail:String, cancellable:Bool = false):Void {
		this.label = label;
		this.detail = detail;
		this.cancellable = cancellable;

		said = "";
		reached.store(UNKNOWN);
		stopping.store(0);
		held.store(RUNNING);
	}

	public inline function steps(done:Int, total:Int):Void {
		if (total <= 0) {
			reached.store(UNKNOWN);
			return;
		}

		var held = Std.int(done * WHOLE / total);
		if (held < 0) held = 0;
		if (held > WHOLE) held = WHOLE;

		reached.store(held);
	}

	public inline function holds(part:Float):Void {
		if (part < 0) reached.store(UNKNOWN);
		else steps(Std.int(part * WHOLE), WHOLE);
	}

	public function ends(ok:Bool, said:String = ""):Void {
		this.said = said;
		reached.store(WHOLE);
		held.store(ok ? DONE : FAILED);
	}

	public inline function state():Int {
		return held.load();
	}

	public inline function running():Bool {
		return held.load() == RUNNING;
	}

	public inline function settled():Bool {
		final now = held.load();
		return now == DONE || now == FAILED;
	}

	public inline function worked():Bool {
		return held.load() == DONE;
	}

	public function reach():Float {
		final now = reached.load();
		return now < 0 ? UNKNOWN : now / WHOLE;
	}

	public inline function cancels():Void {
		stopping.store(1);
	}

	public inline function stopped():Bool {
		return stopping.load() != 0;
	}

	public inline function forget():Void {
		held.store(IDLE);
	}
}
