package mdd.app;

import mdd.check.Diagnostic;
import mdd.play.Polyphony;
import mdd.play.Transport;
import mdd.song.edit.Command;
import mdd.song.edit.History;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;

@:unreflective

/**
	Everything about the piece being worked on that is not the piece itself: what is
	chosen, which tool is in hand, what has been copied, and the undo stack.

	Every edit goes through `does`, which is what makes undo cover everything rather
	than the parts somebody remembered.
**/
final class Session {
	/**
		The piece.
	**/
	public final song:Song;

	/**
		The undo stack.
	**/
	public final history:History = new History();

	/**
		What plays it.
	**/
	public final transport:Transport;

	/**
		Which part is chosen.
	**/
	public var part:Part = Part.Fm1;

	/**
		Every preset installed, which the browser offers beside the piece's own and a channel's
		origin is looked up in first. Null where nothing installed is being offered, as in a check
		that builds a session over a piece alone.
	**/
	public var library:Null<mdd.song.Library> = null;

	/**
		The presets the piece held when this session began: what its file carried, or what a new
		piece starts with.
	**/
	final carried:Array<mdd.song.Instrument> = [];

	/**
		The presets a save by hand has left out of the file because nothing played them. They are
		still offered as the piece's own, and a save on its own does not write them back.
	**/
	final shed:Array<mdd.song.Instrument> = [];

	/**
		@param held A preset the piece carries, usually a channel's.
		@return The preset it was loaded from, found by identity among the installed presets first
			and then among the piece's others, or null where it came from none or neither holds it.
	**/
	public function loadedFrom(held:mdd.song.Instrument):Null<mdd.song.Instrument> {
		if (held.from == "") return null;

		final known = library;

		if (known != null) {
			for (bank in known.instruments) for (one in bank) if (one.id == held.from) return one;
		}

		for (one in song.instruments) if (one != held && one.id == held.from) return one;

		return null;
	}

	/**
		Tool: choose and move.
	**/
	public static inline final SELECT = 0;

	/**
		Tool: write notes.
	**/
	public static inline final DRAW = 1;

	/**
		Tool: remove them.
	**/
	public static inline final ERASE = 2;

	/**
		Tool: cut a clip in two.
	**/
	public static inline final SLICE = 3;

	/**
		Tool: drag the view.
	**/
	public static inline final PAN = 4;

	/**
		How many tools there are.
	**/
	public static inline final TOOLS = 5;

	/**
		Which pattern is chosen.
	**/
	public var pattern:Int = 0;

	/**
		Which tool is in hand.
	**/
	public var tool:Int = DRAW;

	/**
		Whether playback is the chosen pattern alone rather than the arrangement.
	**/
	public var alone:Bool = false;

	/**
		Whether a MIDI keyboard is recording.
	**/
	public var arming:Bool = false;

	/**
		How many steps a bar is cut into for snapping, or nought for no snap.

		The division is held rather than the tick count it works out to, because a piece
		carries its own resolution and an imported one rarely carries 96. A count fixed
		when it was chosen stops being a sixteenth the moment a piece at another
		resolution is loaded, and at 480 ticks a beat it stops being anything at all.
	**/
	public var snapping:Int = SIXTEENTH;

	/**
		The division that cuts a bar into sixteenths, which is what a piece opens on.
	**/
	public static inline final SIXTEENTH = 16;

	/**
		@return What the editors snap to, in ticks, which follows the piece's resolution.
			Nought where snap is off.
	**/
	public var snap(get, never):Int;

	function get_snap():Int {
		if (snapping < 1) return 0;

		final step = Math.round(song.tempo.ppqn * 4 / snapping);
		return step < 1 ? 1 : step;
	}

	/**
		Whether the other parts are drawn faintly behind the chosen one.
	**/
	public var ghosts:Bool = true;

	/**
		Whether the editor in front keeps the playhead in sight while the song plays, turning the
		view on a page at a time as the playhead reaches its edge.
	**/
	public var following:Bool = true;

	/**
		The key and scale the roll highlights.
	**/
	public final scale:mdd.song.Scale = new mdd.song.Scale();

	/**
		Whether it highlights at all.
	**/
	public var highlight:Bool = true;

	/**
		Which theme is worn.
	**/
	public var theme:Int = 0;

	/**
		Where the monitoring fader stands, nought silent and 127 the top of its travel.

		This is heard and never written. An export takes no notice of it, and what makes
		a written file reach the ceiling is the normalising in `mdd.play.Mixing`.
	**/
	public var master:Int = UNITY;

	/**
		The fader position that passes the render through at the level it was made at.

		The travel above it is make up, because a channel now rests well below the top
		of the part and six of them together reach nothing like it. The travel below is
		half a decibel a step, so the bottom of the fader is 43 decibels down.
	**/
	public static inline final UNITY = 87;

	/**
		What one step of the fader is worth, in decibels.
	**/
	static inline final STEP = 0.5;

	/**
		The most the fader asks for, which is what the top of its travel stands for.
	**/
	public static final MOST:Float = gainOf(Song.LOUDEST);

	/**
		@param fader A fader position, 1 to 127.
		@return The gain it stands for in decibels, nought at unity. The bottom of the travel is
			silence, which no number of decibels says, so the caller answers that one itself.
	**/
	public static inline function decibelsOf(fader:Int):Float {
		return (fader - UNITY) * STEP;
	}

	/**
		@param fader A fader position, 0 to 127.
		@return The gain it stands for, nought at the bottom of the travel.
	**/
	public static function gainOf(fader:Int):Float {
		if (fader <= 0) return 0;
		return Math.pow(10, (fader - UNITY) * STEP / 20.0);
	}

	/**
		Automation is edited as lanes under the roll.
	**/
	public static inline final LANES = 0;

	/**
		Automation is edited as clips on the playlist.
	**/
	public static inline final CLIPS = 1;

	/**
		Which of those two.
	**/
	public var automating:Int = LANES;

	/**
		Which typeface pairing is chosen.
	**/
	public var typeface:Int = 0;

	/**
		How note names are written, a style from `mdd.song.Notation`: sharps or flats, and English
		or German letters.
	**/
	public var notation:Int = 0;

	/**
		Which set of part colours is drawn, `mdd.ui.Theme.STANDARD` or `mdd.ui.Theme.SAFE`.
	**/
	public var partColours:Int = 0;

	/**
		Right clicking a clip takes it off the playlist, with undo the only way back.
	**/
	public static inline final DELETES = 0;

	/**
		Right clicking a clip opens the menu that is otherwise behind the triangle in its
		corner, which is what every other sequencer does with that button.
	**/
	public static inline final OPENS = 1;

	/**
		Which of those two.
	**/
	public var rightClick:Int = DELETES;

	/**
		How much motion the interface uses.
	**/
	public var motion:Int = 0;

	/**
		Called whenever anything here moves, so the interface redraws.
	**/
	public var onChange:Null<Session -> Void> = null;

	/**
		Called when a warning is clicked, to select the note that caused it.
	**/
	public var onReveal:Null<Diagnostic -> Void> = null;

	/**
		The last line for the status bar, where it is a line rather than a name. A line
		put up by name leaves this empty and sets `saidKey` instead.
	**/
	public var said(default, null):String = "";

	/**
		Which string the last line is, or -1 where it is the plain text in `said`.
	**/
	public var saidKey(default, null):Int = -1;

	/**
		What goes in the numbered places of that string, in order.
	**/
	public final saidWith:Array<String> = [];

	/**
		The preset on the clipboard: a copy of what a channel played when it was copied, its patch,
		its envelope or its recording, or null.
	**/
	public var copiedPreset(default, null):Null<mdd.song.Instrument> = null;

	/**
		The recording the preset on the clipboard plays, a copy of its own, or null.
	**/
	public var copiedSample(default, null):Null<mdd.song.Sample> = null;

	/**
		Copies what a channel plays onto the clipboard: its patch, its envelope or its recording,
		with its name and tags, so pasting it is loading that preset.

		@param part Which channel.
		@return Whether the channel played anything to copy.
	**/
	public function copiesPreset(part:Part):Bool {
		final held = song.instrumentAt(song.rack[part.index()]);
		if (held == null) return false;

		final sample = song.sampleAt(held.sample);

		copiedPreset = held.copy();
		copiedSample = sample == null ? null : sample.copy();

		says(Locale.SAID_PRESET_COPIED, part.name());
		changed();

		return true;
	}

	/**
		@param part Which channel.
		@return Whether the preset on the clipboard is one that channel plays: FM on an FM channel,
			a square's envelope on a square, the noise channel's on the noise channel, and a
			recording on the sample channel.
	**/
	public function pastes(part:Part):Bool {
		final held = copiedPreset;
		return held != null && mdd.song.Library.kin(held.kind, part);
	}

	/**
		Loads the preset on the clipboard into a channel as one step on the undo stack, the same
		way choosing it in the preset browser would.

		@param part Which channel.
		@return Whether the clipboard held a preset that channel plays.
	**/
	public function pastesPreset(part:Part):Bool {
		final held = copiedPreset;
		if (held == null || !pastes(part)) return false;

		does(mdd.song.edit.TakesPreset.adopting(part, held.copy(),
			copiedSample == null ? null : copiedSample.copy()));
		says(Locale.SAID_PRESET_PASTED, part.name());

		return true;
	}

	/**
		Puts a channel back to a fresh preset of its kind, keeping its name: a patch every operator
		of which is silent, an envelope that holds one level, or no recording, as one step on the
		undo stack.

		@param part Which channel.
		@return Whether the channel played anything to reset.
	**/
	public function resetsPreset(part:Part):Bool {
		final held = song.instrumentAt(song.rack[part.index()]);
		if (held == null) return false;

		does(mdd.song.edit.TakesPreset.adopting(part, new mdd.song.Instrument(held.name, held.kind), null));
		says(Locale.SAID_PRESET_RESET, part.name());

		return true;
	}

	/**
		The notes on it.
	**/
	public final copiedNotes:Array<mdd.song.Note> = [];

	/**
		The clips on it.
	**/
	public final copiedClips:Array<mdd.song.Clip> = [];

	/**
		Which track each of those clips came from.
	**/
	public final copiedRows:Array<Int> = [];

	/**
		The automation points on it.
	**/
	public final copiedPoints:Array<mdd.song.Point> = [];

	/**
		Builds a session over a piece.

		@param song The piece.
	**/
	public function new(song:Song) {
		this.song = song;
		transport = new Transport(song, 65536);

		for (held in song.instruments) carried.push(held);
	}

	/**
		Works out which presets the piece still keeps although nothing in it plays them any more.

		A preset swapped out of a channel stays the piece's own until a save by hand has left it
		out of the file and the piece has been closed, so a channel can always go back to what it
		played. That holds for everything the piece opened with and for any copy that was played
		with. A copy of an installed preset left exactly as it was is not kept, because the library
		still offers it, and a sound something else already makes is kept once.

		It works out the sound of every preset the piece holds, recordings included, so it belongs
		on a save or on rebuilding the browser rather than on a frame.

		@param played What the piece plays, as `mdd.format.Needed.of` gives it.
		@param saving Whether it is for a save on its own, which leaves out what a save by hand has
			already let go of.
		@return Whether each preset is kept, by index into the piece.
	**/
	public function spares(played:mdd.format.Needed, saving:Bool):haxe.ds.Vector<Bool> {
		final instruments = song.instruments;
		final many = instruments.length;
		final out = new haxe.ds.Vector<Bool>(many);
		final heard = new haxe.ds.StringMap<Bool>();

		for (index in 0...many) {
			out[index] = false;
			if (played.instrument(index) >= 0) heard.set(sounded(instruments[index]), true);
		}

		for (index in 0...many) {
			if (played.instrument(index) >= 0) continue;

			final held = instruments[index];
			if (saving && shed.indexOf(held) >= 0) continue;

			final sound = sounded(held);
			if (heard.exists(sound)) continue;
			if (held.from == sound && carried.indexOf(held) < 0) continue;

			heard.set(sound, true);
			out[index] = true;
		}

		return out;
	}

	/**
		Lets go of every preset nothing plays, which a save by hand does: the file it wrote leaves
		them out, and a save on its own after it does not write them back. `spares` still offers
		them until the piece is closed.

		@param played What the piece plays, as `mdd.format.Needed.of` gives it.
	**/
	public function sheds(played:mdd.format.Needed):Void {
		final instruments = song.instruments;

		for (index in 0...instruments.length) {
			final held = instruments[index];
			if (played.instrument(index) < 0 && shed.indexOf(held) < 0) shed.push(held);
		}
	}

	/**
		@param held A preset the piece holds.
		@return What it sounds like, as `mdd.format.Preset.identity` gives it, worked out now rather
			than read from the identity it last carried, which an edit leaves behind.
	**/
	function sounded(held:mdd.song.Instrument):String {
		return mdd.format.Preset.identity(held, held.kind.sampled() ? song.sampleAt(held.sample) : null);
	}

	static inline final TRACKS = 8;

	/**
		What a new piece starts each part playing, by name, taken out of the bank every piece
		opens with. A name nothing there answers to falls back to the first preset the part can
		play, so a bank edited before a build never leaves a channel silent.
	**/
	static final DEFAULTS:Array<String> = [
		"Lead guitar", "Soft piano", "Punch bass", "Wide pad", "Bright brass", "Soft strings",
		"Square stab", "Power square", "Echo pluck", "Closed hat"
	];

	/**
		Builds a session over a new empty piece with the shipped instruments in it.

		@param library The preset library to take instruments from.
		@return The session.
	**/
	public static function started(library:mdd.song.Library):Session {
		final out = new Session(empty(library));
		out.library = library;

		return out;
	}

	/**
		Where general midi puts a kick, which is where the one a new piece starts with
		sits so that a drum track imported from a file lands on it.
	**/
	public static inline final KICK = 36;

	/**
		Builds a new piece with a track and an instrument for each part, and nothing else: each
		channel's preset is copied out of the library the way loading one copies it, so a new piece
		carries eleven presets rather than everything installed. The sample channel plays a kick
		made here, in a kit of its own, until a kit is loaded.

		@param library The preset library to take instruments from.
		@return The piece.
	**/
	public static function empty(library:mdd.song.Library):Song {
		final song = new Song("untitled", 96, 120);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (part.sampled()) continue;

			final at = played(library, part, index < DEFAULTS.length ? DEFAULTS[index] : "");
			if (at < 0) continue;

			final bank = at >> 16;
			final which = at & 0xFFFF;

			song.rack[index] = song.adopts(library.instruments[bank][which], library.samples[bank][which]);
		}

		final kit = song.instrument(new mdd.song.Instrument("Kick", Part.Dac));
		kit.icon = mdd.Icon.KICK;
		final sample = song.sample(new mdd.song.Sample("Kick", 8000, KICK));

		final bytes = new haxe.ds.Vector<Int>(1200);
		var seed = 0x2C1D;

		for (i in 0...bytes.length) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;

			final fade = 1.0 - i / bytes.length;
			final value = Math.round(Math.sin(i * 0.09) * 110 * fade
				+ ((seed >> 9) % 30 - 15) * fade) + 128;

			bytes[i] = value < 0 ? 0 : (value > 255 ? 255 : value);
		}

		sample.hold(bytes);
		kit.sample = song.samples.length - 1;
		kit.identifies(sample);

		final at = song.instruments.length - 1;

		song.rack[Part.Dac.index()] = at;
		for (bank in song.banks) bank.remove(at);
		song.banked(kit.name).add(at);

		song.add(new Pattern("Pattern 1", 384));

		for (index in 0...TRACKS) song.track(new mdd.song.Track("track " + (index + 1)));

		return song;
	}

	/**
		@param library The preset library.
		@param part A part.
		@param want The name of the preset it should play.
		@return Where that preset sits, as its bank shifted up sixteen bits over its place in the
			bank, looking in the starting bank first, then for the first preset the part can play
			in the starting bank, then anywhere; or -1 where nothing installed plays on the part.
	**/
	static function played(library:mdd.song.Library, part:Part, want:String):Int {
		var first = -1;
		var anywhere = -1;

		for (bank in 0...library.names.length) {
			final starting = library.names[bank] == mdd.song.Library.STARTERS;
			final held = library.instruments[bank];

			for (which in 0...held.length) {
				if (!mdd.song.Library.kin(held[which].kind, part)) continue;

				final at = (bank << 16) | which;

				if (starting && held[which].name == want) return at;
				if (starting && first < 0) first = at;
				if (anywhere < 0) anywhere = at;
			}
		}

		return first >= 0 ? first : anywhere;
	}

	/**
		Takes the lock the render thread also takes, so the song can be changed safely.
		Every `holds` needs a `frees`.
	**/
	public inline function holds():Void {
		transport.holds();
	}

	/**
		Gives that lock back.
	**/
	public inline function frees():Void {
		transport.frees();
	}

	/**
		Applies an edit and puts it on the undo stack, with the render thread held off
		while it lands.

		@param command The edit.
	**/
	public function does(command:Command):Void {
		transport.holds();
		history.does(song, command);
		transport.frees();

		changed();
	}

	/**
		Takes the last edit back.

		@return False where there was nothing to undo.
	**/
	public function undo():Bool {
		transport.holds();
		final done = history.undo(song);
		transport.frees();

		if (done) changed();
		return done;
	}

	/**
		Puts back the last edit that was undone.

		@return False where there was nothing to redo.
	**/
	public function redo():Bool {
		transport.holds();
		final done = history.redo(song);
		transport.frees();

		if (done) changed();
		return done;
	}

	/**
		Selects whatever caused a warning, which is what clicking one does.

		@param found The warning.
	**/
	public function reveal(found:Diagnostic):Void {
		part = found.part;
		if (found.pattern >= 0) pattern = found.pattern;

		saying(found.saying, found.values);

		if (onReveal != null) onReveal(found);
		changed();
	}

	/**
		Puts a line in the status bar, as it stands.

		This is for what carries no words of its own: a file name, a part name, a
		number. Anything with a sentence in it goes through `says` instead, or it
		reaches the bar in the language it was written in whatever is being worn.

		@param said The line.
	**/
	public function say(said:String):Void {
		this.said = said;
		saidKey = -1;
		saidWith.resize(0);
	}

	/**
		Puts a line in the status bar by name, so it is read in the language being worn
		rather than the one it was written in. Changing language changes what is
		already on the bar, because nothing was resolved when it was said.

		@param key Which string, from the table.
		@param one What goes where the string leaves `{0}`.
		@param two What goes in `{1}`.
		@param three What goes in `{2}`.
		@param four What goes in `{3}`.
		@param five What goes in `{4}`.
		@param six What goes in `{5}`.
	**/
	public function says(key:Int, ?one:String, ?two:String, ?three:String,
			?four:String, ?five:String, ?six:String):Void {
		said = "";
		saidKey = key;

		saidWith.resize(0);

		if (one != null) saidWith.push(one);
		if (two != null) saidWith.push(two);
		if (three != null) saidWith.push(three);
		if (four != null) saidWith.push(four);
		if (five != null) saidWith.push(five);
		if (six != null) saidWith.push(six);
	}

	/**
		The same, where the values are already gathered. Anything holding a line to put
		up later keeps the name and the values rather than the sentence, so it is read
		in whatever language is worn when it finally reaches the bar.

		@param key Which string, from the table.
		@param values What goes in its numbered places, in order.
	**/
	public function saying(key:Int, values:Array<String>):Void {
		said = "";
		saidKey = key;

		saidWith.resize(0);
		for (value in values) saidWith.push(value);
	}

	/**
		Tells the interface something moved.
	**/
	public function changed():Void {
		if (onChange != null) onChange(this);
	}

	/**
		Chooses a part, and moves the chosen pattern to one that carries it.

		@param part The part.
	**/
	public function choose(part:Part):Void {
		if (this.part == part) return;

		this.part = part;
		followed(part);
		changed();
	}

	/**
		Finds the pattern a newly chosen part should show.

		@param part The part.
	**/
	function followed(part:Part):Void {
		final held = current();
		if (held != null && held.lane(part).notes.length > 0) return;

		var found = -1;

		for (index in 0...song.patterns.length) {
			if (song.patterns[index].lane(part).notes.length == 0) continue;
			if (found >= 0) return;

			found = index;
		}

		if (found < 0 || found == pattern) return;

		pattern = found;
		follows();
	}

	/**
		Chooses a pattern.

		@param which Which pattern, by index.
	**/
	public function chooses(which:Int):Void {
		if (which < 0 || which >= song.patterns.length || which == pattern) return;

		pattern = which;
		follows();
		changed();
	}

	/**
		The clip the chosen pattern was last opened from on the playlist, or null. Where a pattern is
		placed more than once, this is the placement the editors draw it at while the playhead is in
		none of them.
	**/
	public var opened:Null<mdd.song.Clip> = null;

	/**
		Opens a clip's pattern for editing: chooses the pattern and a channel it carries, keeping the
		chosen channel where the pattern carries that one, and remembers the clip.

		@param clip A clip that plays a pattern. An automation clip is left alone.
	**/
	public function opens(clip:mdd.song.Clip):Void {
		if (clip.kind != mdd.song.Clip.PATTERN) return;

		final held = song.patternAt(clip.pattern);
		if (held == null) return;

		opened = clip;
		pattern = clip.pattern;

		if (!carries(held, part)) {
			for (index in 0...Part.COUNT) {
				if (!carries(held, index)) continue;

				part = index;
				break;
			}
		}

		follows();
		changed();
	}

	/**
		@param held A pattern.
		@param part A channel.
		@return Whether the pattern writes notes or automation on that channel.
	**/
	static function carries(held:Pattern, part:Part):Bool {
		final lane = held.lane(part);
		return lane.notes.length > 0 || lane.automation.length > 0;
	}

	/**
		Where the chosen pattern starts in the song, which the editors measure their ruler, their
		playhead and their scrubbing from, so a pattern placed at bar fifty three is drawn there.

		@param tick Where the playhead is in the song, in ticks.
		@return Nought while the pattern plays alone. Otherwise where the pattern would start for the
			clip playing it at that tick, or else for the clip it was opened from, or else for its
			first clip, and nought where no clip plays it.
	**/
	public function origin(tick:Int):Int {
		if (alone) return 0;

		var first:Null<mdd.song.Clip> = null;
		var still = false;

		for (track in song.tracks) {
			for (clip in track.clips) {
				if (clip.kind != mdd.song.Clip.PATTERN || clip.pattern != pattern) continue;
				if (tick >= clip.at && tick < clip.ends()) return clip.origin();

				if (clip == opened) still = true;
				if (first == null || clip.at < first.at) first = clip;
			}
		}

		final held = opened;
		if (still && held != null) return held.origin();

		return first == null ? 0 : first.origin();
	}

	/**
		Puts a tool in hand.

		@param which Which tool.
	**/
	public function uses(which:Int):Void {
		if (which < 0 || which >= TOOLS || which == tool) return;

		tool = which;
		changed();
	}

	/**
		Switches between playing the chosen pattern and the whole arrangement.

		@param alone Whether to play the pattern alone.
	**/
	public function plays(alone:Bool):Void {
		if (this.alone == alone) return;

		this.alone = alone;
		follows();
		changed();
	}

	/**
		Points the transport at whatever should be playing now.
	**/
	public function follows():Void {
		transport.sequencer.alone = alone ? pattern : -1;
	}

	/**
		@return The chosen pattern, or null where the index is out of range.
	**/
	public function current():Null<Pattern> {
		return song.patternAt(pattern);
	}

	/**
		Changes what happens when more notes are wanted than a part has channels.

		@param policy The behaviour to use.
	**/
	public function policy(policy:Polyphony):Void {
		transport.sequencer.voices.policy = policy;
		changed();
	}

	/**
		@param tick A tick.
		@return It moved to the nearest grid position, or left alone where snap is off.
	**/
	public function snapped(tick:Int):Int {
		final step = snap;
		if (step < 1) return tick;

		return Math.round(tick / step) * step;
	}

	/**
		Rounding to the nearest line is right for moving something that already exists,
		and wrong for placing something new: a click past the middle of a step lands what
		it places on the step after the one that was pointed at.

		@param tick A tick.
		@return Where the grid step holding it begins, or the tick left alone where snap
			is off.
	**/
	public function begins(tick:Int):Int {
		final step = snap;
		if (step < 1) return tick;

		return Math.floor(tick / step) * step;
	}
}
