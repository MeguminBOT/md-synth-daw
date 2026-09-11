package mdd.song;

import haxe.ds.Vector;
import mdd.app.Locale;

/**
	One FM patch: the algorithm, the feedback, the two LFO sensitivities, and ten
	fields for each of four operators.

	That is exactly what a chip is set to at a key on, which is why an imported patch
	is forty two bytes of register values and claims nothing more. Fields are read and
	written by index as well as by name, so an editor can walk them without knowing
	what each one is.
**/
@:unreflective
final class Patch {
	/**
		How many operators a channel has.
	**/
	public static inline final SLOTS = 4;

	/**
		How many fields each operator carries.
	**/
	public static inline final ROWS = 10;

	/**
		How many channel wide values there are.
	**/
	public static inline final DIALS = 4;

	/**
		Dial: which of the eight operator wirings.
	**/
	public static inline final ALGORITHM = 0;

	/**
		Dial: how much operator one feeds back.
	**/
	public static inline final FEEDBACK = 1;

	/**
		Dial: how far the LFO swings the amplitude.
	**/
	public static inline final AMS = 2;

	/**
		Dial: how far the LFO swings the pitch.
	**/
	public static inline final PMS = 3;

	/**
		Each operator field as the documentation names it, which is never translated.
	**/
	public static final NAMES:Array<String> = ["TL", "AR", "D1R", "D1L", "D2R", "RR", "MUL",
		"DT", "RS", "SSG"];

	/**
		The same fields spelt out, for a tooltip and for anywhere there is room to read
		rather than to recognise. These are prose where the names above are what the
		documentation calls the registers, so these are looked up and those are not.
	**/
	public static final SPELT:Array<Locale> = [Locale.FIELD_TOTAL_LEVEL,
		Locale.FIELD_ATTACK_RATE, Locale.FIELD_FIRST_DECAY, Locale.FIELD_SUSTAIN_LEVEL,
		Locale.FIELD_SECOND_DECAY, Locale.FIELD_RELEASE_RATE, Locale.FIELD_MULTIPLE,
		Locale.FIELD_DETUNE, Locale.FIELD_RATE_SCALING, Locale.FIELD_SSG_ENVELOPE];

	/**
		Each dial as the documentation names it.
	**/
	public static final DIAL_NAMES:Array<String> = ["ALG", "FB", "AMS", "PMS"];

	/**
		The same dials spelt out.
	**/
	public static final DIAL_SPELT:Array<Locale> = [Locale.FIELD_ALGORITHM,
		Locale.FIELD_FEEDBACK, Locale.FIELD_TREMOLO, Locale.FIELD_VIBRATO];

	/**
		The largest value each dial takes.
	**/
	static final DIAL_MOST:Array<Int> = [7, 7, 3, 7];

	/**
		Which of the eight operator wirings, 0 to 7.
	**/
	public var algorithm:Int = 0;

	/**
		How much operator one feeds back into itself, 0 to 7.
	**/
	public var feedback:Int = 0;

	/**
		How far the LFO swings the amplitude, 0 to 3.
	**/
	public var ams:Int = 0;

	/**
		How far the LFO swings the pitch, 0 to 7.
	**/
	public var pms:Int = 0;

	/**
		Detune, per operator.
	**/
	public final detune:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Frequency multiple, per operator.
	**/
	public final multiple:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Attenuation, per operator, 0 loudest and 127 silent.
	**/
	public final totalLevel:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Where a carrier rests before a velocity is applied.

		A driver keeps its channel volume apart from the voice and adds it to the carrier
		levels at every key on, so a voice ripped out of a game is a timbre with no
		loudness attached to it. Playing one at nought puts a single channel at the
		loudest the part goes, which no driver does: measured across the register logs,
		a carrier stands at 22 when a key on arrives. That is the number a channel is
		built around, and it is what leaves room for the other five.
	**/
	public static inline final REST = 22;

	/**
		How much the key code scales the rates, per operator.
	**/
	public final keyScale:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Attack rate, per operator.
	**/
	public final attack:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Decay rate, per operator.
	**/
	public final decay:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Sustain rate, per operator.
	**/
	public final sustain:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Where the decay gives way to the sustain, per operator.
	**/
	public final sustainLevel:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Release rate, per operator.
	**/
	public final release:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		The SSG-EG nibble, per operator.
	**/
	public final ssg:Vector<Int> = new Vector<Int>(SLOTS);

	/**
		Whether the LFO swings this operator's amplitude, per operator.
	**/
	public final tremolo:Vector<Bool> = new Vector<Bool>(SLOTS);

	/**
		Builds a silent patch with every field at nought.
	**/
	public function new() {
		for (i in 0...SLOTS) {
			detune[i] = 0;
			multiple[i] = 1;
			totalLevel[i] = i == SLOTS - 1 ? REST : 127;
			keyScale[i] = 0;
			attack[i] = 31;
			decay[i] = 0;
			sustain[i] = 0;
			sustainLevel[i] = 0;
			release[i] = 15;
			ssg[i] = 0;
			tremolo[i] = false;
		}
	}

	/**
		@param row Which operator field, 0 to 9.
		@return The largest value it takes, which is the width of its register field.
	**/
	public static function mostOf(row:Int):Int {
		return switch (row) {
			case 0: 127;
			case 1, 2, 4, 5: 31;
			case 3: 15;
			case 6: 15;
			case 7: 7;
			case 8: 3;
			case _: 15;
		}
	}

	/**
		@param which Which dial, 0 to 3.
		@return The largest value it takes.
	**/
	public static function mostDial(which:Int):Int {
		return which < 0 || which >= DIALS ? 0 : DIAL_MOST[which];
	}

	/**
		Reads one operator field by index, so an editor can walk them.

		@param slot Which operator, 0 to 3.
		@param row Which field, 0 to 9.
		@return Its value.
	**/
	public function reads(slot:Int, row:Int):Int {
		return switch (row) {
			case 0: totalLevel[slot];
			case 1: attack[slot];
			case 2: decay[slot];
			case 3: sustainLevel[slot];
			case 4: sustain[slot];
			case 5: release[slot];
			case 6: multiple[slot];
			case 7: detune[slot];
			case 8: keyScale[slot];
			case _: ssg[slot];
		}
	}

	/**
		Writes one operator field by index, clamped to what the register holds.

		@param slot Which operator, 0 to 3.
		@param row Which field, 0 to 9.
		@param value The value to write.
	**/
	public function writes(slot:Int, row:Int, value:Int):Void {
		final most = mostOf(row);
		final want = value < 0 ? 0 : (value > most ? most : value);

		switch (row) {
			case 0: totalLevel[slot] = want;
			case 1: attack[slot] = want;
			case 2: decay[slot] = want;
			case 3: sustainLevel[slot] = want;
			case 4: sustain[slot] = want;
			case 5: release[slot] = want;
			case 6: multiple[slot] = want;
			case 7: detune[slot] = want;
			case 8: keyScale[slot] = want;
			case _: ssg[slot] = want;
		}
	}

	/**
		@param which Which dial, 0 to 3.
		@return Its value.
	**/
	public function dial(which:Int):Int {
		return switch (which) {
			case ALGORITHM: algorithm;
			case FEEDBACK: feedback;
			case AMS: ams;
			case _: pms;
		}
	}

	/**
		Writes one dial, clamped to what it holds.

		@param which Which dial, 0 to 3.
		@param value The value to write.
	**/
	public function turns(which:Int, value:Int):Void {
		final most = mostDial(which);
		final want = value < 0 ? 0 : (value > most ? most : value);

		switch (which) {
			case ALGORITHM: algorithm = want;
			case FEEDBACK: feedback = want;
			case AMS: ams = want;
			case _: pms = want;
		}
	}

	/**
		@param slot Which operator, 0 to 3.
		@return Whether it is a carrier under the current algorithm, so its total level is what
			velocity scales.
	**/
	public function carries(slot:Int):Bool {
		return switch (algorithm) {
			case 0, 1, 2, 3: slot == 3;
			case 4: slot == 1 || slot == 3;
			case 5, 6: slot == 1 || slot == 2 || slot == 3;
			case _: true;
		}
	}

	/**
		Brings every carrier up so the loudest sits at full, which is what two patches
		from different sources have to be put through before they can be compared.
	**/
	public function raises():Void {
		var least = 127;

		for (slot in 0...SLOTS) {
			if (!carries(slot)) continue;
			if (totalLevel[slot] < least) least = totalLevel[slot];
		}

		if (least <= 0 || least > 127) return;

		for (slot in 0...SLOTS) {
			if (!carries(slot)) continue;
			totalLevel[slot] -= least;
		}
	}

	/**
		Moves every carrier so the loudest sits at the resting level, keeping whatever
		balance the carriers had between them.

		This is what a voice needs before it can be played at a velocity. A voice arrives
		as a timbre with no loudness attached, and a velocity only ever attenuates, so
		one played as it arrives has nowhere above it to go and sits far louder than the
		driver it came from ever put it.
	**/
	public function rests():Void {
		raises();

		for (slot in 0...SLOTS) {
			if (!carries(slot)) continue;

			final want = totalLevel[slot] + REST;
			totalLevel[slot] = want > 127 ? 127 : want;
		}
	}

	/**
		@return A new patch with the same values.
	**/
	public function copy():Patch {
		final out = new Patch();

		out.algorithm = algorithm;
		out.feedback = feedback;
		out.ams = ams;
		out.pms = pms;

		for (i in 0...SLOTS) {
			out.detune[i] = detune[i];
			out.multiple[i] = multiple[i];
			out.totalLevel[i] = totalLevel[i];
			out.keyScale[i] = keyScale[i];
			out.attack[i] = attack[i];
			out.decay[i] = decay[i];
			out.sustain[i] = sustain[i];
			out.sustainLevel[i] = sustainLevel[i];
			out.release[i] = release[i];
			out.ssg[i] = ssg[i];
			out.tremolo[i] = tremolo[i];
		}

		return out;
	}
}
