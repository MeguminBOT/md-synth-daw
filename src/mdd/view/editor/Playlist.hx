package mdd.view.editor;

import mdd.app.Locale;
import mdd.app.Session;
import mdd.song.edit.AddClip;
import mdd.song.edit.AddTrack;
import mdd.song.Clip;
import mdd.song.edit.MoveClip;
import mdd.song.edit.RemoveClip;
import mdd.song.edit.RemoveTrack;
import mdd.song.edit.SizeClip;
import mdd.song.Part;
import mdd.ui.Colour;
import mdd.ui.control.Choice;
import mdd.ui.control.Menu;
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
	public static inline final SPARE = 4;

	public final session:Session;

	public var perTick:Float = 0.25;
	public var offsetX:Float = 0;
	public var offsetY:Float = 0;

	public var rowTall:Float = 0;
	public var playhead:Int = -1;
	public var chosen(default, null):Null<Clip> = null;
	public var painted(default, null):Int = 0;

	public var onRename:Null<Int -> Void> = null;
	public var onOpen:Null<Clip -> Void> = null;

	var chosenTrack:Int = -1;
	var scrubbing:Bool = false;
	var sizingRows:Int = -1;
	var hoverEdge:Int = -1;
	var dragging:Null<Clip> = null;
	var sizing:Bool = false;
	var grabTick:Int = 0;
	var grabWasAt:Int = 0;
	var grabWasLong:Int = 0;
	var grabFresh:Bool = false;
	var hoverTrack:Int = -1;

	public function new(session:Session) {
		super();
		this.session = session;

		focusable = true;
		opaque = true;
	}

	public static inline final LEAST_ROW = 16;
	public static inline final MOST_ROW = 180;

	public function trackTall():Float {
		final root = root();
		if (rowTall <= 0) return root == null ? 34 : root.metrics.row;

		final least = root == null ? LEAST_ROW : root.metrics.whole(LEAST_ROW);
		final most = root == null ? MOST_ROW : root.metrics.whole(MOST_ROW);

		return rowTall < least ? least : (rowTall > most ? most : rowTall);
	}

	public function heighten(to:Float):Void {
		final was = trackTall();

		rowTall = to;
		if (trackTall() == was) return;

		scrollDown(offsetY);
		invalidate();
	}

	public function rowEdgeAt(px:Float, py:Float):Int {
		if (px < x || px >= x + names() || py < y + ruler()) return -1;

		final tall = trackTall();
		final which = Math.round((py - y - ruler() + offsetY) / tall) - 1;

		if (which < 0 || which >= rows()) return -1;
		if (Math.abs(atTrack(which) + tall - py) > edge() * 0.7) return -1;

		return which;
	}

	public function names():Float {
		final root = root();
		return root == null ? 148 : root.metrics.whole(148);
	}

	public function ruler():Float {
		final root = root();
		return root == null ? 24 : root.metrics.whole(24);
	}

	public function rows():Int {
		return session.song.tracks.length + SPARE;
	}

	public inline function tickAt(px:Float):Int {
		return Math.round((px - x - names() + offsetX) / perTick);
	}

	public inline function atTick(tick:Int):Float {
		return x + names() + tick * perTick - offsetX;
	}

	public inline function atTrack(which:Int):Float {
		return y + ruler() + which * trackTall() - offsetY;
	}

	public function trackAt(py:Float):Int {
		final at = Std.int((py - y - ruler() + offsetY) / trackTall());
		return at < 0 || at >= rows() ? -1 : at;
	}

	public function muteAt(px:Float):Bool {
		final root = root();
		if (root == null) return false;

		final metrics = root.metrics;
		final left = x + names() - metrics.whole(26);

		return px >= left && px < left + metrics.whole(18);
	}

	public function edge():Float {
		final root = root();
		return root == null ? 6 : root.metrics.whole(6);
	}

	public function onEdge(clip:Clip, px:Float):Bool {
		final right = atTick(clip.ends());
		final reach = edge();

		return px >= right - reach && px <= right + reach;
	}

	public function resized(clip:Clip, to:Int):Void {
		final least = session.snap < 1 ? 1 : session.snap;
		var want = session.snapped(to) - clip.at;

		if (want < least) want = least;
		if (want == clip.length) return;

		clip.length = want;
	}

	public function clipAt(px:Float, py:Float):Null<Clip> {
		final which = trackAt(py);
		if (which < 0 || which >= session.song.tracks.length) return null;

		final tick = tickAt(px);
		final track = session.song.tracks[which];

		for (clip in track.clips) {
			if (tick >= clip.at && tick < clip.ends()) return clip;
		}

		return null;
	}

	var framedFor:Int = -1;

	public function framed():Void {
		if (width <= 0) return;

		final beat = session.song.tempo.ppqn;
		if (beat < 1 || framedFor == beat) return;

		framedFor = beat;
		perTick = widest();

		scrollTo(0);
	}

	public function widest():Float {
		final length = session.song.ends();
		if (length < 1) return 0.01;

		final fits = (width - names()) / length;
		return fits < 0.01 ? fits : 0.01;
	}

	public function zoom(by:Float, around:Float):Void {
		final tick = tickAt(around);
		final want = perTick * by;
		final least = widest();

		perTick = want < least ? least : (want > 1 ? 1 : want);
		scrollTo(tick * perTick - (around - x - names()));
	}

	public function fit():Void {
		perTick = widest();
		scrollTo(0);
	}

	public function scrollTo(px:Float):Void {
		final most = session.song.ends() * perTick - (width - names());
		offsetX = px < 0 ? 0 : (px > most ? (most < 0 ? 0 : most) : px);
		invalidate();
	}

	public function scrollDown(py:Float):Void {
		final most = rows() * trackTall() - (height - ruler());
		offsetY = py < 0 ? 0 : (py > most ? (most < 0 ? 0 : most) : py);
		invalidate();
	}

	override function took(event:Input):Bool {
		switch (event.kind) {
			case Kind.Wheel:
				if ((event.ctrl() || event.alt()) && event.x < x + names()) {
					heighten(trackTall() * (event.dy > 0 ? 1.15 : 0.87));
					return true;
				}

				if (event.ctrl() || event.alt()) {
					zoom(event.dy > 0 ? 1.25 : 0.8, event.x);
					return true;
				}

				if (event.shift()) {
					scrollTo(offsetX - event.dy * trackTall() * 3);
					return true;
				}

				scrollDown(offsetY - event.dy * trackTall() * 2);
				return true;

			case Kind.PointerDown:
				final rein = reinAt(event.x, event.y);

				if (rein != 0) {
					reining = rein;
					reined(event.x, event.y);
					return true;
				}

				if (event.y < y + ruler() && event.x >= x + names()) {
					scrubbing = true;
					scrubbed(event.x);
					return true;
				}

				final held = rowEdgeAt(event.x, event.y);

				if (held >= 0 && event.button == Pointer.Left) {
					sizingRows = held;
					return true;
				}

				if (event.clicks > 1 && event.button == Pointer.Left) {
					final under = clipAt(event.x, event.y);

					if (under != null && under.drawn() && onOpen != null) {
						chosen = under;
						chosenTrack = trackAt(event.y);

						onOpen(under);
						return true;
					}
				}

				return pressed(event);

			case Kind.PointerMove:
				if (reining != 0) {
					reined(event.x, event.y);
					return true;
				}

				if (sizingRows >= 0) {
					heighten((event.y - y - ruler() + offsetY) / (sizingRows + 1));
					return true;
				}

				if (scrubbing) {
					scrubbed(event.x);
					return true;
				}

				final edging = rowEdgeAt(event.x, event.y);

				if (edging != hoverEdge) {
					hoverEdge = edging;
					invalidate();
				}

				final which = trackAt(event.y);

				if (which != hoverTrack) {
					hoverTrack = which;
					invalidate();
				}

				if (dragging == null) return false;

				if (sizing) {
					resized(dragging, tickAt(event.x));
					invalidate();
					return true;
				}

				final at = session.snapped(tickAt(event.x) - grabTick);
				dragging.at = at < 0 ? 0 : at;

				invalidate();
				return true;

			case Kind.PointerUp:
				if (reining != 0) {
					reining = 0;
					return true;
				}

				if (sizingRows >= 0) {
					sizingRows = -1;
					return true;
				}

				if (scrubbing) {
					scrubbing = false;
					return true;
				}

				if (dragging == null) return false;

				settled();
				return true;

			case Kind.KeyDown:
				return steered(event);

			case _:
		}

		return false;
	}

	public function scrubbed(px:Float):Void {
		final tick = session.snapped(tickAt(px));
		final want = tick < 0 ? 0 : tick;

		session.transport.seek(session.song.tempo.samplesAt(want));
		playhead = want;

		invalidate();
	}

	function pressed(event:Input):Bool {
		final which = trackAt(event.y);
		if (which < 0) return false;

		if (event.x < x + names()) return railed(which, event);

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
			sizing = onEdge(under, event.x);
			grabTick = sizing ? 0 : tickAt(event.x) - under.at;
			grabWasAt = under.at;
			grabWasLong = under.length;
			grabFresh = false;
			invalidate();
			return true;
		}

		final pattern = session.current();
		if (pattern == null) return true;

		if (which >= session.song.tracks.length) session.does(new AddTrack(which));

		final at = session.snapped(tickAt(event.x));
		final clip = new Clip(session.pattern, at < 0 ? 0 : at, pattern.length);

		session.does(new AddClip(which, clip));

		chosen = clip;
		chosenTrack = which;
		dragging = clip;
		sizing = true;
		grabTick = 0;
		grabWasAt = clip.at;
		grabWasLong = clip.length;
		grabFresh = true;

		invalidate();
		return true;
	}

	function settled():Void {
		final held = dragging;

		dragging = null;

		if (held == null || grabFresh) {
			sizing = false;
			grabFresh = false;
			session.changed();
			return;
		}

		if (sizing && held.length != grabWasLong) {
			final want = held.length;

			held.length = grabWasLong;
			session.does(new SizeClip(chosenTrack, held, want));
		} else if (!sizing && held.at != grabWasAt) {
			final want = held.at;

			held.at = grabWasAt;
			session.does(new MoveClip(chosenTrack, held, want, held.transpose));
		}

		sizing = false;
		session.changed();
	}

	function railed(which:Int, event:Input):Bool {
		if (event.button == Pointer.Right) {
			popped(which, event.x, event.y);
			return true;
		}

		if (which >= session.song.tracks.length) {
			session.does(new AddTrack(which));
			chosenTrack = which;
			invalidate();
			return true;
		}

		if (muteAt(event.x)) {
			final track = session.song.tracks[which];

			track.muted = !track.muted;
			session.say((track.muted ? "muted " : "unmuted ") + track.name);
			session.changed();
			invalidate();
			return true;
		}

		chosenTrack = which;
		invalidate();
		return true;
	}

	function popped(which:Int, px:Float, py:Float):Void {
		final root = root();
		if (root == null) return;

		final song = session.song;
		final menu = new Menu();
		final held = which < song.tracks.length ? song.tracks[which] : null;

		fires(menu.offer(new Choice(translate(Locale.TRACK_ADD))), function():Void {
			session.does(new AddTrack(song.tracks.length));
		});

		if (held != null) {
			final drives = new Menu();

			for (one in mdd.view.Parameter.of(session.part)) {
				if (!one.operators) {
					driven(drives, held, one, one.target, 0, px);
					continue;
				}

				final slots = new Menu();
				for (slot in 0...4) driven(slots, held, one, one.target, slot, px);

				drives.offer(new Choice(one.name)).submenu = slots;
			}

			menu.offer(new Choice(translate(Locale.TRACK_AUTOMATE)
				+ "  " + session.part.name())).submenu = drives;

			menu.divide();

			fires(menu.offer(new Choice(translate(Locale.TRACK_RENAME))), function():Void {
				if (onRename != null) onRename(which);
			});

			fires(menu.offer(new Choice(translate(held.muted
					? Locale.TRACK_UNMUTE : Locale.TRACK_MUTE))), function():Void {
				held.muted = !held.muted;
				session.changed();
			});

			menu.divide();

			final drop = menu.offer(new Choice(translate(Locale.TRACK_DELETE)));

			drop.enabled = song.tracks.length > 1;
			if (!drop.enabled) drop.reason = translate(Locale.TRACK_LAST);

			fires(drop, function():Void {
				session.does(new RemoveTrack(which));
				chosen = null;
				chosenTrack = -1;
			});
		}

		root.pop(menu, px, py, this);
	}

	function driven(into:Menu, track:mdd.song.Track, held:mdd.view.Parameter, target:Int,
			slot:Int, px:Float):Void {
		final one = into.offer(new Choice(held.titled(slot)));
		one.reason = translate(held.about);

		fires(one, function():Void {
			final bar = session.song.tempo.ppqn * 4;

			var at = session.snapped(tickAt(px));
			if (at < 0) at = 0;

			final made = mdd.song.Clip.drives(session.part, target, slot, at, bar * 2);
			final line = made.line;

			if (line != null) {
				line.add(new mdd.song.Point(0, 0));

				final tail = new mdd.song.Point(bar * 2, 0);
				line.points[0].shape = held.smooth ? mdd.song.Automation.LINEAR
					: mdd.song.Automation.HOLD;

				line.add(tail);
			}

			session.does(new mdd.song.edit.AddClip(session.song.tracks.indexOf(track), made));
			chosen = made;
			chosenTrack = session.song.tracks.indexOf(track);

			session.say(held.titled(slot) + "  " + session.part.name());
		});
	}

	function fires(choice:Choice, what:Void -> Void):Void {
		choice.onFire = function(chosen:Choice):Void {
			what();
			invalidate();
		};
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

		framed();

		paint.rect(x, y, width, height, theme.ground);
		painted = 0;

		final left = x + names();
		final top = y + ruler();

		paint.pushClip(left, top, width - names(), height - ruler());

		bars(paint, theme, metrics, left, top);
		clips(paint, theme, metrics);

		if (playhead >= 0) {
			final at = atTick(playhead);
			if (at >= left && at < x + width) {
				paint.rect(at, top, metrics.whole(2), height - ruler(), theme.warn, 0.9);
			}
		}

		paint.popClip();

		rails(paint, theme, metrics, top);
		heading(paint, theme, metrics, left);
		reins(paint, theme, metrics, left, top);

		paint.outline(x, y, width, height, theme.frame, metrics.whole(1));
	}

	var reining:Int = 0;

	function reinAt(px:Float, py:Float):Int {
		final thick = reinTall();

		if (py >= y + height - thick && px >= x + names()
			&& acrossReach() > width - names() + 0.5) return 1;

		if (px >= x + width - thick && py >= y + ruler()
			&& downReach() > height - ruler() + 0.5) return 2;

		return 0;
	}

	function reined(px:Float, py:Float):Void {
		if (reining == 1) {
			final wide = width - names();
			final held = span(wide, acrossReach());
			final room = wide - held;

			if (room <= 0) return;

			final want = (px - x - names() - held * 0.5) / room;
			scrollTo(want * (acrossReach() - wide));
			return;
		}

		final tall = height - ruler();
		final held = span(tall, downReach());
		final room = tall - held;

		if (room <= 0) return;

		final want = (py - y - ruler() - held * 0.5) / room;
		scrollDown(want * (downReach() - tall));
	}

	function span(across:Float, reach:Float):Float {
		final root = root();
		final least = root == null ? 24.0 : root.metrics.whole(24);
		final held = across * across / reach;

		return held < least ? least : held;
	}

	public function reinTall():Float {
		final root = root();
		return root == null ? 8 : root.metrics.whole(8);
	}

	public function acrossReach():Float {
		return session.song.ends() * perTick;
	}

	public function downReach():Float {
		return rows() * trackTall();
	}

	function reins(paint:Paint, theme:Theme, metrics:Metrics, left:Float,
			top:Float):Void {
		final thick = reinTall();
		final wide = width - names();
		final tall = height - ruler();

		if (acrossReach() > wide + 0.5) {
			final held = span(wide, acrossReach());
			final room = wide - held;
			final most = acrossReach() - wide;
			final at = most <= 0 ? 0 : offsetX / most * room;

			paint.rect(left, y + height - thick, wide, thick, theme.sink, 0.7);
			paint.roundedRect(left + at, y + height - thick + metrics.whole(2), held,
				thick - metrics.whole(4), metrics.whole(2), theme.frame);
		}

		if (downReach() > tall + 0.5) {
			final held = span(tall, downReach());
			final room = tall - held;
			final most = downReach() - tall;
			final at = most <= 0 ? 0 : offsetY / most * room;

			paint.rect(x + width - thick, top, thick, tall, theme.sink, 0.7);
			paint.roundedRect(x + width - thick + metrics.whole(2), top + at,
				thick - metrics.whole(4), held, metrics.whole(2), theme.frame);
		}
	}

	function bars(paint:Paint, theme:Theme, metrics:Metrics, left:Float, top:Float):Void {
		final bar = session.song.tempo.ppqn * 4;
		final hair = metrics.whole(1);
		final tall = trackTall();
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

		for (which in 0...rows()) {
			final row = atTrack(which);
			if (row + tall < top) continue;
			if (row > y + height) break;

			if (which >= session.song.tracks.length) {
				paint.rect(left, row, width - names(), tall, theme.sink, 0.35);
			} else if (which == hoverTrack) {
				paint.rect(left, row, width - names(), tall, theme.ink, 0.03);
			}

			paint.rect(left, row + tall - hair, width - names(), hair, theme.frame, 0.5);
		}
	}

	function clips(paint:Paint, theme:Theme, metrics:Metrics):Void {
		final font = metrics.small == null ? metrics.body : metrics.small;
		final tall = trackTall();
		final top = y + ruler();

		paint.reface(font);

		for (which in 0...session.song.tracks.length) {
			final track = session.song.tracks[which];
			final row = atTrack(which);

			if (row + tall < top) continue;
			if (row > y + height) break;

			for (clip in track.clips) {
				final at = atTick(clip.at);
				final wide = clip.length * perTick;

				if (at + wide < x + names() || at > x + width) continue;

				painted++;

				if (clip.drawn()) {
					curved(paint, theme, metrics, clip, at, row, wide, tall, track.muted);
					continue;
				}

				final pattern = session.song.patternAt(clip.pattern);
				final colour = pattern == null ? theme.part(clip.pattern % 11)
					: pattern.colour >= 0 ? new Colour(pattern.colour)
					: pattern.part >= 0 ? theme.part(pattern.part)
					: theme.part(clip.pattern % 11);

				paint.roundedGradient(at, row + 2, wide, tall - 5, metrics.radiusSmall,
					colour.lift(0.22), colour.sink(0.18), track.muted ? 0.3 : 0.75);

				if (clip == chosen) {
					paint.outline(at, row + 2, wide, tall - 5, theme.ink, metrics.whole(1));
				}

				final said = pattern == null ? "?" : pattern.name;
				final tail = clip.transpose == 0 ? ""
					: (clip.transpose > 0 ? "  +" + clip.transpose : "  " + clip.transpose);

				if (wide < metrics.whole(24)) continue;

				final inset = metrics.whole(2);
				final body = tall - 5 - inset * 2;

				paint.pushClip(at, row + 2, wide - metrics.unit, tall - 5);

				if (pattern != null && body >= metrics.whole(4)) {
					inked(paint, metrics, pattern, clip, colour.sink(0.5), at,
						row + 2 + inset, wide, body);
				}

				paint.text(said + tail, at + metrics.unit,
					row + 2 + (tall - 5 - font.height) * 0.5 + font.ascent, colour.sink(0.72));
				paint.popClip();
			}
		}
	}

	static inline final CURVE = 256;

	final curve:haxe.ds.Vector<Float> = new haxe.ds.Vector<Float>(CURVE * 2);

	function curved(paint:Paint, theme:Theme, metrics:Metrics, clip:Clip, at:Float,
			row:Float, wide:Float, tall:Float, quiet:Bool):Void {
		final line = clip.line;
		if (line == null) return;

		final part:mdd.song.Part = clip.part;
		final held = mdd.view.Parameter.found(part, line.target, line.slot);
		final colour = theme.part(clip.part);
		final font = metrics.small == null ? metrics.body : metrics.small;

		paint.roundedRect(at, row + 2, wide, tall - 5, metrics.radiusSmall, theme.raise1,
			quiet ? 0.4 : 0.9);

		paint.outline(at, row + 2, wide, tall - 5, colour, metrics.whole(1),
			clip == chosen ? 1 : 0.6);

		if (clip == chosen) {
			paint.outline(at, row + 2, wide, tall - 5, theme.ink, metrics.whole(1));
		}

		if (wide < metrics.whole(24) || held == null) return;

		final inset = metrics.whole(3);
		final top = row + 2 + inset;
		final room = tall - 5 - inset * 2;
		final span = held.high - held.low;

		if (room > metrics.whole(4) && span > 0 && line.points.length > 0) {
			paint.pushClip(at, row + 2, wide, tall - 5);

			var many = Std.int(wide / metrics.whole(3)) + 2;
			if (many > CURVE) many = CURVE;
			if (many < 2) many = 2;

			for (step in 0...many) {
				final tick = Std.int(clip.length * step / (many - 1));
				final value = line.valueAt(tick);
				final much = (value - held.low) / span;

				curve[step * 2] = at + wide * step / (many - 1);
				curve[step * 2 + 1] = top + room * (1 - (much < 0 ? 0 : (much > 1 ? 1 : much)));
			}

			paint.polyline(curve, many, metrics.whole(2), colour, quiet ? 0.4 : 0.95);
			paint.popClip();
		}

		paint.pushClip(at, row + 2, wide - metrics.unit, tall - 5);

		paint.text(part.name() + "  " + held.titled(line.slot), at + metrics.unit,
			row + 2 + metrics.unit + font.ascent, colour, quiet ? 0.4 : 0.85);

		paint.popClip();
	}

	static inline final MOST_NOTES = 2048;

	function inked(paint:Paint, metrics:Metrics, pattern:mdd.song.Pattern, clip:Clip,
			ink:Colour, left:Float, top:Float, wide:Float, tall:Float):Void {
		var low = 128;
		var high = -1;
		var counted = 0;

		for (index in 0...Part.COUNT) {
			for (note in pattern.lanes[index].notes) {
				if (note.at >= clip.length) continue;

				if (note.pitch < low) low = note.pitch;
				if (note.pitch > high) high = note.pitch;
				counted++;
			}
		}

		if (counted == 0 || high < low) return;

		if (high - low < 6) {
			final middle = (high + low) >> 1;
			low = middle - 3;
			high = middle + 3;
		}

		final span = high - low + 1;
		final hair = tall / span;
		final thick = hair < 1 ? 1 : (hair > metrics.whole(3) ? metrics.whole(3) : hair);
		final least = metrics.whole(1);

		var drawn = 0;

		for (index in 0...Part.COUNT) {
			for (note in pattern.lanes[index].notes) {
				if (note.at >= clip.length) continue;
				if (drawn >= MOST_NOTES) return;

				var length = note.length;
				if (note.at + length > clip.length) length = clip.length - note.at;

				final from = left + note.at * perTick;
				var run = length * perTick;
				if (run < least) run = least;

				if (from > left + wide) continue;

				final seat = top + (high - note.pitch) * hair;

				paint.rect(from, seat, run, thick, ink, 0.85);
				drawn++;
			}
		}
	}

	function rails(paint:Paint, theme:Theme, metrics:Metrics, top:Float):Void {
		final wide = names();
		final font = metrics.body;
		final small = metrics.small == null ? font : metrics.small;
		final tall = trackTall();
		final hair = metrics.whole(1);

		paint.rect(x, top, wide, height - ruler(), theme.panel);
		paint.pushClip(x, top, wide, height - ruler());

		for (which in 0...rows()) {
			final row = atTrack(which);
			if (row + tall < top) continue;
			if (row > y + height) break;

			final held = which < session.song.tracks.length
				? session.song.tracks[which] : null;

			if (which == chosenTrack) {
				paint.rect(x, row, wide, tall - hair, theme.accent, Theme.SELECT);
			} else if (which == hoverTrack) {
				paint.rect(x, row, wide, tall - hair, theme.accent, Theme.HOVER);
			}

			if (which == hoverEdge || which == sizingRows) {
				paint.rect(x, row + tall - hair * 2, wide, hair * 3, theme.accent, 0.9);
			} else {
				paint.rect(x, row + tall - hair, wide, hair, theme.frame, 0.5);
			}

			if (held == null) {
				paint.reface(small);
				paint.textCentred("+", x + wide * 0.5,
					row + (tall - small.height) * 0.5 + small.ascent, theme.dim, 0.5);
				continue;
			}

			paint.rect(x, row + metrics.unit, metrics.whole(3), tall - metrics.unit * 2 - hair,
				theme.part(which % 11), held.muted ? 0.25 : 0.9);

			final box = metrics.whole(18);
			final at = x + wide - metrics.whole(26);

			if (held.muted) {
				paint.roundedGradient(at, row + (tall - box) * 0.5, box, box,
					metrics.radiusSmall, theme.accent.lift(0.20), theme.accent.sink(0.16),
					0.8);
			} else {
				paint.roundedRect(at, row + (tall - box) * 0.5, box, box,
					metrics.radiusSmall, theme.raise1);
			}

			paint.reface(font);
			paint.text(held.name, x + metrics.inset + metrics.gap,
				row + (tall - font.height) * 0.5 + font.ascent,
				held.muted ? theme.dim : theme.ink);

			paint.reface(small);
			paint.textCentred("M", at + box * 0.5,
				row + (tall - small.height) * 0.5 + small.ascent,
				held.muted ? theme.ink : theme.dim);
		}

		paint.popClip();
		paint.rect(x + wide - hair, top, hair, height - ruler(), theme.frame);
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
