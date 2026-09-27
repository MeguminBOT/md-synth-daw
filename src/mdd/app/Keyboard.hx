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
		Controller: every sound stops at once.
	**/
	public static inline final SOUND_OFF = 120;

	/**
		Controller: every key is let go.
	**/
	public static inline final NOTES_OFF = 123;

	/**
		Listen on every channel.
	**/
	public static inline final ANY = -1;

	/**
		Where the pitch wheel rests.
	**/
	public static inline final MIDDLE = 8192;

	/**
		How far the pitch wheel bends at either end, in cents: two semitones, which is where general
		MIDI starts a device.
	**/
	public static inline final BEND_RANGE = 200;

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
		The key a part with one voice should sound: the latest one still down or held by the pedal,
		or -1 when there is none.
	**/
	public var latest(default, null):Int = -1;

	/**
		The keys let go while the pedal was down, which it holds until it comes up.
	**/
	final sustained:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(128);

	/**
		The keys down or held by the pedal, oldest first, `depth` of them.
	**/
	final order:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(128);

	var depth:Int = 0;

	/**
		The velocity each key went down at.
	**/
	final velocities:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(128);

	/**
		The pitch each note number went down as, or -1 while it is up, so a key let go after the
		transpose changed lets go of what it sounded.
	**/
	final struck:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(128);

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
		Called with a note when it is let go. A key let go while the sustain pedal is down is held
		until the pedal comes up, and called then.
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
	public function new() {
		for (index in 0...128) {
			sustained[index] = false;
			velocities[index] = 0;
			struck[index] = -1;
		}
	}

	/**
		@param pitch A pitch that is down or held by the pedal.
		@return The velocity it went down at.
	**/
	public inline function velocityOf(pitch:Int):Int {
		return velocities[pitch & 127];
	}

	/**
		Lets go of every key, whether it is down or held by the pedal, and lifts the pedal. For a
		device that stops being listened to with keys still down, and for a keyboard's own all
		notes off. `latest` is -1 before the first key is let go.
	**/
	public function lets():Void {
		final count = depth;

		pedal = false;
		depth = 0;
		latest = -1;

		for (index in 0...128) struck[index] = -1;

		for (index in 0...count) {
			final pitch = order[index];

			sustained[pitch] = false;
			if (onRelease != null) onRelease(pitch);
		}
	}

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

				struck[one] = pitch;
				sustained[pitch] = false;
				velocities[pitch] = velocity < 1 ? 1 : velocity;
				leaves(pitch);
				order[depth++] = pitch;
				latest = pitch;

				if (onNote != null) onNote(pitch, velocities[pitch]);

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
					pedals(two >= 64);
				} else if (one == NOTES_OFF || one == SOUND_OFF) {
					lets();
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
		final pitch = struck[note];
		if (pitch < 0) return;

		struck[note] = -1;

		if (pedal) {
			sustained[pitch] = true;
			return;
		}

		leaves(pitch);
		if (onRelease != null) onRelease(pitch);
	}

	/**
		Takes a key out of the order and points `latest` at whatever is left on top.

		@param pitch The key.
	**/
	function leaves(pitch:Int):Void {
		var at = 0;
		while (at < depth && order[at] != pitch) at++;

		if (at < depth) {
			depth--;
			for (index in at...depth) order[index] = order[index + 1];
		}

		latest = depth > 0 ? order[depth - 1] : -1;
	}

	/**
		Puts the sustain pedal down or lets it up, and lets go of every key it was holding when it
		comes up. All of them leave the order before the first is let go, so a part with one voice
		falls back only to a key that is still down.

		@param down Whether it is down now.
	**/
	function pedals(down:Bool):Void {
		final lifted = pedal && !down;
		pedal = down;

		if (!lifted) return;

		for (pitch in 0...128) if (sustained[pitch]) leaves(pitch);

		for (pitch in 0...128) {
			if (!sustained[pitch]) continue;

			sustained[pitch] = false;
			if (onRelease != null) onRelease(pitch);
		}
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
