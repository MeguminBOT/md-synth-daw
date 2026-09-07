package mdd.app;

import mdd.ui.Key;
import mdd.ui.Mod;

@:unreflective
final class Bindings {
	public static inline final NONE = -1;

	public static inline final UNDO = 0;
	public static inline final REDO = 1;
	public static inline final NEW = 2;
	public static inline final OPEN = 3;
	public static inline final SAVE = 4;
	public static inline final PREFERENCES = 5;
	public static inline final PLAY = 6;
	public static inline final STOP = 7;
	public static inline final LOOP = 8;
	public static inline final WRITE_VGM = 9;
	public static inline final WRITE_AUDIO = 10;
	public static inline final EARLIER = 11;
	public static inline final LATER = 12;
	public static inline final SELECT = 13;
	public static inline final DRAW = 14;
	public static inline final ERASE = 15;
	public static inline final SLICE = 16;
	public static inline final PAN = 17;
	public static inline final ALL = 18;
	public static inline final COPY = 19;
	public static inline final CUT = 20;
	public static inline final PASTE = 21;
	public static inline final COUNT = 22;

	static final KEYS:Array<Key> = [
		Key.Z, Key.Y, Key.N, Key.O, Key.S, Key.Comma,
		Key.Space, Key.Space, Key.L, Key.E, Key.E,
		Key.Left, Key.Right,
		Key.E, Key.P, Key.D, Key.C, Key.H,
		Key.A, Key.C, Key.X, Key.V
	];

	static final MODS:Array<Int> = [
		Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl,
		Mod.None, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl | Mod.Shift,
		Mod.Ctrl, Mod.Ctrl,
		Mod.None, Mod.None, Mod.None, Mod.None, Mod.None,
		Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl
	];

	public static final NAMES:Array<Locale> = [
		Locale.BIND_UNDO, Locale.BIND_REDO, Locale.BIND_NEW, Locale.BIND_OPEN,
		Locale.BIND_SAVE, Locale.BIND_PREFERENCES, Locale.BIND_PLAY, Locale.BIND_STOP,
		Locale.BIND_LOOP, Locale.BIND_WRITE_VGM, Locale.BIND_WRITE_AUDIO,
		Locale.BIND_EARLIER, Locale.BIND_LATER,
		Locale.BIND_SELECT, Locale.BIND_DRAW, Locale.BIND_ERASE, Locale.BIND_SLICE,
		Locale.BIND_PAN,
		Locale.BIND_ALL, Locale.BIND_COPY, Locale.BIND_CUT, Locale.BIND_PASTE
	];

	final keys:Array<Key> = [];
	final mods:Array<Int> = [];

	public function new() {
		forget();
	}

	public function forget():Void {
		keys.resize(0);
		mods.resize(0);

		for (index in 0...COUNT) {
			keys.push(KEYS[index]);
			mods.push(MODS[index]);
		}
	}

	public inline function keyOf(action:Int):Key {
		return keys[action];
	}

	public inline function modOf(action:Int):Int {
		return mods[action];
	}

	public static function of(held:Null<Bindings>, action:Int):String {
		return held == null ? "" : held.shortcut(action);
	}

	public function shortcut(action:Int):String {
		if (action < 0 || action >= COUNT) return "";
		return keys[action].shortcut(mods[action]);
	}

	public function binds(action:Int, key:Key, mod:Int):Void {
		if (action < 0 || action >= COUNT) return;

		for (index in 0...COUNT) {
			if (index == action) continue;
			if (keys[index] != key || mods[index] != mod) continue;

			keys[index] = Key.Unknown;
			mods[index] = Mod.None;
		}

		keys[action] = key;
		mods[action] = mod;
	}

	public function restores(action:Int):Void {
		if (action < 0 || action >= COUNT) return;
		binds(action, KEYS[action], MODS[action]);
	}

	public inline function bound(action:Int):Bool {
		return action >= 0 && action < COUNT && keys[action] != Key.Unknown;
	}

	public function actionFor(key:Key, mod:Int):Int {
		final held = mod & (Mod.Ctrl | Mod.Alt | Mod.Shift);

		for (index in 0...COUNT) {
			if (keys[index] == Key.Unknown) continue;
			if (keys[index] == key && mods[index] == held) return index;
		}

		return NONE;
	}

	public function said():String {
		final out = new StringBuf();

		for (index in 0...COUNT) {
			if (keys[index] == KEYS[index] && mods[index] == MODS[index]) continue;

			if (out.length > 0) out.add(",");
			out.add(index + ":" + (keys[index] : Int) + ":" + mods[index]);
		}

		return out.toString();
	}

	public function reads(from:String):Void {
		forget();

		if (from == "") return;

		for (piece in from.split(",")) {
			final parts = piece.split(":");
			if (parts.length != 3) continue;

			final action = Std.parseInt(parts[0]);
			final key = Std.parseInt(parts[1]);
			final mod = Std.parseInt(parts[2]);

			if (action == null || key == null || mod == null) continue;
			if (action < 0 || action >= COUNT) continue;

			keys[action] = key;
			mods[action] = mod;
		}
	}
}
