package mdd.format;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.play.Stream;
import mdd.song.Clip;
import mdd.song.Instrument;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Patch;
import mdd.song.Pattern;
import mdd.song.Sample;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective
final class Transcription {
	static final GROUP:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	public var song(default, null):Song;
	public var notes(default, null):Int = 0;
	public var worstCents(default, null):Float = 0;
	public var offGrid(default, null):Int = 0;
	public var onGrid(default, null):Int = 0;
	public var sounded(default, null):Int = 0;
	public var beats(default, null):Float = 150;

	final shadow:Vector<Int> = new Vector<Int>(512);
	final keyed:Vector<Bool> = new Vector<Bool>(6);
	final startedAt:Vector<Int> = new Vector<Int>(6);
	final startedOn:Vector<Int> = new Vector<Int>(6);

	final psgPeriod:Vector<Int> = new Vector<Int>(4);
	final psgLevel:Vector<Int> = new Vector<Int>(4);
	final psgFrom:Vector<Int> = new Vector<Int>(4);
	final psgNote:Vector<Int> = new Vector<Int>(4);

	var latched:Int = 0;
	var dacOn:Bool = false;
	var dacFrom:Int = -1;
	var dacLast:Int = 0;

	var perTick:Float = 183.75;
	var pattern:Pattern;

	function new() {}

	public static function of(stream:Stream, rate:Int, name:String):Transcription {
		final made = new Transcription();
		made.take(stream, rate, name);
		return made;
	}

	public static function tempoFor(rate:Int):Float {
		return rate == 50 ? 125 : 150;
	}

	function take(stream:Stream, rate:Int, name:String):Void {
		beats = tempoFor(rate);

		song = new Song(name, 96, beats);
		perTick = Tempo.TICKS * 60.0 / (beats * 96);

		for (i in 0...shadow.length) shadow[i] = 0;

		for (i in 0...6) {
			keyed[i] = false;
			startedAt[i] = 0;
			startedOn[i] = 60;
		}

		for (i in 0...4) {
			psgPeriod[i] = 0;
			psgLevel[i] = 15;
			psgFrom[i] = -1;
			psgNote[i] = 60;
		}

		final last = stream.count == 0 ? 0 : stream.tickAt(stream.count - 1);
		pattern = song.add(new Pattern(name, ticked(last) + 96));

		final track = song.track(new Track("imported"));
		track.add(new Clip(0, 0, pattern.length));

		var half = 0;
		var address = -1;

		for (index in 0...stream.count) {
			final at = stream.tickAt(index);
			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) == Stream.PSG) {
				square(at, value);
				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0) continue;

			shadow[(half << 8) | address] = value;
			applied(at, half, address, value);
		}

		close(last);
		for (index in 0...Part.COUNT) song.rack[index] = -1;
		settle();
	}

	inline function ticked(sample:Int):Int {
		return Math.round(sample / perTick);
	}

	function applied(at:Int, half:Int, address:Int, value:Int):Void {
		if (half == 0 && address == 0x28) {
			final within = value & 3;
			if (within == 3) return;

			final channel = within + ((value & 4) != 0 ? 3 : 0);
			final on = (value & 0xF0) != 0;

			if (on && keyed[channel]) {
				finish(at, channel);
				start(at, channel);
			} else if (on) start(at, channel);
			else if (keyed[channel]) finish(at, channel);

			keyed[channel] = on;
			return;
		}

		if (half == 0 && address == 0x2B) {
			final on = (value & 0x80) != 0;

			if (on && !dacOn) dacFrom = at;
			else if (!on && dacOn) sampled(at);

			dacOn = on;
			return;
		}

		if (half == 0 && address == 0x2A) {
			if (dacOn && dacFrom < 0) dacFrom = at;
			dacLast = at;
		}
	}

	function start(at:Int, channel:Int):Void {
		startedAt[channel] = at;
		startedOn[channel] = pitchOf(channel);
	}

	function finish(at:Int, channel:Int):Void {
		final from = ticked(startedAt[channel]);
		var until = ticked(at);

		if (at <= startedAt[channel]) return;
		if (until <= from) until = from + 1;

		final part:Part = channel;
		final note = new Note(from, until - from, startedOn[channel], 100, instrumentFor(channel));

		pattern.lane(part).add(note);
		notes++;
	}

	function sampled(at:Int):Void {
		if (dacFrom < 0) return;

		final from = ticked(dacFrom);
		final until = ticked(at > dacLast ? at : dacLast + 1);
		dacFrom = -1;

		if (until <= from) return;

		pattern.lane(Part.Dac).add(new Note(from, until - from, 60, 100, sampleInstrument()));
		notes++;
	}

	function square(at:Int, value:Int):Void {
		if ((value & 0x80) != 0) {
			latched = (value >> 4) & 0x07;
			final channel = latched >> 1;

			if ((latched & 1) != 0) attenuated(at, channel, value & 0x0F);
			else if (channel < 3) psgPeriod[channel] = (psgPeriod[channel] & 0x3F0) | (value & 0x0F);

			return;
		}

		final channel = latched >> 1;

		if ((latched & 1) != 0) {
			attenuated(at, channel, value & 0x0F);
			return;
		}

		if (channel < 3) psgPeriod[channel] = (psgPeriod[channel] & 0x0F) | ((value & 0x3F) << 4);
	}

	function attenuated(at:Int, channel:Int, level:Int):Void {
		final was = psgLevel[channel];
		psgLevel[channel] = level;

		if (level < 15 && was >= 15) {
			psgFrom[channel] = at;
			psgNote[channel] = channel < 3 ? squareNote(psgPeriod[channel]) : 60;
			return;
		}

		if (level >= 15 && was < 15 && psgFrom[channel] >= 0) {
			final from = ticked(psgFrom[channel]);
			var until = ticked(at);
			final was = psgFrom[channel];
			psgFrom[channel] = -1;

			if (at <= was) return;
			if (until <= from) until = from + 1;

			final part:Part = 6 + channel;
			pattern.lane(part).add(new Note(from, until - from, psgNote[channel], 100,
				squareInstrument(channel)));
			notes++;
		}
	}

	function close(at:Int):Void {
		for (channel in 0...6) if (keyed[channel]) finish(at, channel);
		for (channel in 0...4) if (psgFrom[channel] >= 0) attenuated(at, channel, 15);
		if (dacOn) sampled(at);
	}

	function pitchOf(channel:Int):Int {
		final half = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		final high = shadow[(half << 8) | (0xA4 + within)];
		final low = shadow[(half << 8) | (0xA0 + within)];

		final block = (high >> 3) & 7;
		final number = ((high & 7) << 8) | low;

		if (number == 0) return 60;

		final hertz = number * (Ym2612.CLOCK / Ym2612.PER_SAMPLE) / 1048576.0
			* Math.pow(2, block - 1);

		return nearest(hertz);
	}

	function squareNote(period:Int):Int {
		if (period < 1) return 60;
		return nearest(Sn76489.CLOCK / (32.0 * period));
	}

	function nearest(hertz:Float):Int {
		if (hertz <= 0) return 60;

		final exact = 69 + 12 * Math.log(hertz / 440.0) / Math.log(2);
		var note = Math.round(exact);

		if (note < 0) note = 0;
		if (note > 127) note = 127;

		final off = Math.abs(exact - note) * 100;
		if (off > worstCents) worstCents = off;

		sounded++;
		if (off > 25) offGrid++;
		else if (off < 1) onGrid++;

		return note;
	}

	function instrumentFor(channel:Int):Int {
		final half = channel >= 3 ? 1 : 0;
		final within = channel % 3;

		final patch = new Patch();
		final wiring = shadow[(half << 8) | (0xB0 + within)];

		patch.algorithm = wiring & 7;
		patch.feedback = (wiring >> 3) & 7;

		final sides = shadow[(half << 8) | (0xB4 + within)];
		patch.ams = (sides >> 4) & 3;
		patch.pms = sides & 7;

		for (group in 0...4) {
			final slot = GROUP[group];
			final at = group * 4 + within;

			final tune = shadow[(half << 8) | (0x30 + at)];
			patch.detune[slot] = (tune >> 4) & 7;
			patch.multiple[slot] = tune & 0x0F;

			patch.totalLevel[slot] = shadow[(half << 8) | (0x40 + at)] & 0x7F;

			final attack = shadow[(half << 8) | (0x50 + at)];
			patch.keyScale[slot] = (attack >> 6) & 3;
			patch.attack[slot] = attack & 0x1F;

			final decay = shadow[(half << 8) | (0x60 + at)];
			patch.tremolo[slot] = (decay & 0x80) != 0;
			patch.decay[slot] = decay & 0x1F;

			patch.sustain[slot] = shadow[(half << 8) | (0x70 + at)] & 0x1F;

			final level = shadow[(half << 8) | (0x80 + at)];
			patch.sustainLevel[slot] = (level >> 4) & 0x0F;
			patch.release[slot] = level & 0x0F;

			patch.ssg[slot] = shadow[(half << 8) | (0x90 + at)] & 0x0F;
		}

		return held(patch, Part.Fm1);
	}

	function held(patch:Patch, kind:Part):Int {
		for (index in 0...song.instruments.length) {
			final instrument = song.instruments[index];
			if (instrument.patch == null) continue;
			if (same(instrument.patch, patch)) return index;
		}

		final instrument = new Instrument("patch " + song.instruments.length, kind);
		instrument.patch = patch;
		song.instrument(instrument);

		return song.instruments.length - 1;
	}

	static function same(one:Patch, two:Patch):Bool {
		if (one.algorithm != two.algorithm || one.feedback != two.feedback) return false;
		if (one.ams != two.ams || one.pms != two.pms) return false;

		for (slot in 0...Patch.SLOTS) {
			if (one.detune[slot] != two.detune[slot]) return false;
			if (one.multiple[slot] != two.multiple[slot]) return false;
			if (one.totalLevel[slot] != two.totalLevel[slot]) return false;
			if (one.keyScale[slot] != two.keyScale[slot]) return false;
			if (one.attack[slot] != two.attack[slot]) return false;
			if (one.decay[slot] != two.decay[slot]) return false;
			if (one.sustain[slot] != two.sustain[slot]) return false;
			if (one.sustainLevel[slot] != two.sustainLevel[slot]) return false;
			if (one.release[slot] != two.release[slot]) return false;
			if (one.ssg[slot] != two.ssg[slot]) return false;
			if (one.tremolo[slot] != two.tremolo[slot]) return false;
		}

		return true;
	}

	var squares:Int = -1;
	var sampler:Int = -1;

	function squareInstrument(channel:Int):Int {
		if (squares >= 0) return squares;

		song.instrument(new Instrument("square", Part.Psg1));
		squares = song.instruments.length - 1;

		return squares;
	}

	function sampleInstrument():Int {
		if (sampler >= 0) return sampler;

		final instrument = new Instrument("kit", Part.Dac);
		instrument.sample = song.samples.length;

		song.sample(new Sample("imported", 8000, 60));
		song.instrument(instrument);

		sampler = song.instruments.length - 1;
		return sampler;
	}

	function settle():Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = pattern.lane(part);
			if (lane.notes.length == 0) continue;

			song.rack[index] = lane.notes[0].instrument;
		}
	}
}
