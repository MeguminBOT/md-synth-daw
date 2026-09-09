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

/**
	The audio device and the render behind it, and what the meters and the scope read
	back out of them.

	Nothing here decides what is played. It opens the device, hands the render the
	transport, and reads levels back for the interface.
**/
final class Sound {
	/**
		How fast a meter falls back, in units a second.
	**/
	public static inline final METER = 1.0;

	/**
		The open device, or null.
	**/
	public var speaker:cpp.Star<Device> = null;

	/**
		The render feeding it.
	**/
	public var render:Null<Render> = null;

	/**
		The level of each part, for the meters.
	**/
	public final peaks:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(Part.COUNT);

	/**
		What is keyed now, read back out of the register stream rather than asked of the
		sequencer, so it agrees with what is actually heard.
	**/
	public final sounding:Sounding = new Sounding();

	/**
		How far through the stream the meters have read.
	**/
	public var seen:Int = 0;

	/**
		Where the device is actually playing.
	**/
	public var heard:Int = 0;

	var tookTaps:Int = 0;
	var tookMeters:Int = 0;

	/**
		Builds a sound with no device open.
	**/
	public function new() {}

	/**
		Opens the device, builds a render, primes it and starts it.

		@param transport The transport the render should follow.
	**/
	public function open(transport:Transport):Void {
		speaker = Audio.open(0, Render.BLOCK);
		if (speaker == null) return;

		render = new Render(Audio.rate(speaker), Render.BLOCK);
		render.transport = transport;
		render.start(speaker);
	}

	/**
		Points the render at another transport, which loading a song needs.

		@param transport The transport to follow.
	**/
	public function follows(transport:Transport):Void {
		if (render != null) render.transport = transport;
	}

	/**
		Sets the monitoring gain, which changes what is heard and never what is
		exported.

		@param much The gain.
	**/
	public function monitors(much:Float):Void {
		if (render != null) render.monitor = much < 0 ? 0 : (much > 1 ? 1 : much);
	}

	/**
		Stops the device without closing it.
	**/
	public function stop():Void {
		if (render != null) render.transport.stop();
	}

	/**
		Reads the register stream forward to work out what is keyed now.

		@param stream The stream to read.
	**/
	public function lit(stream:Stream):Void {
		if (!render.litAt(render.heardAt, sounding)) heard = sounding.take(stream, heard);
	}

	/**
		Hands the scope the samples it draws, from the render ring.

		@param scope The scope to fill.
	**/
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

	/**
		Works out each part's level from what is keyed, and lets the meters fall back.
	**/
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

	/**
		Stops and closes the device.
	**/
	public function shut():Void {
		if (render != null) render.stop();
		if (speaker != null) Audio.close(speaker);
	}
}
