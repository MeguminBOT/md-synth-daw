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
		What the editors snap to, in ticks.
	**/
	public var snap:Int = 24;

	/**
		Whether the other parts are drawn faintly behind the chosen one.
	**/
	public var ghosts:Bool = true;

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
		The monitoring volume.
	**/
	public var master:Int = Song.LOUDEST;

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
		The last line for the status bar.
	**/
	public var said(default, null):String = "";

	/**
		The patch on the clipboard.
	**/
	public var copiedPatch:Null<mdd.song.Patch> = null;

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
	}

	static inline final TRACKS = 8;

	static final DEFAULTS:Array<Int> = [0, 1, 4, 5, 8, 2, 16, 17, 18, 22];

	/**
		Builds a session over a new empty piece with the shipped instruments in it.

		@param library The preset library to take instruments from.
		@return The session.
	**/
	public static function started(library:mdd.song.Library):Session {
		return new Session(empty(library));
	}

	/**
		Builds a new piece with a track and an instrument for each part.

		@param library The preset library to take instruments from.
		@return The piece.
	**/
	public static function empty(library:mdd.song.Library):Song {
		final song = new Song("untitled", 96, 120);

		mdd.song.Shipped.into(song);

		library.into(song);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (part.sampled()) continue;

			final want = DEFAULTS[index];
			song.rack[index] = want < song.instruments.length ? want : 0;
		}

		final kit = song.instrument(new mdd.song.Instrument("Kick", Part.Dac));
		kit.icon = mdd.Icon.KICK;
		final sample = song.sample(new mdd.song.Sample("Kick", 8000, 60));

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
		kit.sample = 0;
		song.rack[Part.Dac.index()] = song.instruments.length - 1;

		song.add(new Pattern("pattern 1", 384));

		for (index in 0...TRACKS) song.track(new mdd.song.Track("track " + (index + 1)));

		return song;
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

		say(found.line());

		if (onReveal != null) onReveal(found);
		changed();
	}

	/**
		Puts a line in the status bar.

		@param said The line.
	**/
	public function say(said:String):Void {
		this.said = said;
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
		if (snap < 1) return tick;
		return Math.round(tick / snap) * snap;
	}
}
