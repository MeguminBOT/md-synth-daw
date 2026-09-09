package mdd.app;

import mdd.song.Patch;

@:unreflective

/**
	Which MIDI controller turns which FM parameter, in eight slots.

	A slot names a channel wide dial or one field of one operator, so a knob box can be
	wired to a patch without anything in the editor knowing about MIDI.
**/
final class Mapping {
	/**
		How many slots there are.
	**/
	public static inline final SLOTS = 8;

	/**
		A slot that is not wired to anything.
	**/
	public static inline final NONE = -1;

	/**
		The slot drives a channel wide dial.
	**/
	public static inline final DIAL = 0;

	/**
		The slot drives one field of one operator.
	**/
	public static inline final OPERATOR = 1;

	static inline final CONTROLS = 128;

	static final PLAIN_CONTROLS:Array<Int> = [1, 7, 74, 71, 73, 72, 75, 70];
	static final PLAIN_KINDS:Array<Int> = [DIAL, OPERATOR, OPERATOR, DIAL, OPERATOR, OPERATOR,
		OPERATOR, DIAL];
	static final PLAIN_OPERATORS:Array<Int> = [0, 3, 0, 0, 3, 3, 3, 0];
	static final PLAIN_ROWS:Array<Int> = [Patch.PMS, 0, 0, Patch.FEEDBACK, 1, 5, 2,
		Patch.ALGORITHM];

	final controls:Array<Int> = [];
	final kinds:Array<Int> = [];
	final operators:Array<Int> = [];
	final rows:Array<Int> = [];

	/**
		Builds the mapping at its defaults.
	**/
	public function new() {
		forget();
	}

	/**
		Clears every slot.
	**/
	public function forget():Void {
		controls.resize(0);
		kinds.resize(0);
		operators.resize(0);
		rows.resize(0);

		for (index in 0...SLOTS) {
			controls.push(NONE);
			kinds.push(DIAL);
			operators.push(0);
			rows.push(0);
		}
	}

	/**
		Puts every slot back to a sensible default wiring.
	**/
	public function plain():Void {
		forget();

		for (slot in 0...SLOTS) {
			drives(slot, PLAIN_KINDS[slot], PLAIN_OPERATORS[slot], PLAIN_ROWS[slot]);
			hears(slot, PLAIN_CONTROLS[slot]);
		}
	}

	/**
		@param slot Which slot, 0 to 7.
		@return Which controller turns it, or `NONE`.
	**/
	public inline function controlOf(slot:Int):Int {
		return controls[slot];
	}

	/**
		@param slot Which slot, 0 to 7.
		@return `DIAL` or `OPERATOR`.
	**/
	public inline function kindOf(slot:Int):Int {
		return kinds[slot];
	}

	/**
		@param slot Which slot, 0 to 7.
		@return Which operator it drives, for an operator slot.
	**/
	public inline function operatorOf(slot:Int):Int {
		return operators[slot];
	}

	/**
		@param slot Which slot, 0 to 7.
		@return Which field it drives.
	**/
	public inline function rowOf(slot:Int):Int {
		return rows[slot];
	}

	/**
		@param slot Which slot, 0 to 7.
		@return Whether a controller reaches it.
	**/
	public inline function bound(slot:Int):Bool {
		return slot >= 0 && slot < SLOTS && controls[slot] != NONE;
	}

	/**
		Wires a controller to a slot, taking it off whatever else had it.

		@param slot Which slot, 0 to 7.
		@param control Which controller.
	**/
	public function hears(slot:Int, control:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;
		if (control < 0 || control >= CONTROLS) return;

		for (index in 0...SLOTS) {
			if (index != slot && controls[index] == control) controls[index] = NONE;
		}

		controls[slot] = control;
	}

	/**
		Says what a slot turns.

		@param slot Which slot, 0 to 7.
		@param kind `DIAL` or `OPERATOR`.
		@param op Which operator, for an operator slot.
		@param row Which field.
	**/
	public function drives(slot:Int, kind:Int, op:Int, row:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;

		final most = kind == DIAL ? Patch.DIALS : Patch.ROWS;

		kinds[slot] = kind == DIAL ? DIAL : OPERATOR;
		operators[slot] = op < 0 ? 0 : (op >= Patch.SLOTS ? Patch.SLOTS - 1 : op);

		rows[slot] = row < 0 ? 0 : (row >= most ? most - 1 : row);
	}

	/**
		Unwires a slot.

		@param slot Which slot, 0 to 7.
	**/
	public function clears(slot:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;

		controls[slot] = NONE;
		kinds[slot] = DIAL;
		operators[slot] = 0;
		rows[slot] = 0;
	}

	/**
		@param control A controller.
		@return Which slot it turns, or `NONE`.
	**/
	public function slotFor(control:Int):Int {
		for (index in 0...SLOTS) if (controls[index] == control) return index;
		return NONE;
	}

	/**
		@param slot Which slot, 0 to 7.
		@return The largest value the field it drives takes.
	**/
	public function most(slot:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;
		return kinds[slot] == DIAL ? Patch.mostDial(rows[slot]) : Patch.mostOf(rows[slot]);
	}

	/**
		@param patch The patch being turned.
		@param slot Which slot, 0 to 7.
		@return What the field it drives holds now.
	**/
	public function valueOf(patch:Patch, slot:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;

		return kinds[slot] == DIAL ? patch.dial(rows[slot])
			: patch.reads(operators[slot], rows[slot]);
	}

	/**
		Turns the field a slot drives.

		@param patch The patch to turn.
		@param slot Which slot, 0 to 7.
		@param value The controller value, 0 to 127.
		@return What the field ended up at.
	**/
	public function turns(patch:Patch, slot:Int, value:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;

		final want = scaled(slot, value);

		if (kinds[slot] == DIAL) patch.turns(rows[slot], want);
		else patch.writes(operators[slot], rows[slot], want);

		return want;
	}

	/**
		@param slot Which slot, 0 to 7.
		@param value A controller value, 0 to 127.
		@return It scaled into the range the field takes.
	**/
	public function scaled(slot:Int, value:Int):Int {
		final held = value < 0 ? 0 : (value > 127 ? 127 : value);
		final span = most(slot);

		return Math.round(held * span / 127.0);
	}

	/**
		@param slot Which slot, 0 to 7.
		@return What the field it drives is called.
	**/
	public function named(slot:Int):String {
		if (slot < 0 || slot >= SLOTS) return "";

		if (kinds[slot] == DIAL) return Patch.DIAL_SPELT[rows[slot]];
		return Patch.SPELT[rows[slot]] + " " + (operators[slot] + 1);
	}

	/**
		@return The whole mapping as one line, for the settings file.
	**/
	public function said():String {
		final out = new StringBuf();

		for (index in 0...SLOTS) {
			if (controls[index] == NONE) continue;

			if (out.length > 0) out.add(",");

			out.add(index + ":" + controls[index] + ":" + kinds[index] + ":"
				+ operators[index] + ":" + rows[index]);
		}

		return out.toString();
	}

	/**
		Reads a mapping back out of that line.

		@param from The line.
	**/
	public function reads(from:String):Void {
		forget();

		if (from == "") return;

		for (piece in from.split(",")) {
			final parts = piece.split(":");
			if (parts.length != 5) continue;

			final slot = Std.parseInt(parts[0]);
			final control = Std.parseInt(parts[1]);
			final kind = Std.parseInt(parts[2]);
			final op = Std.parseInt(parts[3]);
			final row = Std.parseInt(parts[4]);

			if (slot == null || control == null || kind == null) continue;
			if (op == null || row == null) continue;
			if (slot < 0 || slot >= SLOTS) continue;

			drives(slot, kind, op, row);
			hears(slot, control);
		}
	}
}
