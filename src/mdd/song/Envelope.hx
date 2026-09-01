package mdd.song;

@:unreflective
final class Envelope {
	public final steps:Array<Int> = [];
	public var loop:Int = -1;
	public var speed:Int = 1;
	public var noise:Int = 4;

	public function new() {}

	public function at(step:Int):Int {
		if (steps.length == 0) return 0;
		if (step < steps.length) return steps[step];
		if (loop < 0 || loop >= steps.length) return steps[steps.length - 1];

		final over = steps.length - loop;
		return steps[loop + (step - steps.length) % over];
	}

	public function copy():Envelope {
		final out = new Envelope();
		for (value in steps) out.steps.push(value);
		out.loop = loop;
		out.speed = speed;
		out.noise = noise;
		return out;
	}
}
