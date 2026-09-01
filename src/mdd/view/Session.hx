package mdd.view;

import mdd.check.Diagnostic;
import mdd.play.Polyphony;
import mdd.play.Transport;
import mdd.song.Command;
import mdd.song.History;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Song;

@:unreflective
final class Session {
	public final song:Song;
	public final history:History = new History();
	public final transport:Transport;

	public var part:Part = Part.Fm1;
	public var pattern:Int = 0;
	public var snap:Int = 24;
	public var ghosts:Bool = true;
	public final scale:mdd.song.Scale = new mdd.song.Scale();
	public var highlight:Bool = true;
	public var theme:Int = 0;
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

	public static function started():Session {
		final song = new Song("untitled", 96, 120);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			if (part.sampled()) continue;

			final instrument = song.instrument(new mdd.song.Instrument(part.name().toLowerCase(),
				part));

			if (instrument.patch != null) {
				instrument.patch.algorithm = 4;
				instrument.patch.feedback = 3;

				for (slot in 0...4) {
					instrument.patch.totalLevel[slot] = instrument.patch.carries(slot) ? 12 : 34;
					instrument.patch.attack[slot] = 28;
					instrument.patch.decay[slot] = 10;
					instrument.patch.sustainLevel[slot] = 3;
					instrument.patch.sustain[slot] = 3;
					instrument.patch.release[slot] = 8;
					instrument.patch.multiple[slot] = 1 + (slot & 1);
				}
			}

			if (instrument.envelope != null) {
				instrument.envelope.steps.push(0);
				instrument.envelope.steps.push(2);
				instrument.envelope.steps.push(5);
				instrument.envelope.loop = 2;
			}

			song.rack[index] = index;
		}

		final kit = song.instrument(new mdd.song.Instrument("kick", Part.Dac));
		final sample = song.sample(new mdd.song.Sample("kick", 8000, 60));

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

		final track = song.track(new mdd.song.Track("track 1"));
		track.add(new mdd.song.Clip(0, 0, 384));

		return new Session(song);
	}

	public function does(command:Command):Void {
		history.does(song, command);
		changed();
	}

	public function undo():Bool {
		final done = history.undo(song);
		if (done) changed();
		return done;
	}

	public function redo():Bool {
		final done = history.redo(song);
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
		changed();
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
