package mdd.song;

/**
	A square channel envelope: a list of attenuation steps, how fast they run, where
	they loop, and which noise mode goes with them.

	The FM part has envelopes in hardware. The squares do not, so a driver runs one by
	writing the attenuation register on a timer, and this is that list of writes.
**/
@:unreflective
final class Envelope {
	/**
		The attenuation at each step, 0 loudest and 15 silent.
	**/
	public final steps:Array<Int> = [];

	/**
		Which step to return to when the end is reached, or -1 to stop there.
	**/
	public var loop:Int = -1;

	/**
		How many frames each step lasts.
	**/
	public var speed:Int = 1;

	/**
		The noise control nibble to use when this envelope plays on the noise channel.
	**/
	public var noise:Int = 4;

	/**
		How many steps an envelope may hold.
	**/
	public static inline final LENGTH = 32;

	/**
		Dial: which step to return to, or none to stop at the end.
	**/
	public static inline final LOOP = 0;

	/**
		Dial: how many frames each step lasts.
	**/
	public static inline final SPEED = 1;

	/**
		Dial: the noise control nibble, for an envelope on the noise channel.
	**/
	public static inline final NOISE = 2;

	/**
		How many dials there are.
	**/
	public static inline final DIALS = 3;

	public function new() {}

	/**
		@param which Which dial.
		@return The largest value it takes.
	**/
	public static function mostDial(which:Int):Int {
		return switch (which) {
			case LOOP: LENGTH - 1;
			case SPEED: 16;
			case _: 7;
		}
	}

	/**
		@param which Which dial.
		@return What it holds. The loop answers -1 where the envelope stops at its end
			rather than returning to a step.
	**/
	public function dial(which:Int):Int {
		return switch (which) {
			case LOOP: loop;
			case SPEED: speed;
			case _: noise;
		}
	}

	/**
		Turns one dial, holding the value to what that dial takes.

		@param which Which dial.
		@param value What to turn it to.
	**/
	public function turns(which:Int, value:Int):Void {
		final most = mostDial(which);
		final least = which == LOOP ? -1 : (which == SPEED ? 1 : 0);
		final want = value < least ? least : (value > most ? most : value);

		switch (which) {
			case LOOP: loop = want;
			case SPEED: speed = want;
			case _: noise = want;
		}
	}

	/**
		@param step How far into the envelope, in steps.
		@return The attenuation there, following the loop, or full silence past the end of an
			envelope that does not loop.
	**/
	public function at(step:Int):Int {
		if (steps.length == 0) return 0;
		if (step < steps.length) return steps[step];
		if (loop < 0 || loop >= steps.length) return steps[steps.length - 1];

		final over = steps.length - loop;
		return steps[loop + (step - steps.length) % over];
	}

	/**
		@return A new envelope with the same steps and settings.
	**/
	public function copy():Envelope {
		final out = new Envelope();
		for (value in steps) out.steps.push(value);
		out.loop = loop;
		out.speed = speed;
		out.noise = noise;
		return out;
	}
}
