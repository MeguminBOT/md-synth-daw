package mdd.song;

@:unreflective
final class Tempo {
	public static inline final TICKS = 44100;

	public var ppqn(default, null):Int;
	public var rate:Int;

	public final at:Array<Int> = [];
	public final bpm:Array<Float> = [];

	final base:Array<Float> = [];
	final perTick:Array<Float> = [];

	public function new(ppqn:Int = 96, first:Float = 120, rate:Int = 60) {
		this.ppqn = ppqn < 1 ? 96 : ppqn;
		this.rate = rate;

		at.push(0);
		bpm.push(first <= 0 ? 120 : first);
		settle();
	}

	public function set(tick:Int, beats:Float):Void {
		final want = beats <= 0 ? 1 : beats;

		if (tick <= 0) {
			bpm[0] = want;
			settle();
			return;
		}

		for (i in 0...at.length) {
			if (at[i] != tick) continue;
			bpm[i] = want;
			settle();
			return;
		}

		var index = at.length;
		while (index > 0 && at[index - 1] > tick) index--;

		at.insert(index, tick);
		bpm.insert(index, want);
		settle();
	}

	public function drop(tick:Int):Bool {
		if (tick <= 0) return false;

		for (i in 0...at.length) {
			if (at[i] != tick) continue;
			at.splice(i, 1);
			bpm.splice(i, 1);
			settle();
			return true;
		}

		return false;
	}

	public function resolve(ppqn:Int):Void {
		this.ppqn = ppqn < 1 ? 96 : ppqn;
		settle();
	}

	public function settle():Void {
		base.resize(0);
		perTick.resize(0);

		var running = 0.0;

		for (i in 0...at.length) {
			base.push(running);
			perTick.push(TICKS * 60.0 / (bpm[i] * ppqn));

			if (i + 1 < at.length) running += (at[i + 1] - at[i]) * perTick[i];
		}
	}

	public function segment(tick:Int):Int {
		var found = 0;
		for (i in 0...at.length) if (at[i] <= tick) found = i;
		return found;
	}

	public function samplesAt(tick:Int):Int {
		final which = segment(tick);
		return Math.round(base[which] + (tick - at[which]) * perTick[which]);
	}

	public function tickAt(samples:Int):Int {
		var which = 0;
		for (i in 0...at.length) if (base[i] <= samples) which = i;

		return at[which] + Math.round((samples - base[which]) / perTick[which]);
	}

	public inline function beatsAt(tick:Int):Float {
		return bpm[segment(tick)];
	}

	public function copy():Tempo {
		final out = new Tempo(ppqn, bpm[0], rate);

		for (i in 1...at.length) {
			out.at.push(at[i]);
			out.bpm.push(bpm[i]);
		}

		out.settle();
		return out;
	}
}
