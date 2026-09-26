package mdd.app;

import mdd.ui.Key;
import mdd.ui.Mod;

@:unreflective

/**
	Which chord runs which action, and what a menu shows beside its entries.

	Every binding can be changed and put back, and the defaults live here rather than
	being scattered across the menus that show them.

	An action is heard everywhere, or only in the editors it names. An editor with the keyboard
	asks for its own actions first, so one of them can share a chord with an action heard
	everywhere and wins while that editor has the keyboard. Two actions heard in the same place
	cannot share a chord. What every application does the same stays fixed rather than being
	listed here: the arrow keys moving a cursor, Home, End, Page Up and Page Down, Delete,
	Escape, Enter and Tab.
**/
final class Bindings {
	/**
		No action.
	**/
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
	public static inline final DOUBLE = 22;
	public static inline final FOLLOW = 23;
	public static inline final NOTES_EARLIER = 24;
	public static inline final NOTES_LATER = 25;
	public static inline final TRANSPOSE_UP = 26;
	public static inline final TRANSPOSE_DOWN = 27;
	public static inline final OCTAVE_UP = 28;
	public static inline final OCTAVE_DOWN = 29;
	public static inline final LOUDER = 30;
	public static inline final QUIETER = 31;
	public static inline final TRACKER_LOUDER = 32;
	public static inline final TRACKER_QUIETER = 33;
	public static inline final TRACKER_OCTAVE_UP = 34;
	public static inline final TRACKER_OCTAVE_DOWN = 35;
	public static inline final TRACKER_FINER = 36;
	public static inline final TRACKER_COARSER = 37;
	public static inline final TRACKER_CUT = 38;

	/**
		How many actions there are. A new one goes on the end, because a saved binding names its
		action by this position.
	**/
	public static inline final COUNT = 39;

	/**
		Where an action is heard: everywhere, once nothing with the keyboard has taken the chord.
	**/
	public static inline final GLOBAL = 0;

	/**
		Where an action is heard: the piano roll, while it has the keyboard.
	**/
	public static inline final ROLL = 1;

	/**
		Where an action is heard: the playlist, while it has the keyboard.
	**/
	public static inline final PLAYLIST = 2;

	/**
		Where an action is heard: the tracker, while it has the keyboard.
	**/
	public static inline final TRACKER = 4;

	static final SCOPES:Array<Int> = [
		GLOBAL, GLOBAL, GLOBAL, GLOBAL, GLOBAL, GLOBAL,
		GLOBAL, GLOBAL, GLOBAL, GLOBAL, GLOBAL,
		GLOBAL, GLOBAL,
		GLOBAL, GLOBAL, GLOBAL, GLOBAL, GLOBAL,
		GLOBAL, GLOBAL, GLOBAL, GLOBAL, GLOBAL,
		GLOBAL,
		ROLL, ROLL, ROLL | PLAYLIST, ROLL | PLAYLIST, ROLL, ROLL, ROLL, ROLL,
		TRACKER, TRACKER, TRACKER, TRACKER, TRACKER, TRACKER, TRACKER
	];

	static final KEYS:Array<Key> = [
		Key.Z, Key.Y, Key.N, Key.O, Key.S, Key.Comma,
		Key.Space, Key.Space, Key.L, Key.E, Key.E,
		Key.Left, Key.Right,
		Key.E, Key.P, Key.D, Key.C, Key.H,
		Key.A, Key.C, Key.X, Key.V, Key.B,
		Key.Unknown,
		Key.Left, Key.Right, Key.Up, Key.Down, Key.Up, Key.Down, Key.Up, Key.Down,
		Key.Up, Key.Down, Key.PageUp, Key.PageDown, Key.Right, Key.Left, Key.One
	];

	static final MODS:Array<Int> = [
		Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl,
		Mod.None, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl | Mod.Shift,
		Mod.Ctrl, Mod.Ctrl,
		Mod.None, Mod.None, Mod.None, Mod.None, Mod.None,
		Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl,
		Mod.None,
		Mod.None, Mod.None, Mod.None, Mod.None, Mod.Ctrl, Mod.Ctrl, Mod.Shift, Mod.Shift,
		Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.Ctrl, Mod.None
	];

	/**
		What each action is called, in order.
	**/
	public static final NAMES:Array<Locale> = [
		Locale.BIND_UNDO, Locale.BIND_REDO, Locale.BIND_NEW, Locale.BIND_OPEN,
		Locale.BIND_SAVE, Locale.BIND_PREFERENCES, Locale.BIND_PLAY, Locale.BIND_STOP,
		Locale.BIND_LOOP, Locale.BIND_WRITE_VGM, Locale.BIND_WRITE_AUDIO,
		Locale.BIND_EARLIER, Locale.BIND_LATER,
		Locale.BIND_SELECT, Locale.BIND_DRAW, Locale.BIND_ERASE, Locale.BIND_SLICE,
		Locale.BIND_PAN,
		Locale.BIND_ALL, Locale.BIND_COPY, Locale.BIND_CUT, Locale.BIND_PASTE,
		Locale.BIND_DOUBLE, Locale.BIND_FOLLOW,
		Locale.BIND_NOTES_EARLIER, Locale.BIND_NOTES_LATER, Locale.BIND_TRANSPOSE_UP,
		Locale.BIND_TRANSPOSE_DOWN, Locale.BIND_OCTAVE_UP, Locale.BIND_OCTAVE_DOWN,
		Locale.BIND_LOUDER, Locale.BIND_QUIETER,
		Locale.BIND_TRACKER_LOUDER, Locale.BIND_TRACKER_QUIETER, Locale.BIND_TRACKER_OCTAVE_UP,
		Locale.BIND_TRACKER_OCTAVE_DOWN, Locale.BIND_TRACKER_FINER, Locale.BIND_TRACKER_COARSER,
		Locale.BIND_TRACKER_CUT
	];

	final keys:Array<Key> = [];
	final mods:Array<Int> = [];

	/**
		Builds the bindings at their defaults.
	**/
	public function new() {
		forget();
	}

	/**
		Puts every binding back to its default.
	**/
	public function forget():Void {
		keys.resize(0);
		mods.resize(0);

		for (index in 0...COUNT) {
			keys.push(KEYS[index]);
			mods.push(MODS[index]);
		}
	}

	/**
		@param action Which action, one of the constants above.
		@return Which key runs it.
	**/
	public inline function keyOf(action:Int):Key {
		return keys[action];
	}

	/**
		@param held The bindings, or null.
		@param action Which action, one of the constants above.
		@return The chord as text, or an empty string where there are no bindings.
	**/
	public static function of(held:Null<Bindings>, action:Int):String {
		return held == null ? "" : held.shortcut(action);
	}

	/**
		@param action Which action, one of the constants above.
		@return The chord as text, spelt the way a menu shows it.
	**/
	public function shortcut(action:Int):String {
		if (action < 0 || action >= COUNT) return "";
		return keys[action].shortcut(mods[action]);
	}

	/**
		Changes a binding, taking the chord off whatever else is heard in the same place. An action
		heard everywhere keeps a chord an editor's own action takes, because the editor asks
		first only while it has the keyboard.

		@param action Which action, one of the constants above.
		@param key The key.
		@param mod Which modifiers go with it.
	**/
	public function binds(action:Int, key:Key, mod:Int):Void {
		if (action < 0 || action >= COUNT) return;

		for (index in 0...COUNT) {
			if (index == action || !clashes(index, action)) continue;
			if (keys[index] != key || mods[index] != mod) continue;

			keys[index] = Key.Unknown;
			mods[index] = Mod.None;
		}

		keys[action] = key;
		mods[action] = mod;
	}

	/**
		Puts one binding back to its default.

		@param action Which action, one of the constants above.
	**/
	public function restores(action:Int):Void {
		if (action < 0 || action >= COUNT) return;
		binds(action, KEYS[action], MODS[action]);
	}

	/**
		@param action Which action, one of the constants above.
		@return Whether anything reaches it.
	**/
	public inline function bound(action:Int):Bool {
		return action >= 0 && action < COUNT && keys[action] != Key.Unknown;
	}

	/**
		@param key The key.
		@param mod Which modifiers were held.
		@return The action heard everywhere that the chord runs, or `NONE`.
	**/
	public inline function actionFor(key:Key, mod:Int):Int {
		return actionIn(GLOBAL, key, mod);
	}

	/**
		@param scope `GLOBAL` for the actions heard everywhere, or one of `ROLL`, `PLAYLIST` and
			`TRACKER` for that editor's own.
		@param key The key.
		@param mod Which modifiers were held. Anything but control, alt and shift is ignored.
		@return The action the chord runs there, or `NONE`.
	**/
	public function actionIn(scope:Int, key:Key, mod:Int):Int {
		final held = mod & (Mod.Ctrl | Mod.Alt | Mod.Shift);

		for (index in 0...COUNT) {
			if (keys[index] == Key.Unknown) continue;
			if (scope == GLOBAL ? SCOPES[index] != GLOBAL : (SCOPES[index] & scope) == 0) continue;
			if (keys[index] == key && mods[index] == held) return index;
		}

		return NONE;
	}

	/**
		@param one An action.
		@param two Another.
		@return Whether the two cannot share a chord: both are heard everywhere, or both are
			heard in one editor.
	**/
	static inline function clashes(one:Int, two:Int):Bool {
		final first = SCOPES[one];
		final second = SCOPES[two];

		return first == second || (first & second) != 0;
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
