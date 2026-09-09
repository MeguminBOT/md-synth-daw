package mdd.host;

@:unreflective

/**
	When the garbage collector is allowed to run.

	A collection stops every participating thread, so one landing in the middle of a
	frame is seen and one landing while a bounce runs is heard. This keeps them out of
	both by running a small collection when nothing is happening, and by never forcing
	a large one while a bounce is in progress: a bounce is a known large allocation
	rather than a leak.
**/
final class Collector {
	/**
		How much growth is allowed before a large collection is asked for.
	**/
	public static inline final CEILING = 64 * 1024 * 1024;

	/**
		How much growth is enough to be worth a small one.
	**/
	public static inline final ROUSE = 8 * 1024 * 1024;
	static inline final QUIET = 0.25;

	/**
		How many collections have been asked for.
	**/
	public var swept(default, null):Int = 0;

	/**
		How many of them were large.
	**/
	public var forced(default, null):Int = 0;

	/**
		The longest any of them took, in seconds.
	**/
	public var worst(default, null):Float = 0;

	/**
		How long the last one took.
	**/
	public var last(default, null):Float = 0;

	var idle:Float = 0;
	var settled:Float = 0;
	var minding:Bool = false;

	/**
		Builds a collector minder that is not yet minding.
	**/
	public function new() {}

	/**
		Takes the collector off its own schedule, so nothing collects except when asked
		here.
	**/
	public function minds():Void {
		if (minding) return;

		minding = true;
		settled = held();

		cpp.vm.Gc.enable(false);
	}

	/**
		Gives the collector its own schedule back, which is what a shutdown wants.
	**/
	public function leaves():Void {
		if (!minding) return;

		minding = false;
		cpp.vm.Gc.enable(true);
	}

	/**
		@return How much memory is in use, in megabytes.
	**/
	public inline function held():Float {
		return cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
	}

	/**
		@return How much has been allocated since the last collection, in megabytes.
	**/
	public inline function loose():Float {
		final now = held();
		return now > settled ? now - settled : 0;
	}

	/**
		Decides whether to collect now. Call once a frame.

		@param seconds How long since the last call.
		@param busy Whether something long is running, such as a bounce.
	**/
	public function rests(seconds:Float, busy:Bool):Void {
		if (!minding) return;

		final much = loose();

		if (much > CEILING) {
			forced++;
			sweeps(!busy);

			return;
		}

		if (busy) {
			idle = 0;
			return;
		}

		idle += seconds;
		if (idle < QUIET || much < ROUSE) return;

		sweeps(true);
	}

	/**
		Collects now and times it.

		@param major Whether to collect everything rather than only what is young.
	**/
	public function sweeps(major:Bool):Void {
		final began = Sdl.ticks();

		cpp.vm.Gc.run(major);

		last = Sdl.ticks() - began;
		if (last > worst) worst = last;

		settled = held();
		idle = 0;
		swept++;
	}

	/**
		@return A line for the status bar: what is held, how many collections and how long the worst
			took.
	**/
	public function said():String {
		return swept + " swept, " + forced + " forced, worst "
			+ Math.round(worst * 10000) / 10 + " ms";
	}
}
