package mdd.gate;

import mdd.view.monitor.Scope;

@:unreflective

/**
	How much time a lane of the scope shows, how many samples it keeps, and where its window
	starts.

	A lane used to hold 512 samples at one in four, drawn one sample to a pixel from wherever a
	crossing fell, so a narrow lane showed less time than a wide one and a window could run past
	the newest sample into what was written a window earlier. Nothing here opens a window or a
	sound device.
**/
class ScopeCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	/**
		@param args The gate's arguments, unused.
		@return Nought where every check held.
	**/
	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  scope");

		timed();
		kept();
		started();
		held();
		windowed();
		smoothed();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function made():Scope {
		return new Scope(new mdd.app.Session(mdd.app.Session.empty(mdd.song.Library.embedded())));
	}

	/**
		Every speed shows the time it says at every accuracy, and the longest window is held to
		half a lane.
	**/
	static function timed():Void {
		final scope = made();
		scope.rated(48000);

		final said:Array<String> = [];

		for (accuracy in 0...Scope.STRIDES.length) {
			scope.refines(accuracy);

			final row:Array<Int> = [];

			for (speed in 0...Scope.SPEEDS.length) {
				scope.paces(speed);
				row.push(scope.window());
			}

			said.push(row.join(" "));
		}

		final windows = said.join(" / ");
		final want = "120 240 480 960 1920 / 240 480 960 1920 3840 / 480 960 1920 3840 7680";

		says("each speed shows the time it names", windows == want,
			"at 48000 Hz, low, medium and high hold " + windows + " samples");

		scope.rated(96000);
		scope.refines(Scope.STRIDES.length - 1);
		scope.paces(Scope.SPEEDS.length - 1);

		says("and the longest window is held to half a lane", scope.window() == Scope.SPAN / 2,
			"160 ms of every sample at 96000 Hz would be 15360, and the lane shows "
			+ scope.window() + " of the " + Scope.SPAN + " it holds");
	}

	/**
		The accuracy decides how many captured samples a lane keeps.
	**/
	static function kept():Void {
		final scope = made();
		final counts:Array<Int> = [];

		for (accuracy in [2, 0, 1]) {
			scope.refines(accuracy);

			final before = scope.written[0];
			for (step in 0...4000) scope.feed(0, 0.5);

			counts.push((scope.written[0] - before + Scope.SPAN) % Scope.SPAN);
		}

		final said = counts.join(" ");

		says("the accuracy decides how many samples a lane keeps", said == "4000 1000 2000",
			"4000 samples fed at high, low and medium kept " + said);
	}

	/**
		A window starts on an upward crossing and ends at or before the newest sample.
	**/
	static function started():Void {
		final scope = made();

		scope.rated(48000);
		scope.refines(2);
		scope.paces(0);

		final many = scope.window();

		for (step in 0...3000) {
			scope.feed(0, Math.sin(2 * Math.PI * 440 * step / 48000 + 1.0) * 0.8);
		}

		final start = scope.startOf(0);
		final crosses = scope.sampleAt(0, start - 1) < 0 && scope.sampleAt(0, start) >= 0;
		final ahead = (scope.written[0] - start + Scope.SPAN) % Scope.SPAN;
		final period = Math.ceil(48000 / 440);

		says("a window starts on an upward crossing", crosses,
			"the sample before the start is " + round(scope.sampleAt(0, start - 1))
			+ " and the start is " + round(scope.sampleAt(0, start)));

		says("and never runs past the newest sample", ahead >= many,
			"the window of " + many + " starts " + ahead + " samples before the newest one");

		says("and is the latest one that fits", ahead < many + period + 1,
			ahead + " samples back is within one period of " + period
			+ " of the latest start that fits");
	}

	/**
		A speed or accuracy read back from settings that is out of range lands on the nearest one.
	**/
	static function held():Void {
		final scope = made();
		final said:Array<Int> = [];

		scope.paces(99);
		said.push(scope.speed);
		scope.paces(-3);
		said.push(scope.speed);
		scope.refines(9);
		said.push(scope.accuracy);
		scope.refines(-1);
		said.push(scope.accuracy);

		final read = said.join(" ");

		says("a stored setting out of range lands on the nearest", read == "4 0 2 0",
			"speed 99 and -3, accuracy 9 and -1 read back as " + read);
	}

	/**
		A tone between two bars leaks across every other bar with no window, and a shaped window
		holds it to the bars beside it. With no shape every sample weighs one, so the bars are what
		they were before shapes existed.
	**/
	static function windowed():Void {
		final scope = made();

		scope.rated(48000);
		scope.refines(2);
		scope.paces(2);

		final many = scope.window();
		final hertz = 40 * Math.pow(8000 / 40, 10.5 / (Scope.BARS - 1.0));

		for (step in 0...Scope.SPAN) scope.feed(0, 0.5 * Math.sin(2 * Math.PI * hertz * step / 48000));

		final flat = leaked(scope, mdd.view.monitor.Windowing.NONE, many);
		final even = @:privateAccess scope.weighed == many;

		scope.windows(mdd.view.monitor.Windowing.HANN);
		final hann = leaked(scope, mdd.view.monitor.Windowing.HANN, many);

		scope.windows(mdd.view.monitor.Windowing.BLACKMAN);
		final blackman = leaked(scope, mdd.view.monitor.Windowing.BLACKMAN, many);

		says("a window holds a tone to its bars", even && hann < flat * 0.25
			&& blackman < flat * 0.25,
			"a tone between bars 10 and 11 leaks " + round(flat * 100) + " per cent of its peak into"
			+ " bars four or more away with no window, " + round(hann * 100) + " with Hann and "
			+ round(blackman * 100) + " with Blackman");
	}

	/**
		@param scope A scope holding a tone in its first lane.
		@param kind The shape it is set to.
		@param many How many samples its window holds.
		@return The largest bar four or more bars from the tone, against the largest bar.
	**/
	static function leaked(scope:Scope, kind:Int, many:Int):Float {
		final analysed = many < Scope.ANALYSED ? many : Scope.ANALYSED;
		final start = (scope.written[0] - analysed + Scope.SPAN) % Scope.SPAN;
		final most = @:privateAccess scope.bands(0, start, analysed);

		var far = 0.0;

		for (bin in 0...Scope.BARS) {
			if (bin > 6 && bin < 15) continue;

			final held = @:privateAccess scope.bins[bin];
			if (held > far) far = held;
		}

		return most <= 0 ? 1 : far / most;
	}

	/**
		A waveform smoothed with a shape keeps a slow tone and loses a fast one laid over it.
	**/
	static function smoothed():Void {
		final scope = made();

		scope.rated(48000);
		scope.refines(2);
		scope.paces(2);

		final many = scope.window();

		for (step in 0...Scope.SPAN) {
			scope.feed(0, 0.5 * Math.sin(2 * Math.PI * 100 * step / 48000)
				+ (step % 2 == 0 ? 0.4 : -0.4));
		}

		final start = scope.startOf(0);
		final rough = @:privateAccess scope.loudest(@:privateAccess scope.traces, 0, start, many);

		scope.smoothsWith(mdd.view.monitor.Windowing.GAUSSIAN, 9);
		@:privateAccess scope.soften(0, start, many);

		final smooth = @:privateAccess scope.loudest(@:privateAccess scope.smoothed, 0, 0, many);

		says("smoothing keeps the slow tone", rough > 0.85 && smooth > 0.45
			&& smooth < 0.55,
			"a 100 Hz tone at 0.5 under a buzz at half the rate peaks at " + round(rough)
			+ " as it is and " + round(smooth) + " smoothed over "
			+ scope.smoothingWidth + " samples with a Gaussian");
	}

	static function round(value:Float):Float {
		return Math.round(value * 10000) / 10000;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}
}
