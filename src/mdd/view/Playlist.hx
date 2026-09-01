package mdd.view;

import mdd.song.AddClip;
import mdd.song.Clip;
import mdd.song.MoveClip;
import mdd.song.RemoveClip;
import mdd.song.Track;
import mdd.ui.Colour;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Pointer;
import mdd.ui.Theme;
import mdd.ui.Widget;

@:unreflective
final class Playlist extends Widget {
	public final session:Session;

	public var perTick:Float = 0.08;
	public var trackTall:Float = 34;
	public var offsetX:Float = 0;

	public var playhead:Int = -1;
	public var chosen(default, null):Null<Clip> = null;
	public var painted(default, null):Int = 0;

	var chosenTrack:Int = -1;
	var dragging:Null<Clip> = null;
	var grabTick:Int = 0;
	var hoverTrack:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public function names():Float {
		final root = root();
		return root == null ? 110 : root.metrics.whole(110);
	}

	public function ruler():Float {
		final root = root();
		return root == null ? 22 : root.metrics.whole(22);
	}

	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - names() + offsetX) / perTick);
	}

	public inline function atTick(tick:Int):Float {
		return x + names() + tick * perTick - offsetX;
	}

	public function trackAt(py:Float):Int {
		final at = Std.int((py - y - ruler()) / trackTall);
		return at < 0 || at >= session.song.tracks.length ? -1 : at;
	}

	public function clipAt(px:Float, py:Float):Null<Clip> {
		final which = trackAt(py);
		if (which < 0) return null;

		final tick = tickAt(px);
		final track = session.song.tracks[which];

		for (clip in track.clips) {
			if (tick >= clip.at && tick < clip.ends()) return clip;
		}

		return null;
	}

	public function scrollTo(px:Float):Void {
		final most = session.song.ends() * perTick - (width - names());
		offsetX = px < 0 ? 0 : (px > most ? (most < 0 ? 0 : most) : px);
		invalidate();
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				if (event.ctrl()) {
					final tick = tickAt(event.x);
					final want = perTick * (event.dy > 0 ? 1.25 : 0.8);

					perTick = want < 0.01 ? 0.01 : (want > 1 ? 1 : want);
					scrollTo(tick * perTick - (event.x - x - names()));
					return true;
				}

				scrollTo(offsetX - event.dy * trackTall * 3);
				return true;

			case Kind.PointerDown:
				final which = trackAt(event.y);
				if (which < 0) return false;

				final under = clipAt(event.x, event.y);

				if (event.button == Pointer.Right) {
					if (under != null) {
						session.does(new RemoveClip(which, under));
						chosen = null;
						invalidate();
					}
					return true;
				}

				if (under != null) {
					chosen = under;
					chosenTrack = which;
					dragging = under;
					grabTick = tickAt(event.x) - under.at;
					invalidate();
					return true;
				}

				final pattern = session.current();
				if (pattern == null) return true;

				final at = session.snapped(tickAt(event.x));
				final clip = new Clip(session.pattern, at < 0 ? 0 : at, pattern.length);

				session.does(new AddClip(which, clip));

				chosen = clip;
				chosenTrack = which;
				dragging = clip;
				grabTick = 0;

				invalidate();
				return true;

			case Kind.PointerMove:
				final which = trackAt(event.y);

				if (which != hoverTrack) {
					hoverTrack = which;
					invalidate();
				}

				if (dragging == null) return false;

				final at = session.snapped(tickAt(event.x) - grabTick);
				dragging.at = at < 0 ? 0 : at;

				invalidate();
				return true;

			case Kind.PointerUp:
				if (dragging == null) return false;

				final held = dragging;
				final was = grabTick;

				dragging = null;
				session.changed();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	function steered(event:Input):Bool {
		if (chosen == null || chosenTrack < 0) return false;

		switch (event.code) {
			case Key.Delete, Key.Backspace:
				session.does(new RemoveClip(chosenTrack, chosen));
				chosen = null;
				invalidate();
				return true;

			case Key.Up:
				session.does(new MoveClip(chosenTrack, chosen, chosen.at, chosen.transpose + 1));
				invalidate();
				return true;

			case Key.Down:
				session.does(new MoveClip(chosenTrack, chosen, chosen.at, chosen.transpose - 1));
				invalidate();
				return true;

			case _:
		}

		return false;
	}

	override function hovered(on:Bool):Void {
		if (!on) hoverTrack = -1;
		super.hovered(on);
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null || root.metrics.body == null) return;

		final theme = root.theme;
		final metrics = root.metrics;
		final song = session.song;

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		final left = x + names();
		final top = y + ruler();

		paint.pushClip(left, top, width - names(), height - ruler());

		bars(paint, theme, metrics, left, top);
		clips(paint, theme, metrics, top);

		if (playhead >= 0) {
			final at = atTick(playhead);
			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(2), height - ruler(), theme.warn, 0.9);
			}
		}

		paint.popClip();

		rails(paint, theme, metrics, top);
		heading(paint, theme, metrics, left);
	}

	function bars(paint:Paint, theme:Theme, metrics:Metrics, left:Float, top:Float):Void {
		final bar = session.song.tempo.ppqn * 4;
		final hair = metrics.whole(1);
		final length = session.song.ends() + bar * 4;

		var tick = Std.int(tickAt(left) / bar) * bar;
		if (tick < 0) tick = 0;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left) {
				paint.rect(at, top, hair, height - ruler(), theme.frame,
					tick % (bar * 4) == 0 ? 0.8 : 0.3);
			}

			tick += bar;
		}

		for (which in 0...session.song.tracks.length) {
			final row = top + which * trackTall;
			if (row > y + height) break;

			if (which == hoverTrack) {
				paint.rect(left, row, width - names(), trackTall, theme.ink, 0.02);
			}

			paint.rect(left, row + trackTall - metrics.whole(1), width - names(),
				metrics.whole(1), theme.frame, 0.4);
		}
	}

	function clips(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(font);

		for (which in 0...session.song.tracks.length) {
			final track = session.song.tracks[which];
			final row = top + which * trackTall;

			if (row > y + height) break;

			for (clip in track.clips) {
				final at = atTick(clip.at);
				final wide = clip.length * perTick;

				if (at + wide < x + names() || at > x + width) continue;

				painted++;

				final pattern = session.song.patternAt(clip.pattern);
				final colour = pattern != null && pattern.colour >= 0
					? new Colour(pattern.colour)
					: theme.part(clip.pattern % 11);

				paint.roundedRect(at, row + 2, wide, trackTall - 5, metrics.radiusSmall, colour,
					track.muted ? 0.3 : 0.75);

				if (clip == chosen) {
					paint.outline(at, row + 2, wide, trackTall - 5, theme.ink, metrics.whole(1));
				}

				final said = pattern == null ? "?" : pattern.name;
				final tail = clip.transpose == 0 ? ""
					: (clip.transpose > 0 ? "  +" + clip.transpose : "  " + clip.transpose);

				paint.text(said + tail, at + metrics.unit,
					row + 2 + (trackTall - 5 - font.height) * 0.5 + font.ascent, theme.sink);
			}
		}
	}

	function rails(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final wide = names();
		final font = metrics.body;

		paint.rect(x, top, wide, height - ruler(), theme.panel);
		paint.reface(font);

		for (which in 0...session.song.tracks.length) {
			final track = session.song.tracks[which];
			final row = top + which * trackTall;

			if (row > y + height) break;

			paint.text(track.name, x + metrics.inset,
				row + (trackTall - font.height) * 0.5 + font.ascent,
				track.muted ? theme.dim : theme.ink);
		}

		paint.rect(x + wide - metrics.whole(1), top, metrics.whole(1), height - ruler(),
			theme.frame);
	}

	function heading(paint:Paint, theme:Theme, metrics:Metrics, left:Float):Void {
		final tall = ruler();

		paint.rect(x, y, width, tall, theme.bar);
		paint.pushClip(left, y, width - names(), tall);

		final font = metrics.small == null ? metrics.body : metrics.small;
		paint.reface(font);

		final bar = session.song.tempo.ppqn * 4;
		final length = session.song.ends() + bar * 4;

		var tick = Std.int(tickAt(left) / (bar * 4)) * bar * 4;
		if (tick < 0) tick = 0;

		while (tick <= length) {
			final at = atTick(tick);
			if (at > x + width) break;

			if (at >= left) {
				paint.text(Std.string(Std.int(tick / bar) + 1), at + metrics.unit,
					y + (tall - font.height) * 0.5 + font.ascent, theme.dim);
			}

			tick += bar * 4;
		}

		paint.popClip();
		paint.rect(x, y + tall - metrics.whole(1), width, metrics.whole(1), theme.frame);
	}
}
