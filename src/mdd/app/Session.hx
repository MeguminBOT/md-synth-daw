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
final class Session {
	public final song:Song;
	public final history:History = new History();
	public final transport:Transport;

	public var part:Part = Part.Fm1;
	public static inline final SELECT = 0;
	public static inline final DRAW = 1;
	public static inline final ERASE = 2;
	public static inline final SLICE = 3;
	public static inline final PAN = 4;
	public static inline final TOOLS = 5;

	public var pattern:Int = 0;
	public var tool:Int = DRAW;
	public var alone:Bool = false;
	public var arming:Bool = false;
	public var snap:Int = 24;
	public var ghosts:Bool = true;
	public final scale:mdd.song.Scale = new mdd.song.Scale();
	public var highlight:Bool = true;
	public var theme:Int = 0;
	public var typeface:Int = 0;
	public var motion:Int = 0;

	public var onChange:Null<Session -> Void> = null;
	public var onReveal:Null<Diagnostic -> Void> = null;

	public var said(default, null):String = "";

	public var copiedPatch:Null<mdd.song.Patch> = null;
	public final copiedNotes:Array<mdd.song.Note> = [];

	public function new(song:Song) {
		this.song = song;
		transport = new Transport(song, 65536);
	}

	public static inline final TRACKS = 8;

	static final DEFAULTS:Array<Int> = [0, 1, 4, 5, 8, 2, 16, 17, 18, 22];

	public static function started():Session {
		final song = new Song("untitled", 96, 120);

		mdd.song.Shipped.into(song);

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
		song.tracks[0].add(new mdd.song.Clip(0, 0, 384));

		return new Session(song);
	}

	public inline function holds():Void {
		transport.holds();
	}

	public inline function frees():Void {
		transport.frees();
	}

	public function does(command:Command):Void {
		transport.holds();
		history.does(song, command);
		transport.frees();

		changed();
	}

	public function undo():Bool {
		transport.holds();
		final done = history.undo(song);
		transport.frees();

		if (done) changed();
		return done;
	}

	public function redo():Bool {
		transport.holds();
		final done = history.redo(song);
		transport.frees();

		if (done) changed();
		return done;
	}

	public function reveal(found:Diagnostic):Void {
		part = found.part;
		if (found.pattern >= 0) pattern = found.pattern;

		say(found.line());

		if (onReveal != null) onReveal(found);
		changed();
	}

	public function say(said:String):Void {
		this.said = said;
	}

	public function changed():Void {
		if (onChange != null) onChange(this);
	}

	public function choose(part:Part):Void {
		if (this.part == part) return;

		this.part = part;
		followed(part);
		changed();
	}

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

	public function chooses(which:Int):Void {
		if (which < 0 || which >= song.patterns.length || which == pattern) return;

		pattern = which;
		follows();
		changed();
	}

	public function uses(which:Int):Void {
		if (which < 0 || which >= TOOLS || which == tool) return;

		tool = which;
		changed();
	}

	public function plays(alone:Bool):Void {
		if (this.alone == alone) return;

		this.alone = alone;
		follows();
		changed();
	}

	public function follows():Void {
		transport.sequencer.alone = alone ? pattern : -1;
	}

	public function current():Null<Pattern> {
		return song.patternAt(pattern);
	}

	public function policy(policy:Polyphony):Void {
		transport.sequencer.voices.policy = policy;
		changed();
	}

	public function snapped(tick:Int):Int {
		if (snap < 1) return tick;
		return Math.round(tick / snap) * snap;
	}
}
