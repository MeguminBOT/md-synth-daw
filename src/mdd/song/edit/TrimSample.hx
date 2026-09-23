package mdd.song.edit;

import haxe.ds.Vector;

/**
	Cuts a recording down to one span of it, and moves its loop point with it.

	A loop point inside the span keeps its place in the sound. One before the span loops the whole
	of what is left, because everything kept was inside the loop, and one past the span leaves the
	recording playing once, because nothing it looped is kept.

	One step on the undo stack. `apply` does it and `revert` puts the song back exactly as it was,
	which is why the bytes it replaces and the loop point are kept here.
**/
final class TrimSample implements Command {
	final at:Int;
	final from:Int;
	final until:Int;

	var was:Null<Vector<Int>> = null;
	var wasLoop:Int = -1;

	/**
		Records what to do. Nothing changes until `apply` is called.

		@param at Which recording, by index.
		@param from The first byte kept.
		@param until One past the last byte kept.
	**/
	public function new(at:Int, from:Int, until:Int) {
		this.at = at;
		this.from = from;
		this.until = until;
	}

	/**
		@param sample A recording.
		@param from The first byte kept.
		@param until One past the last byte kept.
		@return Whether cutting it there would change anything: the span has to hold at least one
			byte, lie inside the recording and leave something out.
	**/
	public static function worth(sample:Sample, from:Int, until:Int):Bool {
		final many = sample.length();
		return from >= 0 && until <= many && until > from && (from > 0 || until < many);
	}

	/**
		@param loop Where the recording loops back to, or -1 where it plays once.
		@param from The first byte kept.
		@param until One past the last byte kept.
		@return Where the cut recording loops back to, or -1 where it plays once.
	**/
	public static function looped(loop:Int, from:Int, until:Int):Int {
		if (loop < 0 || loop >= until) return -1;
		return loop < from ? 0 : loop - from;
	}

	/**
		Does it, keeping whatever `revert` will need to put back.

		@param song The song to act on.
	**/
	public function apply(song:Song):Void {
		final sample = song.sampleAt(at);
		if (sample == null || !worth(sample, from, until)) return;

		final bytes = sample.bytes;
		final kept = new Vector<Int>(until - from);

		Vector.blit(bytes, from, kept, 0, kept.length);

		was = bytes;
		wasLoop = sample.loop;

		sample.hold(kept);
		sample.loop = looped(wasLoop, from, until);
	}

	/**
		Puts the song back as it was.

		@param song The song to act on.
	**/
	public function revert(song:Song):Void {
		final held = was;
		final sample = song.sampleAt(at);

		if (held == null || sample == null) return;

		sample.hold(held);
		sample.loop = wasLoop;
		was = null;
	}

	/**
		@return What the undo entry is called, in lower case.
	**/
	public function label():String {
		return "trim a sample";
	}
}
