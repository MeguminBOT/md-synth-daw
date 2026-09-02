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
	final startedWith:Vector<Int> = new Vector<Int>(6);
	final tying:Vector<Bool> = new Vector<Bool>(6);
	final started:Vector<Bool> = new Vector<Bool>(6);

	final psgPeriod:Vector<Int> = new Vector<Int>(4);
	final psgLevel:Vector<Int> = new Vector<Int>(4);
	final psgFrom:Vector<Int> = new Vector<Int>(4);
	final psgNote:Vector<Int> = new Vector<Int>(4);

	static inline final ENVELOPE_TICKS = 735;
	static inline final ENVELOPE_STEPS = 96;

	final psgWhen:Array<Array<Int>> = [[], [], [], []];
	final psgHeld:Array<Array<Int>> = [[], [], [], []];
	final shapes:Array<Int> = [];

	var latched:Int = 0;
	var noiseMode:Int = 4;
	var dacOn:Bool = false;
	var dacHead:Int = -1;
	var dacLast:Int = 0;

	static inline final DAC_GAP = 2205;
	static inline final DAC_LEAST = 48;
	static inline final DAC_ROOM = 262144;

	final dacBytes:Array<Int> = [];
	final kits:Array<Int> = [];
	var dacHeld:Int = 0;

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

		for (half in 0...2) {
			for (at in 0x40...0x50) shadow[(half << 8) | at] = 0x7F;
		}

		for (i in 0...6) {
			keyed[i] = false;
			startedAt[i] = 0;
			startedOn[i] = 60;
			startedWith[i] = -1;
			tying[i] = false;
			started[i] = false;
		}

		for (i in 0...levels.length) levels[i] = -1;
		for (i in 0...stereos.length) stereos[i] = -1;

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
		parted();
		session();
		mdd.song.Shipped.into(song);
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
				tying[channel] = true;
				start(at, channel);
			} else if (on) {
				tying[channel] = false;
				start(at, channel);
			} else if (keyed[channel]) {
				finish(at, channel);
			}

			keyed[channel] = on;
			return;
		}

		if (half == 0 && address == 0x22) {
			song.lfoOn = (value & 0x08) != 0;
			song.lfoRate = value & 7;
			return;
		}

		if (half == 0 && address == 0x2B) {
			final on = (value & 0x80) != 0;

			if (!on && dacOn) sampled(at);

			dacOn = on;
			return;
		}

		if (address >= 0x40 && address <= 0x4F && (address & 3) != 3) {
			levelled(at, half, address, value & 0x7F);
			return;
		}

		if (address >= 0xB4 && address <= 0xB6 && (address & 3) != 3) {
			sided(at, half * 3 + (address & 3), value & 0xFF);
			return;
		}

		if (half == 0 && address == 0x2A) {
			if (!dacOn) return;

			if (dacHead >= 0 && at - dacLast > DAC_GAP) sampled(dacLast + 1);

			if (dacHead < 0) {
				dacHead = at;
				dacBytes.resize(0);
			}

			dacBytes.push(value & 0xFF);
			dacLast = at;
		}
	}

	static final GROUP_OF:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	final levels:Vector<Int> = new Vector<Int>(24);

	final stereos:Vector<Int> = new Vector<Int>(6);

	function sided(at:Int, channel:Int, value:Int):Void {
		if (stereos[channel] == value) return;

		final was = stereos[channel];
		stereos[channel] = value;

		if (was < 0) return;

		final line = lined(channel, mdd.song.Automation.SIDES, 0, was);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	function lined(channel:Int, target:Int, slot:Int, first:Int):Null<mdd.song.Automation> {
		final lane = pattern.lane(channel);

		for (held in lane.automation) {
			if (!held.held(target, slot)) continue;
			return held.points.length >= mdd.song.Automation.ROOM ? null : held;
		}

		final made = new mdd.song.Automation(target, slot);

		lane.automation.push(made);
		made.add(new mdd.song.Point(0, first));

		return made;
	}

	function levelled(at:Int, half:Int, address:Int, value:Int):Void {
		final channel = half * 3 + (address & 3);
		final slot = GROUP_OF[(address - 0x40) >> 2];
		final which = channel * 4 + slot;

		if (levels[which] == value) return;

		final was = levels[which];
		levels[which] = value;

		if (was < 0) return;

		final line = lined(channel, mdd.song.Automation.LEVEL, slot, was);
		if (line == null) return;

		line.add(new mdd.song.Point(ticked(at), value));
	}

	function placed(part:Part, from:Int, until:Int, pitch:Int, instrument:Int,
			velocity:Int = 127, tied:Bool = false):Void {
		final lane = pattern.lane(part);
		final many = lane.notes.length;

		if (many > 0) {
			final last = lane.notes[many - 1];

			if (last.at + last.length > from) {
				final want = from - last.at;

				if (want < 1) {
					lane.notes.remove(last);
					notes--;
				} else {
					last.length = want;
				}
			}
		}

		final made = new Note(from, until - from, pitch, velocity, instrument);
		made.tied = tied;

		lane.add(made);
		notes++;
	}

	function start(at:Int, channel:Int):Void {
		startedAt[channel] = at;
		startedOn[channel] = pitchOf(channel);
		startedWith[channel] = instrumentFor(channel);
		started[channel] = tying[channel];
	}

	function finish(at:Int, channel:Int):Void {
		final from = ticked(startedAt[channel]);
		var until = ticked(at);

		if (at <= startedAt[channel]) return;
		if (until <= from) until = from + 1;

		placed(channel, from, until, startedOn[channel], startedWith[channel] < 0
			? instrumentFor(channel) : startedWith[channel], 127, started[channel]);
	}

	function sampled(at:Int):Void {
		if (dacHead < 0) return;

		final head = dacHead;
		final tail = at > dacLast ? at : dacLast + 1;
		dacHead = -1;

		final wrote = dacBytes.length;
		trimmed();

		if (dacBytes.length < DAC_LEAST || tail <= head || wrote < 1) {
			dacBytes.resize(0);
			return;
		}

		final which = sampleInstrument(Math.round((tail - head) / wrote * dacBytes.length));

		final from = ticked(head);
		var until = ticked(tail);
		if (until <= from) until = from + 1;

		dacBytes.resize(0);

		if (which < 0) return;

		placed(Part.Dac, from, until, 60, which);
	}

	function trimmed():Void {
		var tail = dacBytes.length;
		while (tail > 0 && quiet(dacBytes[tail - 1])) tail--;

		var head = 0;
		while (head < tail && quiet(dacBytes[head])) head++;

		if (head == 0 && tail == dacBytes.length) return;

		final held = dacBytes.slice(head, tail);
		dacBytes.resize(0);
		for (byte in held) dacBytes.push(byte);
	}

	static inline function quiet(byte:Int):Bool {
		final away = byte - 0x80;
		return (away < 0 ? -away : away) < 3;
	}

	function square(at:Int, value:Int):Void {
		if ((value & 0x80) != 0) {
			latched = (value >> 4) & 0x07;
			final channel = latched >> 1;

			if ((latched & 1) != 0) attenuated(at, channel, value & 0x0F);
			else if (channel < 3) psgPeriod[channel] = (psgPeriod[channel] & 0x3F0) | (value & 0x0F);
			else noiseMode = value & 0x0F;

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

			psgWhen[channel].resize(0);
			psgHeld[channel].resize(0);
			psgWhen[channel].push(at);
			psgHeld[channel].push(level);
			return;
		}

		if (level < 15 && psgFrom[channel] >= 0) {
			if (level == was) return;

			psgWhen[channel].push(at);
			psgHeld[channel].push(level);
			return;
		}

		if (level >= 15 && was < 15 && psgFrom[channel] >= 0) {
			final head = psgFrom[channel];
			final from = ticked(head);
			var until = ticked(at);
			psgFrom[channel] = -1;

			if (at <= head) return;
			if (until <= from) until = from + 1;

			final loudest = psgHeld[channel][0];
			final velocity = Math.round((15 - loudest) * 127 / 15);

			placed(6 + channel, from, until, psgNote[channel],
				squareInstrument(channel, head, at), velocity < 1 ? 1 : velocity);
		}
	}

	function shaped(channel:Int, head:Int, tail:Int):Array<Int> {
		final when = psgWhen[channel];
		final held = psgHeld[channel];
		final steps:Array<Int> = [];

		if (when.length == 0) return steps;

		final loudest = held[0];
		var many = Math.ceil((tail - head) / ENVELOPE_TICKS);

		if (many < 1) many = 1;
		if (many > ENVELOPE_STEPS) many = ENVELOPE_STEPS;

		var at = 0;

		for (step in 0...many) {
			final want = head + step * ENVELOPE_TICKS;
			while (at + 1 < when.length && when[at + 1] <= want) at++;

			final away = held[at] - loudest;
			steps.push(away < 0 ? 0 : (away > 15 ? 15 : away));
		}

		while (steps.length > 1 && steps[steps.length - 1] == steps[steps.length - 2]) {
			steps.pop();
		}

		return steps;
	}

	function parted():Void {
		final source = pattern;
		final length = source.length;

		var used = 0;
		for (index in 0...Part.COUNT) if (source.lane(index).notes.length > 0) used++;

		if (used < 2) return;

		song.patterns.remove(source);
		while (song.tracks.length > 0) song.tracks.remove(song.tracks[0]);

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = source.lane(part);
			if (lane.notes.length == 0) continue;

			final made = song.add(new Pattern(part.name(), length,
				mdd.ui.Theme.PARTS[index]));

			for (note in lane.notes) made.lane(part).add(note);
			for (line in lane.automation) made.lane(part).automation.push(line);

			final track = song.track(new Track(part.name()));
			track.add(new Clip(song.patterns.length - 1, 0, length));
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

		final stereo = (sides >> 6) & 3;
		if (stereo != 0) song.pan[channel] = stereo;

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

	function squareInstrument(channel:Int, head:Int, tail:Int):Int {
		final steps = shaped(channel, head, tail);
		final noise = channel == 3 ? noiseMode : -1;

		for (index in 0...shapes.length) {
			final held = song.instruments[shapes[index]];
			if (held.envelope == null) continue;
			if (noise >= 0 && held.envelope.noise != noise) continue;
			if (noise < 0 && held.kind.noise()) continue;
			if (noise >= 0 && !held.kind.noise()) continue;
			if (!alikeShape(held.envelope.steps, steps)) continue;

			return shapes[index];
		}

		final kind = channel == 3 ? Part.Noise : Part.Psg1;
		final instrument = new Instrument((channel == 3 ? "noise " : "square ")
			+ (shapes.length + 1), kind);

		if (instrument.envelope != null) {
			for (step in steps) instrument.envelope.steps.push(step);
			if (noise >= 0) instrument.envelope.noise = noise;
		}

		song.instrument(instrument);
		shapes.push(song.instruments.length - 1);

		if (squares < 0) squares = song.instruments.length - 1;
		return song.instruments.length - 1;
	}

	static function alikeShape(one:Array<Int>, two:Array<Int>):Bool {
		if (one.length != two.length) return false;
		for (index in 0...one.length) if (one[index] != two[index]) return false;

		return true;
	}

	function sampleInstrument(span:Int):Int {
		final many = dacBytes.length;

		for (index in 0...song.samples.length) {
			if (alike(song.samples[index])) return kits[index];
		}

		if (dacHeld + many > DAC_ROOM) return kits.length == 0 ? -1 : kits[0];

		final counted = Math.round(many * Tempo.TICKS / (span < 1 ? 1 : span));
		final rate = counted < 2000 ? 2000 : (counted > 32000 ? 32000 : counted);

		final held = new Vector<Int>(many);
		for (index in 0...many) held[index] = dacBytes[index];

		final sample = new Sample("hit " + (song.samples.length + 1), rate, 60);
		sample.hold(held);
		song.sample(sample);

		final instrument = new Instrument(sample.name, Part.Dac);
		instrument.sample = song.samples.length - 1;
		song.instrument(instrument);

		kits.push(song.instruments.length - 1);
		dacHeld += many;

		return song.instruments.length - 1;
	}

	function alike(sample:Sample):Bool {
		if (sample.length() != dacBytes.length) return false;

		final bytes = sample.bytes;
		for (index in 0...bytes.length) if (bytes[index] != dacBytes[index]) return false;

		return true;
	}

	function session():Void {
		if (song.instruments.length == 0) return;

		final bank = song.banked("from the import", false);
		for (index in 0...song.instruments.length) bank.add(index);

		song.banks[0].instruments.resize(0);
	}

	function settle():Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final lane = pattern.lane(part);

			if (lane.notes.length > 0) {
				song.rack[index] = lane.notes[0].instrument;
				continue;
			}

			if (part.sampled()) song.rack[index] = -1;
			else if (part.noise()) song.rack[index] = mdd.song.Shipped.firstNoise(song);
			else if (part.square()) song.rack[index] = mdd.song.Shipped.firstSquare(song);
			else song.rack[index] = mdd.song.Shipped.firstFm(song);
		}
	}
}
