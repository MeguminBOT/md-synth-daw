package mdd.play;

import mdd.host.Atomic;
import mdd.song.Instrument;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;

/**
	Play, stop, seek, loop and audition, and the position everything else reads.

	It owns the sequencer and the stream the render thread consumes, so a caller moving
	the playhead and a render reading it are kept apart by one mutex rather than by
	hoping. Auditioning a note goes through here too, and so through the same stream,
	which is what stops a panel writing to a chip on its own.
**/
@:unreflective
final class Transport {
	/**
		The song being played.
	**/
	public final song:Song;

	/**
		What turns that song into register writes.
	**/
	public final sequencer:Sequencer;

	/**
		Where those writes are put for the render to read.
	**/
	public final stream:Stream;

	/**
		Whether the transport is running.
	**/
	public var playing(get, never):Bool;

	/**
		Where the playhead is, in output samples.
	**/
	public var position(default, null):Int = 0;

	final running:Atomic = new Atomic(0);
	final hushing:Atomic = new Atomic(0);

	/**
		Whether playback wraps at `loopTo`.
	**/
	public var looping:Bool = false;

	/**
		How many seconds to keep rendering past the end of the song, so a release is heard.
	**/
	public var tail:Int = 1;

	/**
		The tick the loop returns to.
	**/
	public var loopFrom:Int = 0;

	/**
		The tick the loop wraps at.
	**/
	public var loopTo:Int = 0;

	/**
		How many frames have been asked for.
	**/
	public var served(default, null):Int = 0;

	/**
		How many times the loop has wrapped.
	**/
	public var wrapped(default, null):Int = 0;

	/**
		How many spans have been sequenced.
	**/
	public var stepped(default, null):Int = 0;

	/**
		How many auditions are waiting to be woven in.
	**/
	public var entering(default, null):Int = 0;

	final gate:sys.thread.Mutex = new sys.thread.Mutex();

	/**
		How long an audition sounds for, in blocks, when it is not held.
	**/
	static inline final AUDITION_BLOCKS = 90;

	/**
		The velocity an audition uses when none is given.
	**/
	static inline final AUDITION_VELOCITY = 100;

	var heardPart:Int = -1;
	var heardNote:Int = 0;
	var heardLeft:Int = 0;
	var heardFresh:Bool = false;
	var heardHeld:Bool = false;
	var heardVelocity:Int = AUDITION_VELOCITY;
	var heardCarry:Float = 0;
	var heardIndex:Int = 0;
	var heardCents:Int = 0;
	var heardBent:Bool = false;
	var heardBefore:Int = -1;
	var priming:Bool = false;
	final sounded:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(Part.COUNT);

	/**
		Whether the metronome clicks on every beat while the song plays. A count in clicks either
		way.
	**/
	public var clicking:Bool = false;

	/**
		How loud the metronome and the count in click, nought to one.
	**/
	public var clickLevel:Float = 0.7;

	/**
		The most clicks one span can hold.
	**/
	static inline final CLICKS = 4;

	/**
		How many clicks fall in the span `advance` last sequenced.
	**/
	public var clicks(default, null):Int = 0;

	/**
		Where each click falls, in output frames from the start of that span.
	**/
	public final clickAt:haxe.ds.Vector<Int> = new haxe.ds.Vector<Int>(CLICKS);

	/**
		Whether each click is the first beat of a bar.
	**/
	public final clickFirst:haxe.ds.Vector<Bool> = new haxe.ds.Vector<Bool>(CLICKS);

	/**
		How much of the count in is still to go, in samples. The playhead waits while it runs.
	**/
	public var counting(default, null):Int = 0;

	var countLength:Int = 0;

	/**
		How many beats the count in lasts.
	**/
	public var countBeats(default, null):Int = 0;

	/**
		How many of them make a bar.
	**/
	public var countBar(default, null):Int = 1;

	var countNext:Int = 0;

	var carried:Int = 0;

	/**
		Builds a transport over a song.

		@param song The song to play.
		@param capacity How many register writes the stream may hold per span.
	**/
	public function new(song:Song, capacity:Int = 8192) {
		this.song = song;
		sequencer = new Sequencer(song);
		sequencer.quiets();
		sequencer.readies();
		for (index in 0...Part.COUNT) sounded[index] = true;
		stream = new Stream(capacity);
	}

	/**
		Whether playback smooths the edges the parts would otherwise click on. An export has a
		setting of its own, because what is monitored and what is written are chosen separately,
		the same way the output stage is.
	**/
	public var declick(get, set):Bool;

	function get_declick():Bool {
		return sequencer.declick;
	}

	function set_declick(value:Bool):Bool {
		sequencer.declick = value;
		return value;
	}

	/**
		@return Whether the transport is running.
	**/
	function get_playing():Bool {
		return running.load() == 1;
	}

	/**
		Starts playing from wherever the playhead is, after a count in where one is asked for. The
		count in clicks every beat of its bars at the tempo the playhead is at, and the song starts
		on the beat after the last.

		@param bars How many bars to count in, or nought to start at once.
	**/
	public function play(bars:Int = 0):Void {
		gate.acquire();

		counting = 0;

		if (bars > 0) {
			final pattern = sequencer.alone >= 0 ? song.patternAt(sequencer.alone) : null;
			final meter = song.meterOf(pattern);
			final tempo = song.tempo;
			final tick = tempo.tickAt(position);

			countLength = tempo.samplesAt(tick + meter.bar(tempo.ppqn) * bars) - tempo.samplesAt(tick);
			countBar = meter.beats;
			countBeats = meter.beats * bars;
			countNext = 0;
			counting = countLength;
		}

		gate.release();
		running.store(1);
	}

	/**
		Stops, and asks for every part to be silenced on the next span.
	**/
	public function stop():Void {
		running.store(0);
		hushing.store(1);
		counting = 0;
	}

	/**
		Moves the playhead, forgetting what the chips are holding so the next span writes every register again.

		@param samples Where to move it to, in output samples.
	**/
	public function seek(samples:Int):Void {
		position = samples < 0 ? 0 : samples;
		hushing.store(1);
	}

	/**
		Sets the loop and turns looping on. A range that is not a range turns it off.

		@param fromTick The tick to return to.
		@param toTick The tick to wrap at.
	**/
	public function loop(fromTick:Int, toTick:Int):Void {
		loopFrom = fromTick < 0 ? 0 : fromTick;
		loopTo = toTick;
		looping = toTick > loopFrom;
	}

	/**
		Takes the lock the render thread also takes, so a caller can change the song
		safely. Every `holds` needs a `frees`.
	**/
	public inline function holds():Void {
		gate.acquire();
	}

	/**
		Gives that lock back, and has the next span look again at every note still sounding, since
		the song may have changed while it was held.
	**/
	public inline function frees():Void {
		sequencer.edited = true;
		gate.release();
	}

	/**
		Sequences the next span into `stream`. Called from the render thread.

		@param frames How many output frames the span covers.
		@param rate The output rate in hertz.
		@return How many register writes the span produced.
	**/
	public function advance(frames:Int, rate:Int):Int {
		stream.clear();
		entering = carried;
		clicks = 0;

		watched();

		if (hushing.exchange(0) == 1) {
			heardPart = -1;
			heardBefore = -1;
			stream.reset(position);
			sequencer.quiets();
			priming = true;
		}

		if (running.load() == 0) {
			stepped = 0;

			gate.acquire();
			auditioned(position, Std.int(frames * Tempo.TICKS / rate));
			gate.release();

			return position;
		}

		final total = frames * Tempo.TICKS + carried;
		final step = Std.int(total / rate);
		carried = total - step * rate;

		gate.acquire();

		var lead = 0;

		if (counting > 0) {
			counted(step, rate);

			if (counting >= step) {
				counting -= step;
				auditioned(position, step);
				gate.release();

				stepped = 0;
				return position;
			}

			lead = counting;
			counting = 0;
		}

		final from = position;
		var until = from + step - lead;

		if (priming) {
			priming = false;
			sequencer.prime(stream, from);
		}

		final ranged = looping && loopTo > loopFrom;
		final ending = ranged ? loopTo : ends();
		final bounded = ending > from;

		if (bounded && until > ending) until = ending;

		sequencer.emit(stream, from, until);
		auditioned(from, until - from);
		if (clicking) beaten(from, until, lead, rate);

		gate.release();
		served++;
		stepped = until - from;

		if (bounded && until >= ending) {
			if (looping) {
				position = ranged ? loopFrom : 0;
				priming = true;
				wrapped++;
			} else {
				position = 0;
				running.store(0);
				hushing.store(1);
			}
		} else {
			position = until;
		}

		return from - lead;
	}

	/**
		@return Which beat of the count in the transport has reached, counted from nought, or -1
			where no count in is running.
	**/
	public function countBeat():Int {
		final left = counting;
		final length = countLength;

		if (left <= 0 || length <= 0 || countBeats <= 0) return -1;

		final at = Std.int((length - left) / (length / countBeats));
		return at >= countBeats ? countBeats - 1 : at;
	}

	/**
		Marks the beats of the count in that fall in the next `step` samples of it.

		@param step How many samples the span covers.
		@param rate The output rate in hertz.
	**/
	function counted(step:Int, rate:Int):Void {
		final elapsed = countLength - counting;

		while (countNext < countBeats && clicks < CLICKS) {
			final offset = Std.int(countNext * (countLength / countBeats) + 0.5);
			if (offset >= elapsed + step) break;

			if (offset >= elapsed) {
				clickAt[clicks] = Std.int((offset - elapsed) * rate / Tempo.TICKS);
				clickFirst[clicks] = countNext % countBar == 0;
				clicks++;
			}

			countNext++;
		}
	}

	/**
		Marks the beats of the song that fall in a span, by the signature of whatever is playing:
		the pattern on its own, or the piece.

		@param from The first sample of the span.
		@param until The sample after its last.
		@param lead How many samples of count in come before `from` in the same block.
		@param rate The output rate in hertz.
	**/
	function beaten(from:Int, until:Int, lead:Int, rate:Int):Void {
		final pattern = sequencer.alone >= 0 ? song.patternAt(sequencer.alone) : null;
		final meter = song.meterOf(pattern);
		final tempo = song.tempo;
		final beat = meter.beat(tempo.ppqn);
		final bar = meter.bar(tempo.ppqn);

		var at = Std.int(tempo.tickAt(from) / beat) * beat;
		if (at >= beat) at -= beat;

		while (clicks < CLICKS) {
			final sample = tempo.samplesAt(at);
			if (sample >= until) break;

			if (sample >= from) {
				clickAt[clicks] = Std.int((sample - from + lead) * rate / Tempo.TICKS);
				clickFirst[clicks] = at % bar == 0;
				clicks++;
			}

			at += beat;
		}
	}

	/**
		@return The sample the song finishes at, including the tail.
	**/
	function ends():Int {
		final alone = sequencer.alone;

		if (alone >= 0) {
			final pattern = song.patternAt(alone);
			return pattern == null ? 0 : song.tempo.samplesAt(pattern.length);
		}

		final last = song.ends();
		if (last <= 0) return 0;

		return song.tempo.samplesAt(last + song.tempo.ppqn * tail);
	}

	/**
		Sounds one note on one part, through the same stream playback uses.

		@param part Which part to sound it on.
		@param note The MIDI note number.
		@param velocity The velocity, 0 to 127.
		@param held Whether it sounds until `releases` rather than for a fixed length.
	**/
	public function auditions(part:Part, note:Int, velocity:Int = AUDITION_VELOCITY,
			held:Bool = false):Void {
		gate.acquire();

		if (heardPart >= 0 && heardPart != part.index()) heardBefore = heardPart;

		heardPart = part.index();
		heardNote = note;
		heardLeft = AUDITION_BLOCKS;
		heardFresh = true;
		heardHeld = held;
		heardVelocity = velocity < 1 ? 1 : (velocity > 127 ? 127 : velocity);

		gate.release();
	}

	/**
		Bends whatever is being auditioned, and every audition after it until it is bent back.

		@param cents How far, in hundredths of a semitone.
	**/
	public function bends(cents:Int):Void {
		gate.acquire();

		if (heardCents != cents) {
			heardCents = cents;
			heardBent = true;
		}

		gate.release();
	}

	/**
		Ends a held audition.

		@param part The part it was sounding on.
	**/
	public function releases(part:Part):Void {
		gate.acquire();

		if (heardPart == part.index() && heardHeld) {
			heardHeld = false;
			heardLeft = 1;
		}

		gate.release();
	}

	/**
		What pressing a key should sound.

		A key on the converter sounds the recording rooted there, whether or not the
		converter is being read as a kit. A recording sits on a key of its own and
		the editor draws it on that row, so pressing the row has to sound the thing
		drawn on it: a keyboard that answers the same sound whichever key is pressed
		is telling the reader nothing.

		Every other part sounds whatever it holds, because a key there is a pitch
		rather than a choice of sound.

		@return The instrument to sound, or null where the converter is read as a kit
			and has nothing rooted at that key, since a key with no drum on it makes
			no sound.
	**/
	function heard():Null<Instrument> {
		final part:Part = heardPart;
		final rooted = part.sampled() ? song.drumAt(heardNote) : -1;

		if (song.drums) return rooted < 0 ? null : song.instrumentAt(rooted);
		if (rooted >= 0) return song.instrumentAt(rooted);

		return song.instrumentAt(song.rack[heardPart]);
	}

	/**
		Weaves a waiting audition into the span being sequenced.

		@param at The first sample of the span.
		@param span How many samples it covers.
	**/
	function auditioned(at:Int, span:Int):Void {
		if (heardBefore >= 0) {
			stream.silence(at, heardBefore);
			heardBefore = -1;
		}

		if (heardPart < 0) return;

		final part:Part = heardPart;

		if (part.sampled()) {
			sampled(at, span < 1 ? 1 : span);
			return;
		}

		if (heardFresh) {
			heardFresh = false;

			final instrument = heard();
			final velocity = Velocity.scaled(heardVelocity, song.volume[heardPart]);

			if (part.fm()) {
				if (instrument != null && instrument.patch != null) {
					stream.patch(at, part, instrument.patch, velocity);
					stream.sides(at, part, ((song.pan[heardPart] & 3) << 6)
						| ((instrument.patch.ams & 3) << 4) | (instrument.patch.pms & 7));
				}

				tunes(at, part, Stream.wordAt(part, heardNote, heardCents));
				stream.keyOn(at, part);
			} else if (part.square()) {
				stream.period(at, part, Stream.wordAt(part, heardNote, heardCents));
				stream.loudness(at, part, instrument == null ? null : instrument.envelope,
					velocity, 0);
			} else if (part.noise()) {
				if (instrument != null && instrument.envelope != null) {
					stream.noise(at, instrument.envelope.noise, false);
				}

				if (stream.tunedNoise()) stream.lends(at, heardNote);

				stream.loudness(at, part, instrument == null ? null : instrument.envelope,
					velocity, 0);
			}

			heardBent = false;
		} else if (heardBent) {
			heardBent = false;

			if (part.fm()) tunes(at, part, Stream.wordAt(part, heardNote, heardCents));
			if (part.square()) stream.period(at, part, Stream.wordAt(part, heardNote, heardCents));
		}

		if (heardHeld) return;

		heardLeft--;
		if (heardLeft > 0) return;

		stream.silence(at, part);
		heardPart = -1;
	}

	/**
		Tunes an FM channel for an audition. Channel three playing a note on each operator has every
		operator tuned to the note, so it sounds as one note does anywhere else.

		@param at When the writes happen.
		@param part Which channel.
		@param word Block and frequency packed as `Stream.wordOf` packs them.
	**/
	function tunes(at:Int, part:Part, word:Int):Void {
		stream.frequency(at, part, word);

		if (part != Part.Fm3 || !song.separated()) return;

		for (slot in 0...3) stream.operatorWord(at, slot, word);
	}

	/**
		Writes the sample channel bytes that fall inside the span.

		@param at The first sample of the span.
		@param span How many samples it covers.
	**/
	function sampled(at:Int, span:Int):Void {
		final instrument = heard();
		final sample = instrument == null ? null : song.sampleAt(instrument.sample);

		if (sample == null || sample.length() == 0) {
			heardPart = -1;
			return;
		}

		if (heardFresh) {
			heardFresh = false;
			heardCarry = 0;
			heardIndex = 0;

			stream.sampling(at, true);
		}

		final rate = sample.rate < 1 ? 1 : sample.rate;
		final step = Tempo.TICKS / rate;

		var when = heardCarry;

		while (heardIndex < sample.length() && when < span) {
			stream.byte(at + Math.round(when), sample.bytes[heardIndex]);
			heardIndex++;
			when += step;
		}

		heardCarry = when - span;
		if (heardCarry < 0) heardCarry = 0;

		if (heardIndex < sample.length()) return;

		stream.sampling(at + span - 1, false);
		heardPart = -1;
	}

	/**
		Notices parts that stopped sounding and lets the audition state go with them.
	**/
	function watched():Void {
		for (index in 0...Part.COUNT) {
			final part:Part = index;
			final now = song.audible(part);

			if (now == sounded[index]) continue;

			sounded[index] = now;
			if (now) continue;

			stream.silence(position, part);
		}
	}

	/**
		Back to the start, silencing everything on the way.
	**/
	public function rewind():Void {
		stream.forget();
		position = 0;
		carried = 0;
		entering = 0;
		stepped = 0;
		served = 0;
		wrapped = 0;
	}

	/**
		Silences every part without moving the playhead.
	**/
	public function silence():Void {
		hushing.store(1);
	}

	/**
		@return Where the playhead is, in seconds.
	**/
	public inline function seconds():Float {
		return position / Tempo.TICKS;
	}

	/**
		@return Where the playhead is, in ticks.
	**/
	public inline function tick():Int {
		return song.tempo.tickAt(position);
	}
}
