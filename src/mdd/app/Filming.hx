package mdd.app;

import haxe.io.Bytes;
import mdd.host.Draw;
import mdd.host.Sdl;
import mdd.host.Texture;
import mdd.host.Video;
import mdd.host.VideoFile;
import mdd.play.Mixdown;
import mdd.play.Mixing;
import mdd.play.Render;
import mdd.play.Sequencer;
import mdd.play.Stream;
import mdd.song.Part;
import mdd.song.Song;
import mdd.song.Tempo;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Root;
import mdd.view.monitor.Scope;

@:unreflective

/**
	Draws the scope over a finished mix, a frame at a time, into a WebM file.

	The mix has already been rendered, faded and levelled by the time this starts, so the audio
	in the video is exactly the audio an export with the same settings writes. The scope is fed by
	a second render of the same register stream, which gives it every part on its own the way the
	live scope sees them, and it is a scope of its own, sized to the picture and set to the speed,
	accuracy and view of the one on screen. It draws in sizes and faces made for the picture, so a
	taller picture carries the same scope drawn larger rather than a small one with room around it.

	Drawing needs the thread that owns the window, so `step` draws as many frames as fit in the
	time it is given and hands back, and the encoding runs on a thread inside the writer. Nothing
	here is safe to call from any other thread.
**/
final class Filming {
	/**
		How long the render the scope reads runs before the piece starts, which is how long the
		mix itself lets the output stage settle.
	**/
	static inline final SETTLE = 0.100;

	/**
		The picture height the scope's design sizes are drawn at one to one. A taller picture draws
		them larger by the same proportion.
	**/
	public static inline final DESIGNED = 720;

	/**
		Where the video is written.
	**/
	public final path:String;

	/**
		The sizes the scope is drawn at, which the caller made for the picture and gives back once
		`finish` has run.
	**/
	public final sizes:Metrics;

	/**
		How many frames the video holds once it is finished.
	**/
	public final frames:Int;

	/**
		How many frames have been drawn.
	**/
	public var done(default, null):Int = 0;

	/**
		Whether it was stopped before the last frame.
	**/
	public var stopped(default, null):Bool = false;

	final root:Root;
	final paint:Paint;
	final made:Mixdown;
	final scope:Scope;
	final pixels:Bytes;
	final render:Render;
	final stream:Stream;
	final wide:Int;
	final tall:Int;
	final fps:Int;
	final ahead:Int;

	var wrong:String = "";
	var target:cpp.Star<Texture> = null;
	var file:cpp.Star<VideoFile> = null;
	var fed:Int = 0;
	var taken:Int = 0;
	var bytes:Int = 0;
	var finished:Bool = false;

	/**
		Sets up the render the scope reads, the scope, the texture it is drawn into and the file.
		A fault in any of them is kept and said by `finish`, and `step` then draws nothing.

		@param root The root the scope borrows its theme and sizes from.
		@param paint What the window is drawn with, which the frames are drawn with too.
		@param sizes The sizes to draw the scope at, dressed in faces baked for the picture.
		@param live The scope on screen, whose settings the video takes.
		@param song The piece.
		@param mixing The export settings.
		@param made The finished mix.
		@param path Where to write the video.
	**/
	public function new(root:Root, paint:Paint, sizes:Metrics, live:Scope, song:Song, mixing:Mixing,
			made:Mixdown, path:String) {
		this.root = root;
		this.paint = paint;
		this.sizes = sizes;
		this.made = made;
		this.path = path;

		wide = mixing.wide();
		tall = mixing.tall();
		fps = mixing.fps;
		ahead = Math.round(mixing.padStart * made.rate);

		frames = made.rate <= 0 ? 0 : Math.ceil(made.frames * fps / made.rate);
		pixels = Bytes.alloc(wide * tall * 4);

		final span = song.tempo.samplesAt(song.ends());

		stream = new Stream(Mixdown.roomFor(span));
		new Sequencer(song).spanned(stream, 0, span);

		render = new Render(made.rate, Render.BLOCK);
		render.console = mixing.console;

		var warmed = 0;
		final warming = Std.int(made.rate * SETTLE);

		while (warmed < warming) {
			final took = render.fill(Render.BLOCK);
			if (took <= 0) break;

			warmed += took;
		}

		taken = render.tapped;

		scope = new Scope(live.session);
		scope.paces(live.speed);
		scope.refines(live.accuracy);
		scope.shows(live.showing);
		scope.rated(made.rate);
		scope.visible = false;

		root.top.add(scope);

		final worn = root.wears(sizes);
		scope.arrange(0, 0, wide, tall);
		root.wears(worn);

		target = Draw.createTarget(paint.canvas(), wide, tall);

		file = Video.open(path, wide, tall, fps, mixing.kilobits(), mixing.rateControl,
			mixing.qualityLevel, mixing.encoderSpeed, mixing.keyframeInterval, mixing.screen ? 1 : 0,
			made.rate, made.channels, mdd.format.Coded.BITRATES[mixing.quality], 0);

		if (target == null) wrong = "no texture could be made to draw the video into";
		else if (file == null) wrong = "the video file would not open: " + path;
	}

	/**
		Draws frames until the time given is used up or the video is done.

		@param budget How long it may take, in seconds.
		@return Whether frames are left to draw.
	**/
	public function step(budget:Float):Bool {
		if (finished || stopped || wrong != "") return false;

		final began = Sdl.ticks();

		while (done < frames) {
			framed(done);
			done++;

			if (wrong != "" || Sdl.ticks() - began >= budget) break;
		}

		return done < frames && wrong == "";
	}

	/**
		Stops before the last frame. `finish` still has to be called to close the file.
	**/
	public function stops():Void {
		stopped = true;
	}

	/**
		@return How far through the frames it is, nought to one.
	**/
	public function reach():Float {
		return frames <= 0 ? 1 : done / frames;
	}

	/**
		@return How long the video runs, in seconds.
	**/
	public function seconds():Float {
		return made.rate <= 0 ? 0 : made.frames / made.rate;
	}

	/**
		@return How big the finished file is, in bytes, or nought before `finish`.
	**/
	public function size():Int {
		return bytes;
	}

	/**
		Closes the file, gives the texture back and takes the scope out of the root. Safe to call
		more than once.

		@return What went wrong, or an empty string where nothing did.
	**/
	public function finish():String {
		if (finished) return wrong;

		finished = true;

		if (file != null) {
			if (Video.close(file) != 0 && wrong == "" && !stopped) {
				wrong = "the video file could not be finished";
			}

			file = null;
		}

		if (target != null) {
			Draw.destroyTexture(target);
			target = null;
		}

		root.top.remove(scope);

		if (sys.FileSystem.exists(path)) bytes = sys.FileSystem.stat(path).size;

		return wrong;
	}

	/**
		Hands one frame's audio to the file, feeds the scope up to the end of that frame, draws it,
		and hands the picture to the file.

		@param frame Which frame.
	**/
	function framed(frame:Int):Void {
		final rate = made.rate;
		final start = Math.round(frame * rate / fps);
		final end = Math.round((frame + 1) * rate / fps);
		final until = end > made.frames ? made.frames : end;

		if (until > start) {
			final samples = cpp.Pointer.arrayElem(made.samples.toData(), start * made.channels);

			if (Video.audio(file, samples.constRaw, until - start) != 0) {
				wrong = "the audio could not be written into the video";
				return;
			}
		}

		poured(until > start ? until : start);
		drawn();

		if (Video.frame(file, cpp.Pointer.arrayElem(pixels.getData(), 0).constRaw) != 0) {
			wrong = "a frame could not be written into the video";
		}
	}

	/**
		Feeds the scope every sample up to a place in the mix: silence for the padding before the
		piece, and after it every part as the render made it.

		@param until Where to feed up to, counted in samples of the mix.
	**/
	function poured(until:Int):Void {
		final rate = made.rate;

		while (fed < until) {
			if (fed < ahead) {
				final quiet = (until < ahead ? until : ahead) - fed;

				for (step in 0...quiet) {
					for (part in 0...Part.COUNT) scope.feed(part, 0);
				}

				fed += quiet;
				continue;
			}

			final count = until - fed < Render.BLOCK ? until - fed : Render.BLOCK;
			final from = Std.int((fed - ahead) * (Tempo.TICKS / rate));
			final took = render.serve(stream, from, count, 0);

			if (took <= 0) break;

			while (taken < render.tapped) {
				final slot = taken % Render.TAPS;

				for (part in 0...Part.COUNT) {
					scope.feed(part, render.taps[part * Render.TAPS + slot]);
				}

				taken++;
			}

			fed += took;
		}
	}

	/**
		Draws the scope into the texture and reads the picture back.
	**/
	function drawn():Void {
		final renderer = paint.canvas();
		final ground = root.theme.ground;
		final worn = root.wears(sizes);
		final face = paint.font;

		Draw.setTarget(renderer, target);
		Sdl.renderClear(renderer, ground.red / 255, ground.green / 255, ground.blue / 255, 1);

		paint.reset();
		scope.paint(paint);
		paint.flush();

		Draw.readPixels(renderer, 0, 0, wide, tall, cpp.Pointer.arrayElem(pixels.getData(), 0).raw);
		Draw.setTarget(renderer, null);

		paint.reface(face);
		root.wears(worn);
	}
}
