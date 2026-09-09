package mdd.app;

@:unreflective

/**
	A MIDI keyboard: what its messages mean and what to do with them.

	It unpacks messages and calls out; it never touches a chip or a stream, because a
	note has to reach the same producer of register writes everything else does.
**/
final class Keyboard {
	/**
		Status: a note was released.
	**/
	public static inline final NOTE_OFF = 0x80;

	/**
		Status: a note was struck.
	**/
	public static inline final NOTE_ON = 0x90;
	static inline final TOUCH = 0xA0;

	/**
		Status: a controller moved.
	**/
	public static inline final CONTROL = 0xB0;
	static inline final PROGRAM = 0xC0;
	static inline final PRESSURE = 0xD0;

	/**
		Status: the pitch wheel moved.
	**/
	public static inline final BEND = 0xE0;

	/**
		Controller: the modulation wheel.
	**/
	public static inline final WHEEL = 1;

	/**
		Controller: the sustain pedal.
	**/
	public static inline final SUSTAIN = 64;

	/**
		Listen on every channel.
	**/
	public static inline final ANY = -1;

	/**
		Where the pitch wheel rests.
	**/
	public static inline final MIDDLE = 8192;

	/**
		Which channel to listen on, or `ANY`.
	**/
	public var channel:Int = ANY;

	/**
		Whether every note sounds at the same velocity rather than the one played.
	**/
	public var forces:Bool = false;

	/**
		That velocity.
	**/
	public var forced:Int = 100;

	/**
		Semitones to shift every note by.
	**/
	public var transpose:Int = 0;

	/**
		Where the pitch wheel is, minus one to one.
	**/
	public var bend:Float = 0;

	/**
		Where the modulation wheel is, 0 to 1.
	**/
	public var wheel:Float = 0;

	/**
		Whether the sustain pedal is down.
	**/
	public var pedal:Bool = false;

	/**
		The last message, for the status line.
	**/
	public var said:String = "";

	/**
		How many messages have been taken.
	**/
	public var taken:Int = 0;

	/**
		Called with a note and a velocity when a key goes down.
	**/
	public var onNote:Null<Int -> Int -> Void> = null;

	/**
		Called with a note when it is let go, or when the pedal is.
	**/
	public var onRelease:Null<Int -> Void> = null;

	/**
		Called when the pitch wheel moves.
	**/
	public var onBend:Null<Float -> Void> = null;

	/**
		Called when the modulation wheel moves.
	**/
	public var onWheel:Null<Float -> Void> = null;

	/**
		Called with a controller and a value for anything else.
	**/
	public var onControl:Null<Int -> Int -> Void> = null;

	/**
		Builds a keyboard listening on every channel.
	**/
	public function new() {}

	/**
		Takes every message waiting on the open port. Call once a frame.

		@return How many were taken.
	**/
	public function drains():Int {
		var many = 0;

		while (true) {
			final message = mdd.host.Midi.take();
			if (message == mdd.host.Midi.EMPTY) break;

			if (takes(message)) many++;
		}

		return many;
	}

	/**
		Unpacks one message and calls whatever it means.

		@param message The message, packed into one value.
		@return Whether it meant anything.
	**/
	public function takes(message:Int):Bool {
		if (message < 0) return false;

		final status = message & 0xFF;
		if (status < 0x80) return false;

		final kind = status & 0xF0;
		if (kind == 0xF0) return false;

		if (channel != ANY && (status & 0x0F) != channel) return false;

		final one = (message >> 8) & 0x7F;
		final two = (message >> 16) & 0x7F;

		taken++;
		said = spelt(kind, one, two);

		switch (kind) {
			case NOTE_ON:
				if (two == 0) {
					released(one);
					return true;
				}

				final velocity = forces ? forced : two;
				final pitch = one + transpose;

				if (pitch < 0 || pitch > 127) return false;
				if (onNote != null) onNote(pitch, velocity < 1 ? 1 : velocity);

			case NOTE_OFF:
				released(one);

			case BEND:
				bend = ((one | (two << 7)) - MIDDLE) / MIDDLE;
				if (onBend != null) onBend(bend);

			case CONTROL:
				if (one == WHEEL) {
					wheel = two / 127.0;
					if (onWheel != null) onWheel(wheel);
				} else if (one == SUSTAIN) {
					pedal = two >= 64;
				}

				if (onControl != null) onControl(one, two);

			default:
		}

		return true;
	}

	/**
		Lets a note go, unless the pedal is holding it.

		@param note The MIDI note number.
	**/
	function released(note:Int):Void {
		final pitch = note + transpose;

		if (pitch < 0 || pitch > 127) return;
		if (onRelease != null) onRelease(pitch);
	}

	static function spelt(kind:Int, one:Int, two:Int):String {
		return switch (kind) {
			case NOTE_ON: two == 0 ? "note off " + one : "note on " + one + " at " + two;
			case NOTE_OFF: "note off " + one;
			case BEND: "bend " + (((one | (two << 7)) - MIDDLE));
			case CONTROL: "control " + one + " at " + two;
			case PROGRAM: "program " + one;
			case TOUCH: "touch " + one + " at " + two;
			case PRESSURE: "pressure " + one;
			default: "message " + kind;
		}
	}
}
