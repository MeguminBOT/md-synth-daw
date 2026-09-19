package mdd.gate;

import haxe.ds.Vector;
import mdd.format.Chunks;
import mdd.format.Project;
import mdd.play.Polyphony;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.play.Voices;
import mdd.song.edit.AddClip;
import mdd.song.edit.AddNote;
import mdd.song.Clip;
import mdd.song.edit.History;
import mdd.song.Instrument;
import mdd.song.edit.MoveNote;
import mdd.song.Note;
import mdd.song.Part;
import mdd.song.Pattern;
import mdd.song.Sample;
import mdd.song.edit.SetTempo;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.song.Track;

@:unreflective
class StreamCheck {
	static var failed:Int = 0;
	static var ran:Int = 0;

	public static function run(args:Array<String>):Int {
		failed = 0;
		ran = 0;

		Sys.println("  stream");

		timing();
		polyphony();
		identical();
		commands();
		faces();
		chunks();
		sounded();
		sought(args);
		raced();
		hushed();
		restruck();
		legato();
		grown();
		survived();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");

		if (failed > 0) {
			Sys.println("    failed");
			return 1;
		}

		Sys.println("    passed");
		return 0;
	}

	static function held(stream:Stream, until:Int):haxe.ds.Vector<Int> {
		final shadow = new haxe.ds.Vector<Int>(512 + 8);
		for (index in 0...shadow.length) shadow[index] = -1;

		var half = 0;
		var address = -1;
		var latched = 0;

		for (index in 0...stream.count) {
			if (stream.tickAt(index) > until) break;

			final port = stream.portAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) != Stream.YM) {
				if ((value & 0x80) != 0) {
					latched = (value >> 4) & 7;
					shadow[512 + latched] = (shadow[512 + latched] & 0x3F0) | (value & 0x0F);
				} else shadow[512 + latched] = (value & 0x3F) << 4
					| (shadow[512 + latched] & 0x0F);

				continue;
			}

			if ((port & 1) == 0) {
				half = (port >> 1) & 1;
				address = value;
				continue;
			}

			if (address < 0 || address == 0x28 || address == 0x2A) continue;

			shadow[(half << 8) | address] = value & 0xFF;
		}

		return shadow;
	}

	static function sought(args:Array<String>):Void {
		final where = Gate.root + "/vendor/vgm";
		if (!sys.FileSystem.isDirectory(where)) return;

		final name = Fixtures.found("Green Hill");

		if (name == "") return;

		final source = new Stream(1 << 22);
		final vgm = mdd.format.Vgm.read(sys.io.File.getBytes(name), source);
		final song = mdd.format.Transcription.of(source, vgm.rate, name).song;

		final into = Tempo.TICKS * 8;

		final whole = new Stream(1 << 21);
		new Sequencer(song).spanned(whole, 0, into);

		final after = new Stream(1 << 20);

		after.reset(into);
		if (args.indexOf("--raw") < 0) new Sequencer(song).prime(after, into);

		final one = held(whole, into);
		final two = held(after, into);

		var apart = 0;
		var first = -1;

		for (index in 0...one.length) {
			if (one[index] == two[index]) continue;
			if (one[index] < 0 || two[index] < 0) continue;

			apart++;
			if (first < 0) first = index;

			Sys.println("      " + StringTools.hex(index, 3) + "  playing "
				+ one[index] + "  seeking " + two[index]);
		}

		final fresh = new Stream(1 << 18);

		fresh.reset(0);
		new Sequencer(song).prime(fresh, 0);

		var latched = 0;
		var loud = 0;
		var keys = 0;

		for (index in 0...fresh.count) {
			final value = fresh.valueAt(index);

			if (fresh.kindAt(index) != Stream.YM) {
				if ((value & 0x80) == 0) continue;

				latched = (value >> 4) & 7;
				if ((latched & 1) != 0 && (value & 0x0F) != 0x0F) loud++;

				continue;
			}

			if ((fresh.portAt(index) & 1) == 0) {
				latched = value == 0x28 ? 1 : 0;
				continue;
			}

			if (latched == 1 && (value & 0xF0) != 0) keys++;
		}

		says("starting at the top sounds nothing", loud == 0 && keys == 0,
			fresh.count + " writes prime the chip at the first tick, " + loud
			+ " of them a square away from silence and " + keys + " a key on");

		says("a seek leaves the chip where playing there would", apart == 0,
			apart + " of the registers the song sets differ from what playing to eight"
			+ " seconds would have left" + (first < 0 ? "" : ", the first being "
			+ StringTools.hex(first, 3)));
	}

	/**
		A stream that grows rather than dropping, and one that still drops.

		Reserving the worst case for an export is half a gigabyte for a quarter of an hour
		and twenty times what a busy piece uses, so an offline stream starts at a guess and
		takes more where the guess was low. What that must not do is lose or reorder a
		single write, which is what is read back here.

		Nothing the render thread touches grows, and the flag being off by default is what
		holds that: a reader on another thread would be left holding the buffer that was
		replaced.
	**/
	static function grown():Void {
		final many = 5000;

		final wide = new Stream(16);
		wide.grows = true;

		for (index in 0...many) wide.raw(index, Stream.YM, index & 3, index & 0xFF);

		var wrong = -1;

		for (index in 0...wide.count) {
			if (wide.tickAt(index) == index && wide.kindAt(index) == Stream.YM
				&& wide.portAt(index) == (index & 3)
				&& wide.valueAt(index) == (index & 0xFF)) continue;

			wrong = index;
			break;
		}

		says("a stream grows into what it needs",
			wide.count == many && wide.dropped == 0 && wrong < 0,
			many + " writes into room for 16, grown to " + wide.capacity
			+ ", none dropped and none out of order");

		final tight = new Stream(16);

		for (index in 0...many) tight.raw(index, Stream.YM, index & 3, index & 0xFF);

		says("and one that may not still drops",
			tight.count == 16 && tight.dropped == many - 16 && tight.capacity == 16,
			tight.count + " writes kept and " + tight.dropped
			+ " dropped, which is what the render thread reads");

		final asked = Stream.reserved(mdd.song.Tempo.TICKS * 60);

		says("and an export starts on a guess",
			asked.grows && asked.capacity == Stream.roomFor(mdd.song.Tempo.TICKS * 60),
			"a minute reserves " + asked.capacity + " writes, "
			+ Math.round(asked.capacity * 16 / 1048576) + " MB, rather than the worst case");
	}

	/**
		A value two threads share is still the value after the collector has run.

		The queue's head and tail, the transport's state and the updater's are all kept this
		way. `haxe.atomic.AtomicInt` keeps its value in an array only a pointer refers to, which
		the collector does not follow, and the fixture below changed one of 256 of those from
		106 to 2 on every run. What is measured here is the replacement, through the same
		churn.
	**/
	static function survived():Void {
		final held:Array<mdd.host.Atomic> = [];

		for (index in 0...256) held.push(new mdd.host.Atomic(index * 7 + 1));

		var churned = 0;

		for (round in 0...40) {
			final junk:Array<Array<Int>> = [];

			for (index in 0...20000) junk.push([0x5A5A, 0x5A5A]);

			churned += junk.length;
			cpp.vm.Gc.run(round % 4 == 0);
		}

		var wrong = 0;

		for (index in 0...held.length) if (held[index].load() != index * 7 + 1) wrong++;

		final swapped = held[0].exchange(9);
		final stored = held[0].load();

		says("shared values survive collection", wrong == 0 && swapped == 1 && stored == 9,
			wrong + " of " + held.length + " changed after " + churned
			+ " allocations and 40 collections, and an exchange handed back " + swapped);
	}

	/**
		Notes laid end to end on an FM channel each attack. The chip copies its key register once a
		slot and holds a write for two slots before it lands, and a write arriving while one is held
		lands the held one at once. A key off and a key on on one sample are then an edge or not
		depending on where the channel's own slot falls: the first channel still attacked, and a
		run of back to back notes on any of the other five played its first note and then silence.
		The sequencer does not declick here, because a fade keys the channel off well before the key
		on and would hide the one sample this measures.
	**/
	static function restruck():Void {
		var gapped = 0;
		var joined = 0;
		var loudest = 0.0;
		var quietest = 1.0;
		final lost:Array<String> = [];

		for (channel in 0...6) {
			final part:Part = channel;
			final song = new Song("restruck", 96, 120);
			final plucked = new Instrument("plucked", part);
			final patch = plucked.patch;

			if (patch != null) {
				patch.algorithm = 7;

				for (slot in 0...4) {
					patch.totalLevel[slot] = slot == 3 ? 0 : 127;
					patch.decay[slot] = 24;
					patch.sustain[slot] = 24;
					patch.sustainLevel[slot] = 15;
				}
			}

			song.instrument(plucked);
			song.rack[part.index()] = song.instruments.length - 1;

			final beat = song.tempo.ppqn;
			final pattern = song.add(new Pattern("pattern 1", beat * 4));

			for (index in 0...4) pattern.lane(part).add(new Note(index * beat, beat, 60, 127));

			song.track(new Track("one")).add(new Clip(0, 0, pattern.length));

			final stream = new Stream(1 << 16);
			final sequencer = new Sequencer(song);

			sequencer.declick = false;
			sequencer.spanned(stream, 0, song.tempo.samplesAt(pattern.length));

			final struck = attacks(song, stream, beat);
			final touched = attacks(song, touching(stream), beat);

			gapped += Std.int(struck[0]);
			joined += Std.int(touched[0]);

			if (struck[1] > loudest) loudest = struck[1];
			if (struck[1] < quietest) quietest = struck[1];
			if (touched[0] < 3) lost.push(part.name());
		}

		says("back to back notes each attack", gapped == 18 && joined < 18,
			gapped + " of the 18 notes that follow another with no gap attack across the six FM"
			+ " channels, peaking between " + Math.round(quietest * 1000) / 1000 + " and "
			+ Math.round(loudest * 1000) / 1000 + "; with each key off moved onto its key on's"
			+ " sample, " + joined + " do" + (lost.length == 0 ? "" : ", losing notes on "
			+ lost.join(", ")));
	}

	/**
		@param stream A sequenced stream.
		@return A copy with every key off moved one sample later, onto the key on after it.
	**/
	/**
		A tied note changes the pitch of the note before it without striking it again: one key on
		and one key off for a whole tied line on an FM channel, and on a square no silence at a tie
		and an envelope that carries on rather than starting over.
	**/
	static function legato():Void {
		final song = new Song("legato", 96, 120);
		final beat = song.tempo.ppqn;
		final pattern = song.add(new Pattern("pattern 1", beat * 4));
		final decaying = new Instrument("decaying", Part.Psg1);

		if (decaying.envelope != null) {
			for (step in 0...8) decaying.envelope.steps.push(step);
			decaying.envelope.speed = 4;
		}

		song.instrument(decaying);
		final square = song.instruments.length - 1;

		for (index in 0...3) {
			final fm = new Note(index * beat, beat, 60 + index * 4, 127);
			final held = new Note(index * beat, beat, 60 + index * 4, 127, square);

			fm.tied = index > 0;
			held.tied = index > 0;

			pattern.lane(Part.Fm1).add(fm);
			pattern.lane(Part.Psg1).add(held);
		}

		song.track(new Track("one")).add(new Clip(0, 0, pattern.length));

		final stream = new Stream(1 << 16);
		new Sequencer(song).spanned(stream, 0, song.tempo.samplesAt(pattern.length));

		final ended = song.tempo.samplesAt(beat * 3);

		var address = 0;
		var ons = 0;
		var offs = 0;
		var early = 0;
		var latched = 0;
		var last = -1;
		var backwards = 0;
		var silenced = 0;
		var tones = 0;

		for (index in 0...stream.count) {
			final tick = stream.tickAt(index);
			final value = stream.valueAt(index);

			if (stream.kindAt(index) == Stream.PSG) {
				if ((value & 0x80) == 0) continue;

				latched = (value >> 4) & 7;

				if (latched == 0) tones++;
				if (latched != 1) continue;

				final level = value & 0x0F;

				if (level == 15 && tick < ended) silenced++;
				if (level < 15 && last >= 0 && level < last) backwards++;
				if (level < 15) last = level;

				continue;
			}

			if (stream.kindAt(index) != Stream.YM) continue;

			if ((stream.portAt(index) & 1) == 0) {
				address = value;
				continue;
			}

			if (address != 0x28 || (value & 7) != 0) continue;

			if ((value & 0xF0) != 0) ons++;
			else {
				offs++;
				if (tick < ended - 1) early++;
			}
		}

		says("a tied FM line keys on once", ons == 1 && offs == 1 && early == 0,
			ons + " key ons and " + offs + " key offs on FM1 for three tied notes, " + early
			+ " of the key offs before the line ends");

		says("and a tied square does not start over", silenced == 0 && backwards == 0 && tones >= 3,
			silenced + " silences before the line ends, " + backwards + " envelope steps that go back"
			+ " toward the start, and " + tones + " tone writes for three pitches");
	}

	static function touching(stream:Stream):Stream {
		final out = new Stream(stream.count + 16);
		var index = 0;

		while (index < stream.count) {
			final paired = stream.kindAt(index) == Stream.YM && (stream.portAt(index) & 1) == 0
				&& index + 1 < stream.count;
			final off = paired && stream.valueAt(index) == 0x28 && (stream.valueAt(index + 1) & 0xF0) == 0;
			final many = paired ? 2 : 1;

			for (at in index...index + many) {
				out.raw(stream.tickAt(at) + (off ? 1 : 0), stream.kindAt(at), stream.portAt(at),
					stream.valueAt(at));
			}

			index += many;
		}

		return out;
	}

	/**
		@param song The song the stream was sequenced from, four notes a beat apart.
		@param stream What to render.
		@param beat How many ticks a beat is.
		@return How many of the last three notes attack, the loudest of them in the 20 ms after it
			keys on, and the loudest in the 20 ms before.
	**/
	static function attacks(song:Song, stream:Stream, beat:Int):Array<Float> {
		final span = song.tempo.samplesAt(beat * 4);
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);
		final loud = new Vector<Float>(span);
		var done = 0;

		while (done < span) {
			final many = render.serve(stream, done, mdd.play.Render.BLOCK);
			if (many <= 0) break;

			for (index in 0...many) {
				if (done + index >= span) break;

				final value = render.block[index * 2];
				loud[done + index] = value < 0 ? -value : value;
			}

			done += many;
		}

		final window = 882;
		var attacked = 0;
		var before = 0.0;
		var after = 0.0;

		for (index in 1...4) {
			final start = song.tempo.samplesAt(index * beat);
			var quiet = 0.0;
			var struck = 0.0;

			for (at in start - window...start) if (loud[at] > quiet) quiet = loud[at];
			for (at in start...start + window) if (loud[at] > struck) struck = loud[at];

			if (struck > 0.01 && struck > quiet * 4) attacked++;
			if (quiet > before) before = quiet;
			if (struck > after) after = struck;
		}

		return [attacked, after, before];
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;
		Sys.println("    " + StringTools.rpad(name, " ", 34) + said + (ok ? "" : "   FAILED"));
	}

	static function round(value:Float, places:Int):Float {
		final scale = Math.pow(10, places);
		return Math.round(value * scale) / scale;
	}

	public static function written():Song {
		final song = new Song("a measured song", 96, 120);

		final lead = song.instrument(new Instrument("lead", Part.Fm1));
		lead.patch.algorithm = 2;
		lead.patch.feedback = 5;

		for (slot in 0...4) {
			lead.patch.detune[slot] = slot;
			lead.patch.multiple[slot] = 1 + slot;
			lead.patch.totalLevel[slot] = slot == 3 ? 8 : 32;
			lead.patch.attack[slot] = 28;
			lead.patch.decay[slot] = 12;
			lead.patch.sustain[slot] = 4;
			lead.patch.sustainLevel[slot] = 3;
			lead.patch.release[slot] = 7;
			lead.patch.tremolo[slot] = slot == 1;
		}

		final square = song.instrument(new Instrument("square", Part.Psg1));
		square.envelope.steps.push(0);
		square.envelope.steps.push(1);
		square.envelope.steps.push(3);
		square.envelope.steps.push(6);
		square.envelope.loop = 2;
		square.envelope.speed = 1;

		final hiss = song.instrument(new Instrument("hiss", Part.Noise));
		hiss.envelope.steps.push(0);
		hiss.envelope.steps.push(4);
		hiss.envelope.noise = 6;

		final kit = song.instrument(new Instrument("kit", Part.Dac));
		final sample = song.sample(new Sample("snare", 8000, 60));

		final bytes = new Vector<Int>(240);
		var seed = 0x1234;

		for (i in 0...bytes.length) {
			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			bytes[i] = 0x80 + ((seed >> 7) % 60) - 30;
		}

		sample.hold(bytes);
		kit.sample = 0;

		for (index in 0...Part.COUNT) {
			final part:Part = index;
			song.rack[index] = part.fm() ? 0 : (part.square() ? 1 : (part.noise() ? 2 : 3));
		}

		final pattern = song.add(new Pattern("verse", 384));

		for (index in 0...6) {
			final part:Part = index;
			pattern.lane(part).add(new Note(index * 24, 72, 48 + index * 5, 90 + index * 4));
			pattern.lane(part).add(new Note(192 + index * 12, 48, 60 + index * 3, 70));
		}

		pattern.lane(Part.Fm1).add(new Note(60, 96, 67, 110));

		for (index in 6...9) {
			final part:Part = index;
			pattern.lane(part).add(new Note(index * 16, 96, 55 + index, 100));
		}

		pattern.lane(Part.Noise).add(new Note(0, 48, 60, 120));
		pattern.lane(Part.Dac).add(new Note(96, 48, 60, 127));
		pattern.lane(Part.Dac).add(new Note(288, 48, 60, 100));

		final second = song.add(new Pattern("chorus", 384));
		for (index in 0...4) {
			final part:Part = index;
			second.lane(part).add(new Note(index * 48, 144, 55 + index * 4, 100));
		}

		final track = song.track(new Track("one"));
		track.add(new Clip(0, 0, 384));
		track.add(new Clip(1, 384, 384, 3));

		final other = song.track(new Track("two"));
		other.add(new Clip(0, 192, 384, -5));

		song.tempo.set(288, 168.5);
		return song;
	}

	static function timing():Void {
		final tempo = new Tempo(96, 120);

		final quarter = tempo.samplesAt(96);
		final bar = tempo.samplesAt(384);

		says("a beat is a beat", quarter == 22050 && bar == 88200,
			"120 bpm puts a quarter at " + quarter + " samples and a bar at " + bar);

		tempo.set(384, 240);
		final later = tempo.samplesAt(384 + 96);

		says("a tempo change lands", later == 88200 + 11025,
			"the beat after the change is " + (later - bar) + " samples, half the one before");

		var walked = true;
		for (tick in 0...600) {
			if (tempo.tickAt(tempo.samplesAt(tick)) != tick) walked = false;
		}

		says("ticks round trip", walked, "600 ticks convert to samples and back unchanged");

		var rising = true;
		var last = -1;
		for (tick in 0...600) {
			final now = tempo.samplesAt(tick);
			if (now < last) rising = false;
			last = now;
		}

		says("time only moves on", rising, "no tick maps behind the one before it");
	}

	static function polyphony():Void {
		final pattern = new Pattern("overlap", 384);
		final lane = pattern.lane(Part.Fm1);

		lane.add(new Note(0, 96, 60, 100));
		lane.add(new Note(48, 96, 64, 100));
		lane.add(new Note(192, 48, 67, 100));

		final voices = new Voices();

		voices.policy = Polyphony.Strict;
		voices.resolve(lane);
		final strict = voices.count;
		final refused = voices.refused;

		voices.policy = Polyphony.Stealing;
		voices.resolve(lane);
		final stealing = voices.count;
		final cut = voices.count > 0 ? voices.endAt(0) : -1;

		voices.policy = Polyphony.Arpeggio;
		voices.arpeggio = 6;
		voices.resolve(lane);
		final arpeggio = voices.count;

		var overlapping = false;
		for (i in 1...voices.count) {
			if (voices.startAt(i) < voices.endAt(i - 1)) overlapping = true;
		}

		says("strict refuses", strict == 2 && refused == 1,
			strict + " of 3 notes sound, " + refused + " refused for overlapping");

		says("stealing cuts", stealing == 3 && cut == 48,
			"all 3 sound and the first is cut at " + cut + " where the second starts");

		says("arpeggio alternates", arpeggio > 3 && !overlapping,
			arpeggio + " slices, none overlapping");
	}

	static function poured(song:Song, span:Int, block:Int, into:Stream):Void {
		final sequencer = new Sequencer(song);
		var at = 0;

		while (at < span) {
			var until = at + block;
			if (until > span) until = span;

			sequencer.emit(into, at, until);
			at = until;
		}
	}

	static function alike(one:Stream, two:Stream):Int {
		if (one.count != two.count) return -1;

		for (i in 0...one.count) {
			if (one.tickAt(i) != two.tickAt(i)) return i;
			if (one.kindAt(i) != two.kindAt(i)) return i;
			if (one.portAt(i) != two.portAt(i)) return i;
			if (one.valueAt(i) != two.valueAt(i)) return i;
		}

		return -2;
	}

	static function keyed(stream:Stream, on:Bool, part:Part):Int {
		var many = 0;
		var index = 0;

		while (index + 1 < stream.count) {
			if (stream.kindAt(index) == Stream.YM && stream.portAt(index) == 0
				&& stream.valueAt(index) == 0x28 && stream.portAt(index + 1) == 1) {
				final byte = stream.valueAt(index + 1);

				if (Stream.keyPart(byte) == part.index() && ((byte & 0xF0) != 0) == on) many++;
			}

			index++;
		}

		return many;
	}

	static function holding():Song {
		final song = new Song("hushed", 96, 120);
		final bar = song.tempo.ppqn * 4;

		for (index in 0...Part.COUNT) {
			final part:Part = index;

			song.instrument(new Instrument(part.name(), part));
			song.rack[index] = index;
		}

		final pattern = song.add(new Pattern("long", bar * 4));
		pattern.lane(Part.Fm1).add(new Note(0, bar * 4, 60, 100));

		song.track(new Track("row")).add(new Clip(0, 0, bar * 4));

		return song;
	}

	static inline final HUSH_BLOCK = 512;
	static inline final HUSH_RATE = 44100;
	static inline final HUSH_ROUNDS = 200;

	static function hushed():Void {
		final transport = new mdd.play.Transport(holding(), 65536);

		transport.rewind();
		transport.play();

		var on = 0;
		var blocks = 0;

		while (on == 0 && blocks < 32) {
			transport.advance(HUSH_BLOCK, HUSH_RATE);
			on += keyed(transport.stream, true, Part.Fm1);
			blocks++;
		}

		transport.stop();
		transport.advance(HUSH_BLOCK, HUSH_RATE);

		final off = keyed(transport.stream, false, Part.Fm1);

		says("stopping writes the key off that ends a note", on > 0 && off > 0,
			"a note keyed on after " + blocks + " blocks of " + HUSH_BLOCK
			+ " frames, and the block after the stop carries " + off + " key off"
			+ (off == 1 ? "" : "s") + " for that channel");

		live();
	}

	static function live():Void {
		final transport = new mdd.play.Transport(holding(), 65536);

		transport.rewind();

		final alive = new mdd.host.Atomic(1);
		final ons = new mdd.host.Atomic(0);
		final offs = new mdd.host.Atomic(0);
		final served = new mdd.host.Atomic(0);

		sys.thread.Thread.create(function():Void {
			while (alive.load() == 1) {
				transport.advance(HUSH_BLOCK, HUSH_RATE);

				final up = keyed(transport.stream, true, Part.Fm1);
				final down = keyed(transport.stream, false, Part.Fm1);

				if (up > 0) ons.add(up);
				if (down > 0) offs.add(down);

				served.add(1);
			}
		});

		var seed = 0x2F6E;
		var late = 0;
		var worst = 0.0;

		for (round in 0...HUSH_ROUNDS) {
			ons.store(0);

			transport.seek(0);
			transport.play();

			var waited = 0;

			while (ons.load() == 0 && waited < 400) {
				Sys.sleep(0.001);
				waited++;
			}

			seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
			Sys.sleep((seed % 1200) / 100000.0);

			offs.store(0);

			final began = mdd.host.Sdl.ticks();
			transport.stop();

			waited = 0;

			while (offs.load() == 0 && waited < 200) {
				Sys.sleep(0.001);
				waited++;
			}

			final took = mdd.host.Sdl.ticks() - began;

			if (offs.load() == 0) late++;
			else if (took > worst) worst = took;
		}

		alive.store(0);
		Sys.sleep(0.05);

		says("and a stop from another thread reaches the render one", late == 0,
			HUSH_ROUNDS + " stops timed across the block a render thread was serving, "
			+ late + " of them with no key off inside 200 ms, and the slowest answered in "
			+ Math.round(worst * 1000000) / 1000 + " ms");
	}

	static function raced():Void {
		final session = mdd.app.Session.started(mdd.song.Library.embedded());
		final render = new mdd.play.Render(44100, mdd.play.Render.BLOCK);

		render.transport = session.transport;
		session.transport.play();

		final blocks = new mdd.host.Atomic(0);
		final alive = new mdd.host.Atomic(1);

		sys.thread.Thread.create(function():Void {
			while (alive.load() == 1) {
				final from = session.transport.advance(mdd.play.Render.BLOCK, 44100);
				render.serve(session.transport.stream, from, mdd.play.Render.BLOCK,
					session.transport.entering, true);
				blocks.add(1);
			}
		});

		var made = 0;
		var dropped = 0;

		for (round in 0...3000) {
			if (round % 40 == 0) Sys.sleep(0.001);

			final part:Part = round % 6;
			final note = new Note((round * 7) % 384, 24, 48 + (round % 24), 100);

			session.does(new AddNote(session.pattern, part, note));
			made++;

			if (round % 3 != 0) continue;

			session.does(new mdd.song.edit.RemoveNote(session.pattern, part, note));
			dropped++;
		}

		alive.store(0);
		Sys.sleep(0.05);

		var left = 0;
		final pattern = session.current();

		if (pattern != null) {
			for (index in 0...Part.COUNT) left += pattern.lane(index).notes.length;
		}

		says("the song survives being edited while it plays", left == made - dropped
			&& blocks.load() > 0,
			made + " notes written and " + dropped + " taken back while the render thread"
			+ " served " + blocks.load() + " blocks of the same song, leaving " + left
			+ " of an expected " + (made - dropped));
	}

	static function sounded():Void {
		final stream = new Stream(8192);
		final held = new mdd.play.Sounding();

		final wanted:Array<Int> = [];
		final parts:Array<Int> = [];

		for (index in 0...6) {
			final part:Part = index;
			final note = 48 + index * 5;

			stream.tune(index * 100, part, note);
			stream.keyOn(index * 100, part);

			wanted.push(note);
			parts.push(index);
		}

		for (index in 6...9) {
			final part:Part = index;
			final note = 60 + (index - 6) * 7;

			stream.square(index * 100, part, note);
			stream.attenuate(index * 100, part, 0);

			wanted.push(note);
			parts.push(index);
		}

		held.take(stream, 0);

		var right = 0;
		var worst = 0;

		for (at in 0...parts.length) {
			final index = parts[at];
			final away = held.notes[index] - wanted[at];
			final much = away < 0 ? -away : away;

			if (much == 0) right++;
			if (much > worst) worst = much;
		}

		says("the stream says what sounds", right == parts.length && worst == 0,
			right + " of " + parts.length + " notes read back off the register writes alone, "
			+ "on the part that was keyed");

		var on = 0;
		for (index in 0...9) if (held.keyed[index]) on++;

		says("and which of them are keyed", on == 9, on + " of 9 parts keyed on");

		for (index in 0...6) stream.keyOff(1000, index);
		for (index in 6...9) stream.attenuate(1000, index, 15);

		held.take(stream, 0);

		var still = 0;
		for (index in 0...9) if (held.keyed[index]) still++;

		says("and when they stop", still == 0, "every part reads silent after key off");
	}

	static function identical():Void {
		final song = written();
		final span = song.tempo.samplesAt(song.ends());

		final offline = new Stream(262144);
		poured(song, span, span, offline);

		says("the stream is made", offline.count > 0 && offline.dropped == 0,
			offline.count + " register writes across " + round(span / Tempo.TICKS, 2)
			+ " s of song");

		for (block in [128, 256, 1024, 4099]) {
			final live = new Stream(262144);
			poured(song, span, block, live);

			final parted = alike(offline, live);

			final said = parted == -1
				? live.count + " writes against " + offline.count
				: (parted >= 0 ? "they part at write " + parted
					: live.count + " writes, every one the same");

			says("live at " + block, parted == -2, said);
		}

		final quiet = new Stream(262144);
		song.muted[Part.Fm1.index()] = true;
		poured(song, span, span, quiet);
		song.muted[Part.Fm1.index()] = false;

		says("a mute is heard", quiet.count < offline.count,
			"muting FM1 drops " + (offline.count - quiet.count) + " writes");
	}

	static function faces():Void {
		final song = written();
		final said = Project.text(song);

		final again = Project.read(said);
		Project.unbulk(again, Project.bulk(song));

		says("the structure returns", Project.text(again) == said,
			said.length + " bytes of json written, read and written again unchanged");

		final root = Gate.root + "/export/project";
		final folder = root + "/exploded";
		final packed = root + "/packed." + mdd.Config.SUFFIX;

		if (sys.FileSystem.exists(folder)) wipe(folder);
		if (sys.FileSystem.exists(packed)) sys.FileSystem.deleteFile(packed);

		Project.saveFolder(song, folder);
		Project.savePacked(song, packed);

		final opened = Project.openFolder(folder);
		final unpacked = Project.openPacked(packed);

		says("the folder returns", Project.text(opened) == said && sameSamples(song, opened),
			"project.json, chunks and " + song.samples.length + " sample file read back the same");

		says("the zip returns", Project.text(unpacked) == said && sameSamples(song, unpacked),
			"the same layout inside a zip reads back the same");

		final live = new Stream(262144);
		final span = song.tempo.samplesAt(song.ends());
		poured(song, span, span, live);

		final other = new Stream(262144);
		poured(unpacked, span, span, other);

		says("what it plays returns", alike(live, other) == -2,
			"a song read back from a zip makes the same " + live.count + " register writes");
	}

	static function sameSamples(one:Song, two:Song):Bool {
		if (one.samples.length != two.samples.length) return false;

		for (index in 0...one.samples.length) {
			final left = one.samples[index];
			final right = two.samples[index];

			if (left.length() != right.length()) return false;
			for (i in 0...left.length()) if (left.bytes[i] != right.bytes[i]) return false;
		}

		return true;
	}

	static function wipe(path:String):Void {
		if (!sys.FileSystem.exists(path)) return;

		if (!sys.FileSystem.isDirectory(path)) {
			sys.FileSystem.deleteFile(path);
			return;
		}

		for (entry in sys.FileSystem.readDirectory(path)) wipe(path + "/" + entry);
		sys.FileSystem.deleteDirectory(path);
	}

	static function chunks():Void {
		final out = new Chunks();

		out.add("SMPL", haxe.io.Bytes.ofString("one"));
		out.add("WHAT", haxe.io.Bytes.ofString("a tag from a newer build"));
		out.add("SMPL", haxe.io.Bytes.ofString("two"));

		final read = Chunks.read(out.bytes());
		final samples = Chunks.of(read, "SMPL");

		says("chunks are read", read.length == 3 && samples.length == 2,
			read.length + " chunks, " + samples.length + " of them samples");

		says("an odd chunk pads", samples.length == 2
			&& samples[0].body.toString() == "one" && samples[1].body.toString() == "two",
			"a three byte body is padded and the chunk after it still lands");

		says("an unknown tag is skipped", Chunks.of(read, "NOPE").length == 0
			&& samples[1].body.toString() == "two",
			"a tag this build does not know does not stop the ones it does");
	}

	static function commands():Void {
		final song = written();
		final history = new History();

		final before = Project.text(song);

		final note = new Note(120, 48, 72, 100);
		history.does(song, new AddNote(0, Part.Fm2, note));
		history.does(song, new MoveNote(0, Part.Fm2, note, 168, 76));
		history.does(song, new SetTempo(192, 96.5));
		history.does(song, new AddClip(0, new Clip(1, 768, 384)));
		history.does(song, new mdd.song.edit.AddPattern(
			new mdd.song.Pattern("spare", 384)));
		history.does(song, new mdd.song.edit.RemovePattern(0));

		final after = Project.text(song);

		var undone = 0;
		while (history.undo(song)) undone++;

		final back = Project.text(song);

		var redone = 0;
		while (history.redo(song)) redone++;

		final again = Project.text(song);

		says("edits change the song", before != after,
			"six edits move the song by " + Math.round(Math.abs(after.length - before.length))
			+ " bytes of written state");

		says("undo returns it", back == before,
			undone + " reverts put the song back byte for byte");

		says("the stack knows", undone == 6 && redone == 6,
			undone + " undone and " + redone
			+ " redone, and nothing left waiting either way");

		says("redo repeats it", again == after,
			redone + " replays put it back where the edits left it");
	}
}
