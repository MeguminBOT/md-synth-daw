package mdd.host;

@:unreflective
final class Collector {
	public static inline final CEILING = 64 * 1024 * 1024;
	public static inline final ROUSE = 8 * 1024 * 1024;
	public static inline final QUIET = 0.25;

	public var swept(default, null):Int = 0;
	public var forced(default, null):Int = 0;
	public var worst(default, null):Float = 0;
	public var last(default, null):Float = 0;

	var idle:Float = 0;
	var settled:Float = 0;
	var minding:Bool = false;

	public function new() {}

	public function minds():Void {
		if (minding) return;

		minding = true;
		settled = held();

		cpp.vm.Gc.enable(false);
	}

	public function leaves():Void {
		if (!minding) return;

		minding = false;
		cpp.vm.Gc.enable(true);
	}

	public inline function held():Float {
		return cpp.vm.Gc.memInfo(cpp.vm.Gc.MEM_INFO_CURRENT);
	}

	public inline function loose():Float {
		final now = held();
		return now > settled ? now - settled : 0;
	}

	public function rests(seconds:Float, busy:Bool):Void {
		if (!minding) return;

		final much = loose();

		if (much > CEILING) {
			forced++;
			sweeps(true);

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

	public function sweeps(major:Bool):Void {
		final began = Sdl.ticks();

		cpp.vm.Gc.run(major);

		last = Sdl.ticks() - began;
		if (last > worst) worst = last;

		settled = held();
		idle = 0;
		swept++;
	}

	public function said():String {
		return swept + " swept, " + forced + " forced, worst "
			+ Math.round(worst * 10000) / 10 + " ms";
	}
}
