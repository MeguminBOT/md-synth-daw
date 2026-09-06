package mdd.app;

import mdd.song.Patch;

@:unreflective
final class Mapping {
	public static inline final SLOTS = 8;
	public static inline final NONE = -1;

	public static inline final DIAL = 0;
	public static inline final OPERATOR = 1;

	public static inline final CONTROLS = 128;

	final controls:Array<Int> = [];
	final kinds:Array<Int> = [];
	final operators:Array<Int> = [];
	final rows:Array<Int> = [];

	public function new() {
		forget();
	}

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

	public inline function controlOf(slot:Int):Int {
		return controls[slot];
	}

	public inline function kindOf(slot:Int):Int {
		return kinds[slot];
	}

	public inline function operatorOf(slot:Int):Int {
		return operators[slot];
	}

	public inline function rowOf(slot:Int):Int {
		return rows[slot];
	}

	public inline function bound(slot:Int):Bool {
		return slot >= 0 && slot < SLOTS && controls[slot] != NONE;
	}

	public function hears(slot:Int, control:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;
		if (control < 0 || control >= CONTROLS) return;

		for (index in 0...SLOTS) {
			if (index != slot && controls[index] == control) controls[index] = NONE;
		}

		controls[slot] = control;
	}

	public function drives(slot:Int, kind:Int, op:Int, row:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;

		final most = kind == DIAL ? Patch.DIALS : Patch.ROWS;

		kinds[slot] = kind == DIAL ? DIAL : OPERATOR;
		operators[slot] = op < 0 ? 0 : (op >= Patch.SLOTS ? Patch.SLOTS - 1 : op);

		rows[slot] = row < 0 ? 0 : (row >= most ? most - 1 : row);
	}

	public function clears(slot:Int):Void {
		if (slot < 0 || slot >= SLOTS) return;

		controls[slot] = NONE;
		kinds[slot] = DIAL;
		operators[slot] = 0;
		rows[slot] = 0;
	}

	public function slotFor(control:Int):Int {
		for (index in 0...SLOTS) if (controls[index] == control) return index;
		return NONE;
	}

	public function most(slot:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;
		return kinds[slot] == DIAL ? Patch.mostDial(rows[slot]) : Patch.mostOf(rows[slot]);
	}

	public function valueOf(patch:Patch, slot:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;

		return kinds[slot] == DIAL ? patch.dial(rows[slot])
			: patch.reads(operators[slot], rows[slot]);
	}

	public function turns(patch:Patch, slot:Int, value:Int):Int {
		if (slot < 0 || slot >= SLOTS) return 0;

		final want = scaled(slot, value);

		if (kinds[slot] == DIAL) patch.turns(rows[slot], want);
		else patch.writes(operators[slot], rows[slot], want);

		return want;
	}

	public function scaled(slot:Int, value:Int):Int {
		final held = value < 0 ? 0 : (value > 127 ? 127 : value);
		final span = most(slot);

		return Math.round(held * span / 127.0);
	}

	public function named(slot:Int):String {
		if (slot < 0 || slot >= SLOTS) return "";

		if (kinds[slot] == DIAL) return Patch.DIAL_SPELT[rows[slot]];
		return Patch.SPELT[rows[slot]] + " " + (operators[slot] + 1);
	}

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
