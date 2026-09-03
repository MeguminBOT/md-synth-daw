package mdd.app;

import mdd.host.Audio;
import mdd.host.Device;
import mdd.play.Render;
import mdd.play.Sounding;
import mdd.play.Stream;
import mdd.play.Transport;
import mdd.song.Part;
import mdd.view.monitor.Scope;

@:unreflective
final class Sound {
	public static inline final METER = 1.0;

	public var speaker:cpp.Star<Device> = null;
	public var render:Null<Render> = null;

	public final peaks:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(Part.COUNT);
	public final sounding:Sounding = new Sounding();

	public var seen:Int = 0;
	public var heard:Int = 0;

	var tookTaps:Int = 0;
	var tookMeters:Int = 0;

	public function new() {}

	public function open(transport:Transport):Void {
		speaker = Audio.open(0, Render.BLOCK);
		if (speaker == null) return;

		render = new Render(Audio.rate(speaker), Render.BLOCK);
		render.transport = transport;
		render.start(speaker);
	}

	public function follows(transport:Transport):Void {
		if (render != null) render.transport = transport;
	}

	public function stop():Void {
		if (render != null) render.transport.stop();
	}

	public function lit(stream:Stream):Void {
		if (!render.litAt(render.heardAt, sounding)) heard = sounding.take(stream, heard);
	}

	public function poured(scope:Scope):Void {
		final ear = Std.int(render.heardAt / Render.TAP_EVERY);

		var now = render.tapped;
		if (ear > 0 && ear < now) now = ear;

		var from = tookTaps;

		if (now - from > Render.TAPS) from = now - Render.TAPS;
		if (from < 0) from = 0;

		while (from < now) {
			final slot = from % Render.TAPS;

			for (index in 0...Part.COUNT) {
				scope.feed(index, render.taps[index * Render.TAPS + slot]);
			}

			from++;
		}

		tookTaps = now;
	}

	public function metered():Void {
		final now = render.tapped;
		var from = tookMeters;

		if (now - from > Render.TAPS) from = now - Render.TAPS;
		if (from < 0) from = 0;

		tookMeters = now;

		for (index in 0...Part.COUNT) {
			final base = index * Render.TAPS;
			var most = 0.0;
			var at = from;

			while (at < now) {
				final value = render.taps[base + at % Render.TAPS];
				final size = value < 0 ? -value : value;

				if (size > most) most = size;
				at++;
			}

			peaks[index] = most * METER;
		}
	}

	public function shut():Void {
		if (render != null) render.stop();
		if (speaker != null) Audio.close(speaker);
	}
}
