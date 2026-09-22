package mdd.song.edit;

import mdd.song.Part;

/**
	Loads a preset into a part as a copy of it, so the preset itself stays as it was written.

	A channel is edited as it is played with, and the preset it came from is what it goes back to:
	choosing the same preset again puts every field back, and one parameter can be put back on its
	own. The copy carries the identity of the preset it came from.

	The preset comes from one of two places. One the piece already carries is named by its index.
	One the library holds is handed over whole, and the copy is what goes into the piece: the
	library is never copied into a piece wholesale, so a piece carries what it plays and nothing
	it was only offered. A copy made once is reused when the step is redone.

	A converter part is loaded by pointing at the preset itself, because a kit is the presets in
	one bank and a copy of one hit would not be in it. A kit out of the library is copied in whole,
	into a bank of the piece's named for it, and a bank of that name already holding the same hits
	is used rather than a second copy.

	One step on the undo stack. `apply` does it and `revert` puts the song back exactly as it was,
	which is why anything it overwrites is kept here.
**/
final class TakesPreset implements Command {
	final part:Part;
	final which:Int;

	/**
		A preset out of the library, or null where the piece carries the one it takes.
	**/
	var preset:Null<Instrument> = null;

	/**
		The recording that preset plays, or null.
	**/
	var sample:Null<Sample> = null;

	/**
		What the kit is called, where a whole kit is taken out of the library.
	**/
	var kit:String = "";

	/**
		The hits of that kit, and what each plays, by the same index.
	**/
	final hits:Array<Instrument> = [];
	final played:Array<Null<Sample>> = [];

	/**
		Which of those hits the part points at.
	**/
	var lead:Int = 0;

	/**
		The copy this step made the first time it was applied, reused on a redo.
	**/
	var made:Null<Instrument> = null;

	var was:Int = -1;
	var kept:Null<Instrument> = null;

	final held:Array<Note> = [];
	final marks:Array<Int> = [];

	/**
		Records what to do with a preset the piece already carries. Nothing changes until `apply`
		is called.

		@param part Which part loads it.
		@param which The preset, by index into the song.
	**/
	public function new(part:Part, which:Int) {
		this.part = part;
		this.which = which;
	}

	/**
		Records what to do with a preset the library holds.

		@param part Which part loads it.
		@param preset The preset. The step keeps it rather than a copy, and copies it when applied.
		@param sample The recording it plays, or null.
		@return The step.
	**/
	public static function adopting(part:Part, preset:Instrument, sample:Null<Sample>):TakesPreset {
		final out = new TakesPreset(part, -1);

		out.preset = preset;
		out.sample = sample;

		return out;
	}

	/**
		Records what to do with a kit the library holds.

		@param part The converter part.
		@param name What the kit is called.
		@param hits Its hits.
		@param samples What each plays, by the same index.
		@param lead Which hit the part points at.
		@return The step.
	**/
	public static function kitting(part:Part, name:String, hits:Array<Instrument>,
			samples:Array<Null<Sample>>, lead:Int):TakesPreset {
		final out = new TakesPreset(part, -1);

		out.kit = name;
		out.lead = lead < 0 || lead >= hits.length ? 0 : lead;

		for (index in 0...hits.length) {
			out.hits.push(hits[index]);
			out.played.push(index < samples.length ? samples[index] : null);
		}

		return out;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final index = part.index();

		was = song.rack[index];
		kept = null;

		if (hits.length > 0) {
			final at = kitted(song);
			if (at >= 0) pointed(song, at);

			return;
		}

		final source = preset == null ? song.instrumentAt(which) : preset;
		if (source == null) return;

		if (part.sampled() && preset == null) {
			pointed(song, which);
			return;
		}

		final playing = song.instrumentAt(was);

		if (playing != null && playing != source && source.id != "" && playing.from == source.id) {
			kept = playing.copy();
			playing.takes(source);

			return;
		}

		pointed(song, adopted(song, source));
	}

	/**
		@param song The song.
		@param source The preset to copy.
		@return The copy of it the song holds, by index: the one this step made before where the
			song still holds it, and a new one otherwise.
	**/
	function adopted(song:Song, source:Instrument):Int {
		final before = made;

		if (before != null) {
			final at = song.instruments.indexOf(before);
			if (at >= 0) return at;
		}

		final at = song.adopts(source, sample);
		made = song.instruments[at];

		return at;
	}

	/**
		Puts the kit in the song, or finds it there already.

		@param song The song.
		@return The hit the part points at, by index into the song, or -1 where the kit is empty.
	**/
	function kitted(song:Song):Int {
		for (bank in song.banks) {
			if (bank.name != kit || bank.instruments.length != hits.length) continue;

			var same = true;
			var found = -1;

			for (at in 0...hits.length) {
				final index = bank.instruments[at];
				final one = song.instrumentAt(index);

				if (one == null || one.from != hits[at].id) {
					same = false;
					break;
				}

				if (at == lead) found = index;
			}

			if (same && found >= 0) return found;
		}

		var name = kit;
		var number = 2;

		while (taken(song, name)) {
			name = kit + " " + number;
			number++;
		}

		final bank = song.banked(name);
		var found = -1;

		for (at in 0...hits.length) {
			final index = song.adopts(hits[at], played[at]);

			bank.add(index);
			if (at == lead) found = index;
		}

		return found;
	}

	/**
		@param song The song.
		@param name A bank's name.
		@return Whether the song has a bank of that name with anything in it.
	**/
	static function taken(song:Song, name:String):Bool {
		for (bank in song.banks) if (bank.name == name && bank.instruments.length > 0) return true;

		return false;
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final playing = song.instrumentAt(was);
		final holding = kept;

		if (holding != null && playing != null) playing.takes(holding);

		song.rack[part.index()] = was;

		for (index in 0...held.length) held[index].instrument = marks[index];

		held.resize(0);
		marks.resize(0);
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "load a preset into " + part.name();
	}

	/**
		Points the part, and every note already written for it, at one instrument.

		@param song The song.
		@param at The instrument, by index.
	**/
	function pointed(song:Song, at:Int):Void {
		song.rack[part.index()] = at;

		held.resize(0);
		marks.resize(0);

		for (pattern in song.patterns) {
			for (note in pattern.lane(part).notes) {
				if (note.instrument == at) continue;

				held.push(note);
				marks.push(note.instrument);
				note.instrument = at;
			}
		}
	}
}
