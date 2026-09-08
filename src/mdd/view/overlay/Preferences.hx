package mdd.view.overlay;

import mdd.app.Associations;
import mdd.app.Languages;
import mdd.app.Locale;
import mdd.app.Session;
import mdd.Typeface;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
import mdd.ui.Flow;
import mdd.ui.Input;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Motion;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Preferences extends Widget {
	public static inline final THEME = 0;
	static inline final TYPEFACE = 1;
	static inline final MOTION = 2;
	public static inline final LANGUAGE = 3;
	public static inline final DENSITY = 4;
	public static inline final KEEPING = 5;
	public static inline final BACKUPS = 6;
	public static inline final BACKUP_AGE = 7;
	public static inline final UPDATES = 8;
	public static inline final PROJECTS = 9;
	public static inline final PRESETS = 10;
	public static inline final AUTOMATING = 11;
	public static inline final TAIL = 12;
	static inline final MIDI_DEVICE = 13;
	static inline final MIDI_CHANNEL = 14;
	static inline final MIDI_VELOCITY = 15;
	public static inline final CONSOLE = 16;
	public static inline final TEMPO = 17;
	public static inline final PRESENCE = 18;
	public static inline final ASSOCIATE = 19;
	public static inline final RENDERER = 20;
	public static inline final ROWS = 21;

	public static inline final LOOK = 0;
	static inline final EDITING = 1;
	public static inline final FILES = 2;
	static inline final CHECKING = 3;
	public static inline final MIDI = 4;
	public static inline final SOUND = 5;
	public static inline final KEYBOARD = 6;
	static inline final SHARING = 7;
	public static inline final GROUPS = 8;

	static final GROUP_NAMES:Array<Locale> = [Locale.GROUP_LOOK, Locale.GROUP_EDITING,
		Locale.GROUP_FILES, Locale.GROUP_UPDATES, Locale.GROUP_MIDI, Locale.GROUP_SOUND,
		Locale.GROUP_KEYBOARD, Locale.GROUP_SHARING];

	static final GROUPED:Array<Array<Int>> = [
		#if windows
		[THEME, TYPEFACE, MOTION, DENSITY, LANGUAGE],
		#else
		[THEME, TYPEFACE, MOTION, DENSITY, LANGUAGE, RENDERER],
		#end
		[AUTOMATING, TAIL, TEMPO],
		#if mac
		[KEEPING, BACKUPS, BACKUP_AGE, PROJECTS, PRESETS],
		#else
		[KEEPING, BACKUPS, BACKUP_AGE, PROJECTS, PRESETS, ASSOCIATE],
		#end
		[UPDATES],
		[MIDI_DEVICE, MIDI_CHANNEL, MIDI_VELOCITY],
		[CONSOLE],
		[],
		[PRESENCE]
	];

	public var group(default, null):Int = LOOK;

	public var onShut:Null<Void -> Void> = null;

	final was:Array<Int> = [];

	var associated:Bool = false;
	var wasProjects:String = "";
	var wasPresets:String = "";
	var offsetY:Float = 0;

	static final NAMES:Array<Locale> = [Locale.PREFERENCE_THEME, Locale.PREFERENCE_TYPEFACE,
		Locale.PREFERENCE_MOTION, Locale.PREFERENCE_LANGUAGE, Locale.PREFERENCE_DENSITY,
		Locale.PREFERENCE_KEEPING, Locale.PREFERENCE_BACKUPS, Locale.PREFERENCE_BACKUP_AGE,
		Locale.PREFERENCE_UPDATES, Locale.PREFERENCE_PROJECTS, Locale.PREFERENCE_PRESETS,
		Locale.PREFERENCE_AUTOMATING, Locale.PREFERENCE_TAIL, Locale.PREFERENCE_MIDI_DEVICE,
		Locale.PREFERENCE_MIDI_CHANNEL, Locale.PREFERENCE_MIDI_VELOCITY, Locale.PREFERENCE_CONSOLE,
		Locale.PREFERENCE_TEMPO, Locale.PREFERENCE_PRESENCE, Locale.PREFERENCE_ASSOCIATE,
		Locale.PREFERENCE_RENDERER];

	static final PRESENCES:Array<Locale> = [Locale.PRESENCE_OFF, Locale.PRESENCE_PLAIN,
		Locale.PRESENCE_FULL];

	static final ASSOCIATES:Array<Locale> = [Locale.ASSOCIATE_NO, Locale.ASSOCIATE_YES];

	static final TEMPOS:Array<Locale> = [Locale.TEMPO_SPEED, Locale.TEMPO_GRID];

	static final CONSOLES:Array<Locale> = [Locale.CONSOLE_CHIP, Locale.CONSOLE_ONE,
		Locale.CONSOLE_TWO];

	static final VELOCITIES:Array<Locale> = [Locale.MIDI_TAKEN, Locale.MIDI_FORCED];

	static final AUTOMATINGS:Array<Locale> = [Locale.AUTOMATING_LANES,
		Locale.AUTOMATING_CLIPS];

	static final TAILS:Array<Locale> = [Locale.TAIL_NONE, Locale.TAIL_BEAT, Locale.TAIL_TWO,
		Locale.TAIL_BAR, Locale.TAIL_TWO_BARS];

	static final BEATS:Array<Int> = [0, 1, 2, 4, 8];

	static final KEEPINGS:Array<Locale> = [Locale.KEEPING_NEVER, Locale.KEEPING_ONE,
		Locale.KEEPING_FIVE, Locale.KEEPING_TEN];

	static final MINUTES:Array<Float> = [0, 60, 300, 600];

	static final BACKUP_ROOMS:Array<String> = ["", "50 MB", "100 MB", "250 MB", "500 MB",
		"1 GB", ""];

	static final NOTHING:Array<String> = [];
	static final NO_KEYS:Array<Locale> = [];

	public static final ROOMS:Array<Float> = [0, 50, 100, 250, 500, 1024, 1024 * 64];

	static final BACKUP_AGES:Array<Locale> = [Locale.BACKUP_AGE_ANY, Locale.BACKUP_AGE_WEEK,
		Locale.BACKUP_AGE_MONTH, Locale.BACKUP_AGE_QUARTER];

	public static final DAYS:Array<Int> = [0, 7, 30, 90];

	static final UPDATING:Array<Locale> = [Locale.UPDATES_NEVER, Locale.UPDATES_LAUNCH];

	static final THEMES:Array<Locale> = [Locale.THEME_MIDNIGHT, Locale.THEME_RACK,
		Locale.THEME_SLATE];
	static final MOTIONS:Array<Locale> = [Locale.MOTION_FULL, Locale.MOTION_REDUCED,
		Locale.MOTION_NONE];
	static final DENSITIES:Array<Locale> = [Locale.DENSITY_CLOSE, Locale.DENSITY_USUAL,
		Locale.DENSITY_ROOMY];

	public var session:Session;
	public final languages:Array<String> = [];
	public final renderers:Array<String> = [];
	public final spoken:Array<String> = [];

	public var chosen(default, null):Int = 0;
	public var density(default, null):Int = 1;
	public var language(default, null):Int = 0;
	public var renderer:Int = 0;
	public var onRenderer:Null<String -> Void> = null;
	public var keeping(default, null):Int = 2;
	public var backups(default, null):Int = 3;
	public var backupAge(default, null):Int = 2;
	public var updates(default, null):Int = 1;
	public var tail(default, null):Int = 1;

	public var projectsAt:String = "";
	public var presetsAt:String = "";

	public final keyboards:Array<String> = [];

	var keyboardAt(default, null):Int = 0;
	public var keyboardChannel(default, null):Int = 0;
	public var keyboardVelocity(default, null):Int = 0;
	public var console(default, null):Int = mdd.play.Render.MODEL_ONE;
	public var tempo(default, null):Int = 0;
	public var presence(default, null):Int = mdd.app.Presence.FULL;

	public var presenceSaid:String = "";

	public final rise:Motion;
	public final fade:Motion;

	public var onScale:Null<Float -> Void> = null;
	public var onTypeface:Null<Int -> Void> = null;
	public var onKeep:Null<Void -> Void> = null;
	public var onKeeping:Null<Float -> Void> = null;
	public var onBackups:Null<Void -> Void> = null;
	public var onUpdates:Null<Bool -> Void> = null;
	public var onAutomating:Null<Int -> Void> = null;
	public var onFolder:Null<Int -> Void> = null;
	public var onKeyboard:Null<Int -> Void> = null;
	public var onKeyboardChannel:Null<Int -> Void> = null;
	public var onKeyboardVelocity:Null<Int -> Void> = null;
	public var onConsole:Null<Int -> Void> = null;
	public var onTempo:Null<Int -> Void> = null;
	public var onPresence:Null<Int -> Void> = null;
	public var onRebind:Null<Void -> Void> = null;

	public var bindings:Null<mdd.app.Bindings> = null;
	public var catching(default, null):Int = -1;

	public var mapping:Null<mdd.app.Mapping> = null;
	public var learning(default, null):Int = -1;

	public var onRemap:Null<Void -> Void> = null;

	var wasKeys:String = "";
	var wasControls:String = "";

	var hoverAt:Int = -1;
	var hoverButton:Int = -1;
	var hoverGroup:Int = -1;
	var menu:Null<Menu> = null;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;

		rise = new Motion(this, 0, true);
		fade = new Motion(this, 0, false);
	}

	public var onSpeak:Null<String -> Void> = null;

	public function draws(names:Array<String>, held:String):Void {
		renderers.resize(0);
		renderers.push(translate(Locale.RENDERER_AUTO));

		for (name in names) renderers.push(name);

		final at = renderers.indexOf(held);
		renderer = held == "" || at < 0 ? 0 : at;

		invalidate();
	}

	public function speaks(codes:Array<String>, code:String):Void {
		languages.resize(0);
		spoken.resize(0);

		for (held in codes) {
			languages.push(Languages.named(held));
			spoken.push(held);
		}

		final at = spoken.indexOf(code);
		language = at < 0 ? 0 : at;

		invalidate();
	}

	public function arrive():Void {
		final root = root();

		associated = Associations.holds();

		was.resize(0);
		for (row in 0...ROWS) was.push(holding(row));

		wasProjects = projectsAt;
		wasPresets = presetsAt;
		wasKeys = bindings == null ? "" : bindings.said();
		wasControls = mapping == null ? "" : mapping.said();

		catching = -1;
		learning = -1;

		offsetY = 0;
		if (root == null) return;

		rise.hold(0);
		fade.hold(0);

		root.start(rise, 1, Motion.ENTER);
		root.start(fade, 1, Motion.ENTER);
	}

	public function saves():Void {
		catching = -1;
		learning = -1;

		if (onKeep != null) onKeep();
		if (onShut != null) onShut();
	}

	public function cancels():Void {
		for (row in 0...ROWS) {
			if (row >= was.length || folded(row)) continue;
			if (holding(row) == was[row]) continue;

			chose(row, was[row]);
		}

		projectsAt = wasProjects;
		presetsAt = wasPresets;
		catching = -1;
		learning = -1;

		if (bindings != null && bindings.said() != wasKeys) {
			bindings.reads(wasKeys);
			if (onRebind != null) onRebind();
		}

		if (mapping != null && mapping.said() != wasControls) {
			mapping.reads(wasControls);
			if (onRemap != null) onRemap();
		}

		if (onShut != null) onShut();
	}

	public function shows(which:Int):Void {
		if (which < 0 || which >= GROUPS || which == group) return;

		group = which;
		offsetY = 0;
		catching = -1;
		learning = -1;

		invalidate();
	}

	public inline function mapped():Bool {
		return group == MIDI && mapping != null;
	}

	public function slotAt(py:Float):Int {
		if (!mapped()) return -1;
		if (py < y + head() || py >= y + head() + room()) return -1;

		final at = Std.int((py - y - head() + offsetY) / rowTall()) - rowsIn().length;
		return at < 0 || at >= mdd.app.Mapping.SLOTS ? -1 : at;
	}

	public function listens(slot:Int):Void {
		learning = learning == slot ? -1 : slot;
		invalidate();
	}

	public function hears(control:Int):Bool {
		final held = mapping;

		if (held == null || learning < 0) return false;

		held.hears(learning, control);
		learning = -1;

		if (onRemap != null) onRemap();
		invalidate();

		return true;
	}

	public function forgets(slot:Int):Void {
		final held = mapping;
		if (held == null || slot < 0) return;

		held.clears(slot);
		learning = -1;

		if (onRemap != null) onRemap();
		invalidate();
	}

	function aims(slot:Int, kind:Int, op:Int, row:Int):Void {
		final held = mapping;
		if (held == null || slot < 0) return;

		held.drives(slot, kind, op, row);
		if (onRemap != null) onRemap();

		invalidate();
	}

	inline function binding():Bool {
		return group == KEYBOARD && bindings != null;
	}

	public function bindAt(py:Float):Int {
		if (!binding()) return -1;
		if (py < y + head() || py >= y + head() + room()) return -1;

		final at = Std.int((py - y - head() + offsetY) / rowTall());
		return at < 0 || at >= mdd.app.Bindings.COUNT ? -1 : at;
	}

	public function catches(action:Int):Void {
		catching = catching == action ? -1 : action;
		invalidate();
	}

	public function binds(code:mdd.ui.Key, mods:Int):Bool {
		if (bindings == null || catching < 0) return false;

		if (code.name() == "") return true;

		bindings.binds(catching, code, mods & (mdd.ui.Mod.Ctrl | mdd.ui.Mod.Alt
			| mdd.ui.Mod.Shift));

		catching = -1;

		if (onRebind != null) onRebind();
		invalidate();

		return true;
	}

	public function restores(action:Int):Void {
		if (bindings == null || action < 0) return;

		bindings.restores(action);
		catching = -1;

		if (onRebind != null) onRebind();
		invalidate();
	}

	public inline function rowsIn():Array<Int> {
		return GROUPED[group];
	}

	function sidebar():Float {
		final root = root();
		return root == null ? 150 : root.metrics.whole(150);
	}

	public function foot():Float {
		final root = root();
		return root == null ? 56 : root.metrics.whole(56);
	}

	public function room():Float {
		return height - head() - foot();
	}

	public function content():Float {
		if (binding()) return mdd.app.Bindings.COUNT * rowTall();

		final rows = rowsIn().length + (mapped() ? mdd.app.Mapping.SLOTS : 0);
		return rows * rowTall();
	}

	public function scrollTo(py:Float):Void {
		final most = content() - room();

		offsetY = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		invalidate();
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		final root = root();
		final metrics = root == null ? null : root.metrics;

		wantWidth = metrics == null ? 640 : metrics.whole(640);

		var most = 0;
		for (held in GROUPED) if (held.length > most) most = held.length;
		if (GROUPS > most) most = GROUPS;

		wantHeight = metrics == null ? 300 : head() + most * rowTall() + foot();
	}

	public function rowTall():Float {
		final root = root();
		return root == null ? 44 : root.metrics.whole(44);
	}

	public function head():Float {
		final root = root();
		return root == null ? 46 : root.metrics.whole(46);
	}

	public function showing(row:Int):Int {
		return holding(row);
	}

	public function rowAt(py:Float):Int {
		if (py < y + head() || py >= y + head() + room()) return -1;

		final held = rowsIn();
		final at = Std.int((py - y - head() + offsetY) / rowTall());

		return at < 0 || at >= held.length ? -1 : held[at];
	}

	function groupAt(py:Float):Int {
		if (py < y + head() || py >= y + head() + room()) return -1;

		final at = Std.int((py - y - head()) / rowTall());
		return at < 0 || at >= GROUPS ? -1 : at;
	}

	public function buttonWide():Float {
		final root = root();
		return root == null ? 110 : root.metrics.whole(110);
	}

	public function buttonTall():Float {
		final root = root();
		return root == null ? 32 : root.metrics.control;
	}

	function buttonTop():Float {
		return y + height - foot() + (foot() - buttonTall()) * 0.5;
	}

	public function buttonAt(px:Float, py:Float):Int {
		final root = root();
		if (root == null) return -1;

		final top = buttonTop();
		if (py < top || py >= top + buttonTall()) return -1;

		final inset = root.metrics.inset;
		final wide = buttonWide();
		final right = x + width - inset;

		if (px >= right - wide && px < right) return 1;
		if (px >= right - wide * 2 - root.metrics.gap && px < right - wide - root.metrics.gap) {
			return 0;
		}

		return -1;
	}

	public function keyed(at:Int, channel:Int, velocity:Int):Void {
		keyboardAt = at < 0 ? 0 : at;
		keyboardChannel = channel < 0 ? 0 : channel;
		keyboardVelocity = velocity < 0 ? 0 : velocity;
	}

	function channels():Array<String> {
		final out = [translate(Locale.MIDI_ANY)];
		for (index in 1...17) out.push(Std.string(index));

		return out;
	}

	public function labels(row:Int):Array<Locale> {
		return switch (row) {
			case THEME: THEMES;
			case MOTION: MOTIONS;
			case DENSITY: DENSITIES;
			case KEEPING: KEEPINGS;
			case BACKUP_AGE: BACKUP_AGES;
			case UPDATES: UPDATING;
			case AUTOMATING: AUTOMATINGS;
			case TAIL: TAILS;
			case MIDI_VELOCITY: VELOCITIES;
			case CONSOLE: CONSOLES;
			case TEMPO: TEMPOS;
			case PRESENCE: PRESENCES;
			case ASSOCIATE: ASSOCIATES;
			case _: NO_KEYS;
		}
	}

	public function choices(row:Int):Array<String> {
		return switch (row) {
			case TYPEFACE: Typeface.NAMES;
			case RENDERER: renderers;
			case BACKUPS: BACKUP_ROOMS;
			case PROJECTS, PRESETS: NOTHING;
			case MIDI_DEVICE: keyboards;
			case MIDI_CHANNEL: channels();
			case THEME, MOTION, DENSITY, KEEPING, BACKUP_AGE, UPDATES, AUTOMATING, TAIL,
				MIDI_VELOCITY, CONSOLE, TEMPO, PRESENCE, ASSOCIATE: NOTHING;
			case _: languages;
		}
	}

	public function counted(row:Int):Int {
		final keys = labels(row);
		return keys.length > 0 ? keys.length : choices(row).length;
	}

	public inline function folded(row:Int):Bool {
		return row == PROJECTS || row == PRESETS;
	}

	public function said(row:Int, which:Int):String {
		if (folded(row)) {
			final held = row == PROJECTS ? projectsAt : presetsAt;
			return held == "" ? translate(Locale.FOLDER_DEFAULT) : held;
		}

		if (row == BACKUPS) {
			if (which == 0) return translate(Locale.BACKUPS_OFF);
			if (which == BACKUP_ROOMS.length - 1) return translate(Locale.BACKUPS_ANY);

			return which > 0 && which < BACKUP_ROOMS.length ? BACKUP_ROOMS[which] : "";
		}

		final keys = labels(row);

		if (keys.length > 0) {
			return which < 0 || which >= keys.length ? "" : translate(keys[which]);
		}

		final held = choices(row);
		return which < 0 || which >= held.length ? "" : held[which];
	}

	public function fieldLeft():Float {
		final root = root();
		final metrics = root == null ? null : root.metrics;
		final inset = metrics == null ? 12 : metrics.inset;

		return x + sidebar() + (width - sidebar()) * 0.42 + inset;
	}

	public function fieldWide():Float {
		final root = root();
		final metrics = root == null ? null : root.metrics;
		final inset = metrics == null ? 12 : metrics.inset;

		return x + width - inset - fieldLeft();
	}

	public function fieldTall():Float {
		final root = root();
		return root == null ? 28 : root.metrics.whole(28);
	}

	public function holding(row:Int):Int {
		return switch (row) {
			case THEME: session.theme;
			case TYPEFACE: session.typeface;
			case MOTION: session.motion;
			case DENSITY: density;
			case KEEPING: keeping;
			case BACKUPS: backups;
			case BACKUP_AGE: backupAge;
			case UPDATES: updates;
			case AUTOMATING: session.automating;
			case TAIL: tail;
			case PROJECTS, PRESETS: 0;
			case MIDI_DEVICE: keyboardAt;
			case MIDI_CHANNEL: keyboardChannel;
			case MIDI_VELOCITY: keyboardVelocity;
			case CONSOLE: console;
			case TEMPO: tempo;
			case PRESENCE: presence;
			case ASSOCIATE: associated ? 1 : 0;
			case RENDERER: renderer;
			case _: language;
		}
	}

	public function chose(row:Int, which:Int):Void {
		final root = root();

		switch (row) {
			case THEME:
				session.theme = which;
				if (root != null) root.theme.wear(which);
				session.say("theme " + which);

			case TYPEFACE:
				session.typeface = which;
				if (onTypeface != null) onTypeface(which);

			case MOTION:
				session.motion = which;
				if (root != null) root.flow = which;
				session.say("motion " + which);

			case DENSITY:
				density = which;
				if (onScale != null) onScale(1.0 + which * 0.15);

			case KEEPING:
				keeping = which;
				if (onKeeping != null) onKeeping(MINUTES[which]);
				session.say(which == 0 ? "no saving on its own"
					: "saving on its own every " + Std.int(MINUTES[which] / 60) + " minutes");

			case BACKUPS:
				backups = which;
				if (onBackups != null) onBackups();

			case BACKUP_AGE:
				backupAge = which;
				if (onBackups != null) onBackups();

			case UPDATES:
				updates = which;
				if (onUpdates != null) onUpdates(which != 0);

			case AUTOMATING:
				session.automating = which;
				if (onAutomating != null) onAutomating(which);

			case TAIL:
				tail = which;
				session.transport.tail = BEATS[which];

				session.say(which == 0 ? translate(Locale.TAIL_NONE)
					: translate(Locale.PREFERENCE_TAIL) + "  " + translate(TAILS[which]));

			case MIDI_DEVICE:
				keyboardAt = which;
				if (onKeyboard != null) onKeyboard(which);

			case MIDI_CHANNEL:
				keyboardChannel = which;
				if (onKeyboardChannel != null) onKeyboardChannel(which);

			case MIDI_VELOCITY:
				keyboardVelocity = which;
				if (onKeyboardVelocity != null) onKeyboardVelocity(which);

			case CONSOLE:
				console = which;
				if (onConsole != null) onConsole(which);

			case TEMPO:
				tempo = which;
				if (onTempo != null) onTempo(which);

			case PRESENCE:
				presence = which;
				if (onPresence != null) onPresence(which);

			case ASSOCIATE:
				if (which > 0) Associations.takes();
				else Associations.drops();

				associated = Associations.holds();
				session.say(translate(ASSOCIATES[associated ? 1 : 0]));

			case RENDERER:
				renderer = which < 0 || which >= renderers.length ? 0 : which;

				final name = renderer == 0 ? "" : renderers[renderer];
				if (onRenderer != null) onRenderer(name);

			case _:
				language = which;

				if (which < spoken.length && onSpeak != null) onSpeak(spoken[which]);
				session.say(which < languages.length ? languages[which] : "");
		}

		if (root != null) root.reshape();

		session.changed();
		invalidate();

		if (onKeep != null) onKeep();
	}

	public function opens(row:Int):Void {
		final root = root();
		if (root == null || row < 0 || row >= ROWS) return;

		if (folded(row)) {
			if (onFolder != null) onFolder(row);
			return;
		}

		final many = counted(row);
		if (many == 0) return;

		final on = holding(row);
		menu = new Menu();

		for (index in 0...many) {
			final which = index;
			final choice = menu.offer(new Choice(said(row, which)));

			choice.onFire = function(from:Choice):Void chose(row, which);
			if (which == on) choice.shortcut = "•";
		}

		root.pop(menu, fieldLeft(), rowTop(row) + fieldTall(), this);
	}

	function aimed(slot:Int):Void {
		final root = root();
		final held = mapping;

		if (root == null || held == null) return;

		menu = new Menu();

		final listen = menu.offer(new Choice(translate(Locale.MAP_LISTEN)));
		listen.onFire = function(from:Choice):Void listens(slot);

		final drop = menu.offer(new Choice(translate(Locale.MAP_CLEAR)));

		drop.enabled = held.bound(slot);
		drop.onFire = function(from:Choice):Void forgets(slot);

		menu.divide();

		for (which in 0...mdd.song.Patch.DIALS) {
			final dial = which;
			final choice = menu.offer(new Choice(mdd.song.Patch.DIAL_SPELT[dial]));

			if (held.kindOf(slot) == mdd.app.Mapping.DIAL && held.rowOf(slot) == dial) {
				choice.shortcut = "•";
			}

			choice.onFire = function(from:Choice):Void
				aims(slot, mdd.app.Mapping.DIAL, 0, dial);
		}

		menu.divide();

		for (index in 0...mdd.song.Patch.SLOTS) {
			final which = index;
			final rows = new Menu();

			for (step in 0...mdd.song.Patch.ROWS) {
				final row = step;
				final choice = rows.offer(new Choice(mdd.song.Patch.SPELT[row]));

				if (held.kindOf(slot) == mdd.app.Mapping.OPERATOR
					&& held.operatorOf(slot) == which && held.rowOf(slot) == row) {
					choice.shortcut = "•";
				}

				choice.onFire = function(from:Choice):Void
					aims(slot, mdd.app.Mapping.OPERATOR, which, row);
			}

			menu.offer(new Choice("OP" + (which + 1))).submenu = rows;
		}

		root.pop(menu, fieldLeft(), y + head() + (rowsIn().length + slot + 1) * rowTall()
			- offsetY, this);
	}

	public function rowTop(row:Int):Float {
		final at = rowsIn().indexOf(row);
		final which = at < 0 ? 0 : at;

		return y + head() - offsetY + which * rowTall() + (rowTall() - fieldTall()) * 0.5;
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				if (event.x >= x + sidebar()) scrollTo(offsetY - event.dy * rowTall());
				return true;

			case Kind.KeyDown:
				if (catching < 0) return true;
				return binds(event.code, event.mods);

			case Kind.PointerDown:
				final button = buttonAt(event.x, event.y);

				if (button == 0) {
					cancels();
					return true;
				}

				if (button == 1) {
					saves();
					return true;
				}

				if (event.x < x + sidebar()) {
					final which = groupAt(event.y);
					if (which >= 0) shows(which);

					return true;
				}

				if (binding()) {
					final action = bindAt(event.y);
					if (action < 0) return true;

					if (event.button == Pointer.Right) restores(action);
					else catches(action);

					return true;
				}

				if (mapped()) {
					final slot = slotAt(event.y);

					if (slot >= 0) {
						if (event.button == Pointer.Right) forgets(slot);
						else aimed(slot);

						return true;
					}
				}

				final row = rowAt(event.y);
				if (row < 0) return true;

				opens(row);
				return true;

			case Kind.PointerMove:
				final row = event.x < x + sidebar() ? -1
					: (binding() ? bindAt(event.y) : rowAt(event.y));
				final button = buttonAt(event.x, event.y);
				final which = event.x < x + sidebar() ? groupAt(event.y) : -1;

				if (row == hoverAt && button == hoverButton && which == hoverGroup) return true;

				hoverAt = row;
				hoverButton = button;
				hoverGroup = which;

				invalidate();
				return true;

			case _:
		}

		return true;
	}

	override function hovered(on:Bool):Void {
		if (!on) {
			hoverAt = -1;
			hoverButton = -1;
			hoverGroup = -1;
		}

		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final alpha = fade.value;

		if (alpha <= 0.004) return;

		final lift = (1 - rise.value) * metrics.sizeOf(8);
		paint.pushTransform(0, lift);

		paint.roundedRect(x, y, width, height, metrics.radiusPanel, theme.raise1, alpha);
		paint.outline(x, y, width, height, theme.frame, metrics.whole(1), alpha,
			metrics.radiusPanel);

		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;

		paint.reface(font);
		paint.text(translate(Locale.PREFERENCES), x + metrics.inset,
			y + metrics.inset + font.ascent, theme.ink, alpha);

		paint.reface(small);
		paint.textRight(translate(Locale.PREFERENCES_CLOSE), x + width - metrics.inset,
			y + metrics.inset + small.ascent, theme.dim, alpha * 0.8);

		final tall = rowTall();

		sided(paint, theme, metrics, small, alpha);
		footed(paint, theme, metrics, small, alpha);

		paint.pushClip(x + sidebar(), y + head(), width - sidebar(), room());

		if (binding()) {
			bound(paint, theme, metrics, small, alpha);
			paint.popClip();

			reined(paint, theme, metrics, alpha);
			paint.popTransform();

			return;
		}

		if (mapped()) controlled(paint, theme, metrics, small, alpha);
		if (group == SHARING) shared(paint, theme, metrics, small, alpha);

		for (which in 0...rowsIn().length) {
			final row = rowsIn()[which];
			final top = y + head() - offsetY + which * tall;

			paint.reface(small);
			paint.text(translate(NAMES[row]), x + sidebar() + metrics.inset,
				top + (tall - small.height) * 0.5 + small.ascent, theme.dim, alpha * 0.9);

			final left = fieldLeft();
			final wide = fieldWide();
			final deep = fieldTall();
			final at = top + (tall - deep) * 0.5;

			paint.roundedRect(left, at, wide, deep, metrics.radiusSmall, theme.raise2, alpha);

			if (row == hoverAt) {
				paint.roundedRect(left, at, wide, deep, metrics.radiusSmall, theme.accent,
					alpha * Theme.HOVER);
			}

			paint.outline(left, at, wide, deep, theme.frame, metrics.whole(1), alpha * 0.8,
				metrics.radiusSmall);

			final arrow = metrics.whole(16);

			paint.pushClip(left + metrics.gap, at, wide - arrow - metrics.gap, deep);
			paint.text(said(row, holding(row)), left + metrics.gap,
				at + (deep - small.height) * 0.5 + small.ascent, theme.ink, alpha);
			paint.popClip();

			if (folded(row)) {
				paint.textRight("...", left + wide - metrics.gap,
					at + (deep - small.height) * 0.5 + small.ascent, theme.dim, alpha * 0.9);
			} else {
				chevron(paint, theme, metrics, left + wide - arrow, at + deep * 0.5, alpha);
			}
		}

		paint.popClip();

		reined(paint, theme, metrics, alpha);
		paint.popTransform();
	}

	function shared(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			alpha:Float):Void {
		if (presenceSaid == "") return;

		final top = y + head() - offsetY + rowsIn().length * rowTall() + metrics.gap;

		paint.reface(font);
		paint.text(presenceSaid, x + sidebar() + metrics.inset, top + font.ascent, theme.dim,
			alpha * 0.8);
	}

	function controlled(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			alpha:Float):Void {
		final held = mapping;
		if (held == null) return;

		final tall = rowTall();
		final deep = fieldTall();
		final left = fieldLeft();
		final wide = fieldWide();
		final from = rowsIn().length;

		for (slot in 0...mdd.app.Mapping.SLOTS) {
			final top = y + head() - offsetY + (from + slot) * tall;
			if (top + tall < y + head() || top > y + head() + room()) continue;

			final at = top + (tall - deep) * 0.5;
			final on = slot == learning;

			paint.reface(font);
			paint.text(translate(Locale.MAP_CONTROL) + " " + (slot + 1),
				x + sidebar() + metrics.inset,
				top + (tall - font.height) * 0.5 + font.ascent, theme.dim, alpha * 0.9);

			paint.roundedRect(left, at, wide, deep, metrics.radiusSmall,
				on ? theme.accent : theme.raise2, on ? alpha * 0.35 : alpha);

			paint.outline(left, at, wide, deep, on ? theme.accent : theme.frame,
				metrics.whole(1), alpha * (on ? 1 : 0.8), metrics.radiusSmall);

			final said = on ? translate(Locale.MAP_WAITING)
				: (held.bound(slot) ? "CC " + held.controlOf(slot) + "   " + held.named(slot)
				: translate(Locale.MAP_EMPTY));

			paint.pushClip(left + metrics.gap, at, wide - metrics.gap * 2, deep);
			paint.text(said, left + metrics.gap,
				at + (deep - font.height) * 0.5 + font.ascent,
				held.bound(slot) || on ? theme.ink : theme.dim, alpha);
			paint.popClip();
		}
	}

	function reined(paint:Paint, theme:Theme, metrics:Metrics, alpha:Float):Void {
		final tall = room();
		final reach = content();

		if (reach <= tall + 0.5) return;

		final thick = metrics.whole(4);
		final held = tall * tall / reach;
		final least = metrics.whole(24);
		final span = held < least ? least : held;
		final at = offsetY / (reach - tall) * (tall - span);

		paint.roundedRect(x + width - metrics.gap - thick, y + head() + at, thick, span,
			thick * 0.5, theme.frame, alpha * 0.9);
	}

	function bound(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			alpha:Float):Void {
		final held = bindings;
		if (held == null) return;

		final tall = rowTall();
		final deep = fieldTall();
		final left = fieldLeft();
		final wide = fieldWide();

		for (action in 0...mdd.app.Bindings.COUNT) {
			final top = y + head() - offsetY + action * tall;
			if (top + tall < y + head() || top > y + head() + room()) continue;

			final at = top + (tall - deep) * 0.5;
			final on = action == catching;

			paint.reface(font);
			paint.text(translate(mdd.app.Bindings.NAMES[action]), x + sidebar() + metrics.inset,
				top + (tall - font.height) * 0.5 + font.ascent, theme.dim, alpha * 0.9);

			paint.roundedRect(left, at, wide, deep, metrics.radiusSmall,
				on ? theme.accent : theme.raise2, on ? alpha * 0.35 : alpha);

			if (action == hoverAt && !on) {
				paint.roundedRect(left, at, wide, deep, metrics.radiusSmall, theme.accent,
					alpha * Theme.HOVER);
			}

			paint.outline(left, at, wide, deep, on ? theme.accent : theme.frame,
				metrics.whole(1), alpha * (on ? 1 : 0.8), metrics.radiusSmall);

			final said = on ? translate(Locale.BIND_CATCH)
				: (held.bound(action) ? held.shortcut(action) : translate(Locale.BIND_NONE));

			paint.pushClip(left + metrics.gap, at, wide - metrics.gap * 2, deep);
			paint.text(said, left + metrics.gap,
				at + (deep - font.height) * 0.5 + font.ascent,
				held.bound(action) || on ? theme.ink : theme.dim, alpha);
			paint.popClip();
		}
	}

	function sided(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			alpha:Float):Void {
		final wide = sidebar();
		final tall = rowTall();
		final hair = metrics.whole(1);

		paint.rect(x, y + head(), wide, room(), theme.panel, alpha);
		paint.rect(x + wide - hair, y + head(), hair, room(), theme.frame, alpha * 0.7);

		paint.reface(font);

		for (which in 0...GROUPS) {
			final top = y + head() + which * tall;
			final on = which == group;

			if (on) {
				paint.roundedRect(x + metrics.unit, top + metrics.unit,
					wide - metrics.unit * 2 - hair, tall - metrics.unit * 2,
					metrics.radiusSmall, theme.accent, alpha * Theme.SELECT);
			} else if (which == hoverGroup) {
				paint.roundedRect(x + metrics.unit, top + metrics.unit,
					wide - metrics.unit * 2 - hair, tall - metrics.unit * 2,
					metrics.radiusSmall, theme.accent, alpha * Theme.HOVER);
			}

			paint.text(translate(GROUP_NAMES[which]), x + metrics.inset,
				top + (tall - font.height) * 0.5 + font.ascent,
				on ? theme.ink : theme.dim, alpha * (on ? 1 : 0.85));
		}
	}

	function footed(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font,
			alpha:Float):Void {
		final top = y + height - foot();
		final hair = metrics.whole(1);

		paint.rect(x, top, width, hair, theme.frame, alpha * 0.7);

		if (binding()) {
			paint.reface(font);
			paint.text(translate(Locale.BIND_HINT), x + metrics.inset,
				top + (foot() - font.height) * 0.5 + font.ascent, theme.dim, alpha * 0.75);
		}

		final wide = buttonWide();
		final deep = buttonTall();
		final at = buttonTop();
		final right = x + width - metrics.inset;

		button(paint, theme, metrics, font, right - wide * 2 - metrics.gap, at, wide, deep,
			translate(Locale.EXPORT_CANCEL), false, hoverButton == 0, alpha);

		button(paint, theme, metrics, font, right - wide, at, wide, deep,
			translate(Locale.FILE_SAVE), true, hoverButton == 1, alpha);
	}

	function button(paint:Paint, theme:Theme, metrics:Metrics, font:mdd.ui.Font, at:Float,
			top:Float, wide:Float, deep:Float, said:String, lit:Bool, over:Bool,
			alpha:Float):Void {
		if (lit) {
			paint.roundedGradient(at, top, wide, deep, metrics.radiusRow,
				theme.accent.lift(0.20), theme.accent.sink(0.16), alpha * 0.95);
		} else {
			paint.roundedRect(at, top, wide, deep, metrics.radiusRow, theme.raise2, alpha);
		}

		if (over) {
			paint.roundedRect(at, top, wide, deep, metrics.radiusRow, theme.accent,
				alpha * Theme.HOVER);
		}

		paint.outline(at, top, wide, deep, theme.frame, metrics.whole(1), alpha * 0.8,
			metrics.radiusRow);

		paint.reface(font);
		paint.textCentred(said, at + wide * 0.5, top + (deep - font.height) * 0.5 + font.ascent,
			theme.ink, alpha);
	}

	function chevron(paint:Paint, theme:Theme, metrics:Metrics, cx:Float, cy:Float,
			alpha:Float):Void {
		final size = metrics.whole(4);

		arrow[0] = cx - size;
		arrow[1] = cy - size * 0.5;
		arrow[2] = cx + size;
		arrow[3] = cy - size * 0.5;
		arrow[4] = cx;
		arrow[5] = cy + size * 0.6;

		paint.polygon(arrow, 3, theme.dim, alpha * 0.9);
	}

	final arrow:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(6);
}
