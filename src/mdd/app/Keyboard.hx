package mdd.app;

@:unreflective
final class Keyboard {
	public static inline final NOTE_OFF = 0x80;
	public static inline final NOTE_ON = 0x90;
	static inline final TOUCH = 0xA0;
	public static inline final CONTROL = 0xB0;
	static inline final PROGRAM = 0xC0;
	static inline final PRESSURE = 0xD0;
	public static inline final BEND = 0xE0;

	public static inline final WHEEL = 1;
	public static inline final SUSTAIN = 64;

	public static inline final ANY = -1;
	public static inline final MIDDLE = 8192;

	public var channel:Int = ANY;
	public var forces:Bool = false;
	public var forced:Int = 100;
	public var transpose:Int = 0;

	public var bend:Float = 0;
	public var wheel:Float = 0;
	public var pedal:Bool = false;

	public var said:String = "";
	public var taken:Int = 0;

	public var onNote:Null<Int -> Int -> Void> = null;
	public var onRelease:Null<Int -> Void> = null;
	public var onBend:Null<Float -> Void> = null;
	public var onWheel:Null<Float -> Void> = null;
	public var onControl:Null<Int -> Int -> Void> = null;

	public function new() {}

	public function drains():Int {
		var many = 0;

		while (true) {
			final message = mdd.host.Midi.take();
			if (message == mdd.host.Midi.EMPTY) break;

			if (takes(message)) many++;
		}

		return many;
	}

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
