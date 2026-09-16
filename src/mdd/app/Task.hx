package mdd.app;

import mdd.host.Atomic;

@:unreflective

/**
	One long thing running, and how far through it is.

	Everything in it is atomic, because the thing running is usually on another thread
	and the progress bar is being drawn on this one. A reach of less than nought means
	nobody knows how far through it is, which is what makes the bar sweep instead of
	filling.
**/
final class Task {
	/**
		State: nothing is running.
	**/
	public static inline final IDLE = 0;
	static inline final RUNNING = 1;
	static inline final DONE = 2;

	/**
		State: it finished and did not work.
	**/
	public static inline final FAILED = 3;

	static inline final UNKNOWN = -1;

	/**
		What a finished task counts up to.
	**/
	public static inline final WHOLE = 1000;

	/**
		What the task is called.
	**/
	public var label:Locale = 0;

	/**
		A second line, usually the file being written.
	**/
	public var detail:String = "";

	/**
		What it said when it finished.
	**/
	public var said:String = "";

	/**
		Whether it can be stopped part way.
	**/
	public var cancellable:Bool = false;

	final held:Atomic = new Atomic(IDLE);
	final reached:Atomic = new Atomic(UNKNOWN);
	final stopping:Atomic = new Atomic(0);

	/**
		Builds a task that is not running.
	**/
	public function new() {}

	/**
		Starts the task, forgetting whatever the last one left behind.

		@param label What to call it.
		@param detail A second line.
		@param cancellable Whether it can be stopped.
	**/
	public function begins(label:Locale, detail:String, cancellable:Bool = false):Void {
		this.label = label;
		this.detail = detail;
		this.cancellable = cancellable;

		said = "";
		reached.store(UNKNOWN);
		stopping.store(0);
		held.store(RUNNING);
	}

	/**
		Says how far through it is, as a count.

		@param done How much is done.
		@param total How much there is. Nought or less means nobody knows.
	**/
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

	/**
		Says how far through it is, as a fraction.

		@param part How far, 0 to 1. Below nought means nobody knows.
	**/
	public inline function holds(part:Float):Void {
		if (part < 0) reached.store(UNKNOWN);
		else steps(Std.int(part * WHOLE), WHOLE);
	}

	/**
		Finishes the task.

		@param ok Whether it worked.
		@param said What to say about it.
	**/
	public function ends(ok:Bool, said:String = ""):Void {
		this.said = said;
		reached.store(WHOLE);
		held.store(ok ? DONE : FAILED);
	}

	/**
		@return Which of the four states it is in.
	**/
	public inline function state():Int {
		return held.load();
	}

	/**
		@return Whether it is running now.
	**/
	public inline function running():Bool {
		return held.load() == RUNNING;
	}

	/**
		@return Whether it has finished, either way.
	**/
	public inline function settled():Bool {
		final now = held.load();
		return now == DONE || now == FAILED;
	}

	/**
		@return Whether it finished and worked.
	**/
	public inline function worked():Bool {
		return held.load() == DONE;
	}

	/**
		@return How far through it is, 0 to 1, or a negative number where nobody knows.
	**/
	public function reach():Float {
		final now = reached.load();
		return now < 0 ? UNKNOWN : now / WHOLE;
	}

	/**
		Asks it to stop. Safe from any thread; whatever is running has to notice.
	**/
	public inline function cancels():Void {
		stopping.store(1);
	}

	/**
		@return Whether it has been asked to stop.
	**/
	public inline function stopped():Bool {
		return stopping.load() != 0;
	}

	/**
		Puts it back to idle.
	**/
	public inline function forget():Void {
		held.store(IDLE);
	}
}
