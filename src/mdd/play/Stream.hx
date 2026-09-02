package mdd.play;

import haxe.ds.Vector;
import mdd.chip.Sn76489;
import mdd.chip.Ym2612;
import mdd.song.Envelope;
import mdd.song.Part;
import mdd.song.Patch;

@:unreflective
final class Stream {
	public static inline final YM = 0;
	public static inline final PSG = 1;

	public static inline final MIDDLE = 60;

	static final GROUP:Vector<Int> = Vector.fromArrayCopy([0, 2, 1, 3]);

	public static final FM_NOTES:Vector<Int> = fmNotes();
	public static final PSG_PERIODS:Vector<Int> = psgPeriods();

	static function fmNotes():Vector<Int> {
		final out = new Vector<Int>(12);
		final rate = Ym2612.CLOCK / Ym2612.PER_SAMPLE;

		for (i in 0...12) {
			final hz = 261.6255653005986 * Math.pow(2, i / 12.0);
			out[i] = Math.round(hz * 1048576.0 / rate / 8.0);
		}

		return out;
	}

	static function psgPeriods():Vector<Int> {
		final out = new Vector<Int>(128);

		for (note in 0...128) {
			final hz = 440.0 * Math.pow(2, (note - 69) / 12.0);
			final period = Math.round(Sn76489.CLOCK / (32.0 * hz));

			out[note] = period < 1 ? 1 : (period > 1023 ? 1023 : period);
		}

		return out;
	}

	public static inline function blockOf(note:Int):Int {
		final octave = Std.int(note / 12) - 1;
		return octave < 0 ? 0 : (octave > 7 ? 7 : octave);
	}

	public static inline function frequencyOf(note:Int):Int {
		return FM_NOTES[note % 12];
	}

	public static inline function periodOf(note:Int):Int {
		return PSG_PERIODS[note < 0 ? 0 : (note > 127 ? 127 : note)];
	}

	public var capacity(default, null):Int;
	public var count(default, null):Int = 0;
	public var dropped(default, null):Int = 0;

	final ticks:Vector<Int>;
	final kinds:Vector<Int>;
	final ports:Vector<Int>;
	final values:Vector<Int>;

	public function new(capacity:Int = 8192) {
		this.capacity = capacity < 16 ? 16 : capacity;

		ticks = new Vector<Int>(this.capacity);
		kinds = new Vector<Int>(this.capacity);
		ports = new Vector<Int>(this.capacity);
		values = new Vector<Int>(this.capacity);
	}

	public function clear():Void {
		count = 0;
		dropped = 0;
	}

	public inline function tickAt(index:Int):Int {
		return ticks[index];
	}

	public inline function kindAt(index:Int):Int {
		return kinds[index];
	}

	public inline function portAt(index:Int):Int {
		return ports[index];
	}

	public inline function valueAt(index:Int):Int {
		return values[index];
	}

	public function raw(tick:Int, kind:Int, port:Int, value:Int):Void {
		if (count >= capacity) {
			dropped++;
			return;
		}

		ticks[count] = tick;
		kinds[count] = kind;
		ports[count] = port & 3;
		values[count] = value & 0xFF;
		count++;
	}

	public inline function ym(tick:Int, half:Int, at:Int, value:Int):Void {
		raw(tick, YM, half * 2, at);
		raw(tick, YM, half * 2 + 1, value);
	}

	public inline function psg(tick:Int, value:Int):Void {
		raw(tick, PSG, 0, value);
	}

	public static function ymPart(half:Int, address:Int):Int {
		if (address == 0x2A || address == 0x2B) return Part.Dac.index();
		if (address < 0x30 || address > 0xB6) return -1;

		if (half == 0 && address >= 0xA8 && address <= 0xAE) return 2;

		final channel = address & 3;
		if (channel == 3) return -1;

		return half * 3 + channel;
	}

	public static function keyPart(value:Int):Int {
		final channel = value & 3;
		if (channel == 3) return -1;

		return ((value & 4) != 0 ? 3 : 0) + channel;
	}

	public static inline function halfOf(part:Part):Int {
		return part.index() >= 3 ? 1 : 0;
	}

	public static inline function channelOf(part:Part):Int {
		return part.index() % 3;
	}

	public function patch(tick:Int, part:Part, patch:Patch, velocity:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		for (group in 0...4) {
			final slot = GROUP[group];
			final at = group * 4 + channel;

			ym(tick, half, 0x30 + at, ((patch.detune[slot] & 7) << 4) | (patch.multiple[slot] & 0x0F));
			ym(tick, half, 0x40 + at, levelled(patch, slot, velocity));
			ym(tick, half, 0x50 + at, ((patch.keyScale[slot] & 3) << 6) | (patch.attack[slot] & 0x1F));
			ym(tick, half, 0x60 + at,
				(patch.tremolo[slot] ? 0x80 : 0) | (patch.decay[slot] & 0x1F));
			ym(tick, half, 0x70 + at, patch.sustain[slot] & 0x1F);
			ym(tick, half, 0x80 + at,
				((patch.sustainLevel[slot] & 0x0F) << 4) | (patch.release[slot] & 0x0F));
			ym(tick, half, 0x90 + at, patch.ssg[slot] & 0x0F);
		}

		ym(tick, half, 0xB0 + channel, ((patch.feedback & 7) << 3) | (patch.algorithm & 7));
	}

	public function frequency(tick:Int, part:Part, word:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		ym(tick, half, 0xA4 + channel, (word >> 8) & 0x3F);
		ym(tick, half, 0xA0 + channel, word & 0xFF);
	}

	public function sides(tick:Int, part:Part, value:Int):Void {
		if (!part.fm()) return;

		ym(tick, halfOf(part), 0xB4 + channelOf(part), value & 0xFF);
	}

	public function totalLevel(tick:Int, part:Part, slot:Int, value:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);
		final group = slot == 1 ? 2 : (slot == 2 ? 1 : slot);

		ym(tick, half, 0x40 + group * 4 + channel, value & 0x7F);
	}

	public function level(tick:Int, part:Part, patch:Patch, velocity:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);

		for (group in 0...4) {
			final slot = GROUP[group];
			if (!patch.carries(slot)) continue;

			ym(tick, half, 0x40 + group * 4 + channel, levelled(patch, slot, velocity));
		}
	}

	static function levelled(patch:Patch, slot:Int, velocity:Int):Int {
		final total = patch.totalLevel[slot] & 0x7F;
		if (!patch.carries(slot)) return total;

		final want = velocity < 0 ? 0 : (velocity > 127 ? 127 : velocity);
		final quieter = total + Std.int((127 - total) * (127 - want) / 127);

		return quieter > 127 ? 127 : quieter;
	}

	public function tune(tick:Int, part:Part, note:Int):Void {
		if (!part.fm()) return;

		final half = halfOf(part);
		final channel = channelOf(part);
		final block = blockOf(note);
		final frequency = frequencyOf(note);

		ym(tick, half, 0xA4 + channel, ((block & 7) << 3) | ((frequency >> 8) & 7));
		ym(tick, half, 0xA0 + channel, frequency & 0xFF);
	}

	public function keyOn(tick:Int, part:Part):Void {
		if (!part.fm()) return;
		ym(tick, 0, 0x28, 0xF0 | select(part));
	}

	public function keyOff(tick:Int, part:Part):Void {
		if (!part.fm()) return;
		ym(tick, 0, 0x28, select(part));
	}

	static inline function select(part:Part):Int {
		return channelOf(part) | (part.index() >= 3 ? 4 : 0);
	}

	public function square(tick:Int, part:Part, note:Int):Void {
		if (!part.square()) return;

		final channel = part.index() - 6;
		final period = periodOf(note);

		psg(tick, 0x80 | (channel << 5) | (period & 0x0F));
		psg(tick, (period >> 4) & 0x3F);
	}

	public function attenuate(tick:Int, part:Part, attenuation:Int):Void {
		if (!part.square() && !part.noise()) return;

		final channel = part.index() - 6;
		final held = attenuation < 0 ? 0 : (attenuation > 15 ? 15 : attenuation);

		psg(tick, 0x80 | (channel << 5) | 0x10 | held);
	}

	public function noise(tick:Int, mode:Int):Void {
		psg(tick, 0x80 | 0x60 | (mode & 0x0F));
	}

	public function loudness(tick:Int, part:Part, envelope:Null<Envelope>, velocity:Int,
			step:Int):Void {
		final want = velocity < 0 ? 0 : (velocity > 127 ? 127 : velocity);
		final quiet = 15 - Std.int(want * 15 / 127);
		final shaped = envelope == null || envelope.steps.length == 0 ? 0 : envelope.at(step);

		attenuate(tick, part, quiet + shaped);
	}

	public function silence(tick:Int, part:Part):Void {
		if (part.fm()) {
			keyOff(tick, part);
			return;
		}

		if (part.square() || part.noise()) {
			attenuate(tick, part, 15);
			return;
		}

		if (!part.sampled()) return;

		byte(tick, 0x80);
		sampling(tick, false);
	}

	public function sampling(tick:Int, on:Bool):Void {
		ym(tick, 0, 0x2B, on ? 0x80 : 0x00);
	}

	public function byte(tick:Int, value:Int):Void {
		ym(tick, 0, 0x2A, value & 0xFF);
	}

	public function lfo(tick:Int, on:Bool, rate:Int):Void {
		ym(tick, 0, 0x22, (on ? 0x08 : 0) | (rate & 7));
	}

	public function reset(tick:Int):Void {
		lfo(tick, false, 0);
		sampling(tick, false);

		for (index in 0...6) {
			final part:Part = index;
			final half = halfOf(part);
			final channel = channelOf(part);

			for (group in 0...4) ym(tick, half, 0x80 + group * 4 + channel, 0x0F);

			keyOff(tick, part);
			ym(tick, half, 0xB4 + channel, 0xC0);
		}

		for (index in 6...10) attenuate(tick, index, 15);
		noise(tick, 4);
	}
}
