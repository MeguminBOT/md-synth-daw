package mdd.view.film;

import mdd.app.Session;
import mdd.song.Part;
import mdd.ui.Input;
import mdd.ui.Key;
import mdd.ui.Kind;
import mdd.ui.Metrics;
import mdd.ui.Paint;
import mdd.ui.Widget;
import mdd.ui.control.Picker;
import mdd.view.monitor.Scope;

/**
	The video style editor: the preview on the left and what the style is set to on the right,
	in a window of its own beside the main one, or filling the main one where there is only one.

	It edits the style it is given in place, so the next video is drawn from whatever it shows, and
	it says every change it settles on through `onChange` so the style is kept. The song is not
	rendered for it: `scope` is fed by playback, and `onPlay` and `onStop` start and stop that.

	Undo and redo are its own, over the style alone, because the style is not part of the piece:
	each change it settles on is kept as the style's JSON before it, and Ctrl+Z and Ctrl+Y walk
	them.
**/
@:unreflective
final class Studio extends Widget {
	/**
		Which picture is being asked for: the one filling the ground.
	**/
	public static inline final GROUND_PICTURE = 0;

	/**
		Which picture is being asked for: one to place as a layer of its own.
	**/
	public static inline final LAYER_PICTURE = 1;

	/**
		Which picture is being asked for: a new one for the chosen picture layer.
	**/
	public static inline final SWAP_PICTURE = 2;

	/**
		How many changes are kept to be undone.
	**/
	static inline final KEPT = 100;

	/**
		The session whose song is shown.
	**/
	public final session:Session;

	/**
		The style being edited.
	**/
	public var style(default, null):Style;

	/**
		The scope the preview draws, fed by playback. It is in the tree so it takes the window's
		sizes, and never drawn itself.
	**/
	public final scope:Scope;

	/**
		The preview.
	**/
	public final preview:Preview;

	/**
		What the style is set to.
	**/
	public final panel:Styling;

	/**
		The colour picker the panel raises.
	**/
	public final picker:Picker;

	/**
		How wide the video is drawn, which the preview keeps the shape of.
	**/
	public var pictureWide:Int = 1920;

	/**
		How tall.
	**/
	public var pictureTall:Int = 1080;

	/**
		The face a line of text is written in where it names none that will read.
	**/
	public var face:String = "";

	/**
		Which layer is chosen, by index into the style's layers, or -1 for none.
	**/
	public var chosen(default, null):Int = 0;

	/**
		Called when a change to the style settles, so it can be kept.
	**/
	public var onChange:Null<Void -> Void> = null;

	/**
		Called with `Scope.WAVEFORM` or `Scope.SPECTRUM` when the preview is switched between them,
		so the video shows the same.
	**/
	public var onView:Null<Int -> Void> = null;

	/**
		Called to start playback.
	**/
	public var onPlay:Null<Void -> Void> = null;

	/**
		Called to stop it.
	**/
	public var onStop:Null<Void -> Void> = null;

	/**
		Called to ask for a picture file, with which one it is for: `GROUND_PICTURE`,
		`LAYER_PICTURE` or `SWAP_PICTURE`. The answer comes back through `picked`.
	**/
	public var onPick:Null<Int -> Void> = null;

	/**
		Called for sizes to draw a picture of a height at, dressed in faces baked for it, or null
		where there are none.
	**/
	public var onSizes:Null<Int -> Null<Metrics>> = null;

	/**
		Called for the names of the styles that have been saved.
	**/
	public var onStyles:Null<Void -> Array<String>> = null;

	/**
		Called to save the style under a name.
	**/
	public var onSave:Null<String -> Void> = null;

	/**
		Called to replace the style with a saved one, by name.
	**/
	public var onLoad:Null<String -> Void> = null;

	/**
		Called to delete a saved style, by name.
	**/
	public var onDelete:Null<String -> Void> = null;

	/**
		The fonts installed on this machine, read the first time the font menu opens.
	**/
	public var installed(default, null):Null<mdd.host.Installed> = null;

	final undos:Array<String> = [];
	final redos:Array<String> = [];
	var settled:String;

	/**
		Builds the editor over a style, which it edits in place.

		@param session The session whose song is shown.
		@param style The style.
	**/
	public function new(session:Session, style:Style) {
		super();

		this.session = session;
		this.style = style;

		focusable = true;
		opaque = true;

		scope = new Scope(session);
		scope.visible = false;
		add(scope);

		preview = new Preview(this);
		add(preview);

		panel = new Styling(this);
		add(panel);

		picker = new Picker();
		settled = style.spelt();
	}

	/**
		@return The layer chosen, or null for none.
	**/
	public function chosenLayer():Null<Layer> {
		return chosen < 0 || chosen >= style.layers.length ? null : style.layers[chosen];
	}

	/**
		Chooses a layer.

		@param index By index into the style's layers, or -1 for none.
	**/
	public function chooses(index:Int):Void {
		chosen = index < 0 || index >= style.layers.length ? -1 : index;
		panel.follows();
		invalidate();
	}

	/**
		Says the style changed. A change that has not settled, one step of a drag, redraws and
		nothing more; one that has is kept for undo and passed on to be kept.

		@param settles Whether the change has settled.
	**/
	public function changed(settles:Bool):Void {
		preview.invalidate();

		if (!settles) return;

		final now = style.spelt();

		if (now != settled) {
			undos.push(settled);
			if (undos.length > KEPT) undos.shift();

			redos.resize(0);
			settled = now;

			if (onChange != null) onChange();
		}

		panel.follows();
	}

	/**
		Replaces the whole style, as loading a saved one does. It is one step to undo like any
		other.

		@param next The style to show.
	**/
	public function restyles(next:Style):Void {
		takes(next);
		changed(true);
	}

	function takes(next:Style):Void {
		style.name = next.name;
		style.ground = next.ground;
		style.groundColour = next.groundColour;
		style.groundTo = next.groundTo;
		style.groundTurn = next.groundTurn;
		style.groundImage = next.groundImage;
		style.groundAlpha = next.groundAlpha;

		style.layers.resize(0);
		for (layer in next.layers) style.layers.push(layer);

		for (part in 0...Part.COUNT) style.colours[part] = next.colours[part];

		style.names = next.names;
		style.grid = next.grid;
		style.weight = next.weight;
		style.windowing = next.windowing;
		style.smoothing = next.smoothing;
		style.smoothingWidth = next.smoothingWidth;

		if (chosen >= style.layers.length) chosen = style.layers.length - 1;
	}

	/**
		Takes the last settled change back.

		@return False where there was nothing to undo.
	**/
	public function undo():Bool {
		if (undos.length == 0) return false;

		redos.push(settled);
		settled = undos.pop();
		takes(Style.read(settled));

		preview.invalidate();
		panel.follows();

		if (onChange != null) onChange();
		return true;
	}

	/**
		Puts back the last change undone.

		@return False where there was nothing to redo.
	**/
	public function redo():Bool {
		if (redos.length == 0) return false;

		undos.push(settled);
		settled = redos.pop();
		takes(Style.read(settled));

		preview.invalidate();
		panel.follows();

		if (onChange != null) onChange();
		return true;
	}

	/**
		Takes a picture file that was asked for.

		@param what Which picture it is for: `GROUND_PICTURE`, `LAYER_PICTURE` or `SWAP_PICTURE`.
		@param path The file.
	**/
	public function picked(what:Int, path:String):Void {
		preview.forgets(path);

		switch (what) {
			case GROUND_PICTURE:
				style.groundImage = path;

			case SWAP_PICTURE:
				final layer = chosenLayer();
				if (layer == null || layer.kind != Layer.IMAGE) return;

				layer.path = path;

			case _:
				final layer = new Layer(Layer.IMAGE);

				layer.path = path;
				layer.wide = 0.25;
				layer.tall = 0.25;

				style.layers.push(layer);
				chosen = style.layers.length - 1;
				shaped(layer);
		}

		changed(true);
	}

	/**
		Gives a picture layer the shape of its picture, keeping its width.

		@param layer The layer.
	**/
	public function shaped(layer:Layer):Void {
		final aspect = preview.aspect(layer.path);
		if (aspect <= 0) return;

		layer.tall = layer.wide * pictureWide / aspect / pictureTall;
		layer.tidied();
	}

	/**
		Adds a line of text over everything, in the middle of the picture, and chooses it.

		@param said What it says.
	**/
	public function writes(said:String):Void {
		final layer = new Layer(Layer.TEXT);

		layer.text = said;
		layer.tall = 0.08;

		style.layers.push(layer);
		chosen = style.layers.length - 1;

		changed(true);
	}

	/**
		@return The parts the lanes lay out together in the song as it is now: those shown that have
			no lane of their own.
	**/
	public function gathered():Array<Int> {
		final out:Array<Int> = [];
		style.gathered(parts(), out);
		return out;
	}

	/**
		Takes every lane the lanes lay out together out on its own, each placed exactly where it
		sat, turned and faded as the lanes were, so nothing on the picture moves, and chooses one of
		them. It is one step to undo.

		Every lane comes out at once rather than only the one asked for, because the rest would
		otherwise be laid out again to fill the gap and jump.

		@param part The part to choose.
		@return The layer that now places that part, or null where the lanes do not show it.
	**/
	public function detaches(part:Int):Null<Layer> {
		final held = style.lone(part);
		if (held != null) return held;

		final together = gathered();
		if (together.indexOf(part) < 0) return null;

		final lanes = style.lanes();
		final at = style.layers.indexOf(lanes);
		final boxWide = lanes.wide * pictureWide;
		final boxTall = lanes.tall * pictureTall;
		final turn = lanes.turn * Math.PI / 180;
		final cell = new haxe.ds.Vector<Float>(4);

		var wanted:Null<Layer> = null;

		for (index in 0...together.length) {
			Scope.cellOf(together.length, index, cell);

			final along = (cell[0] + cell[2] * 0.5 - 0.5) * boxWide;
			final across = (cell[1] + cell[3] * 0.5 - 0.5) * boxTall;
			final lane = new Layer(Layer.LANE);

			lane.part = together[index];
			lane.x = lanes.x + (along * Math.cos(turn) - across * Math.sin(turn)) / pictureWide;
			lane.y = lanes.y + (along * Math.sin(turn) + across * Math.cos(turn)) / pictureTall;
			lane.wide = cell[2] * lanes.wide;
			lane.tall = cell[3] * lanes.tall;
			lane.turn = lanes.turn;
			lane.alpha = lanes.alpha;
			lane.tidied();

			style.layers.insert(at + 1 + index, lane);
			if (lane.part == part) wanted = lane;
		}

		if (wanted != null) chosen = style.layers.indexOf(wanted);

		changed(true);
		return wanted;
	}

	/**
		Puts every lane placed on its own back with the rest, and chooses the lanes.
	**/
	public function gathers():Void {
		var index = style.layers.length - 1;

		while (index >= 0) {
			if (style.layers[index].kind == Layer.LANE) style.layers.splice(index, 1);
			index--;
		}

		chosen = style.layers.indexOf(style.lanes());
		changed(true);
	}

	/**
		Shows the waveform or the spectrum in the lanes, and says so.

		@param which `Scope.WAVEFORM` or `Scope.SPECTRUM`.
	**/
	public function views(which:Int):Void {
		scope.shows(which);
		if (onView != null) onView(which);

		preview.invalidate();
		panel.follows();
	}

	/**
		Moves the chosen layer up or down the order it is drawn in.

		@param by One to draw it later, over what was above it, or minus one to draw it earlier.
	**/
	public function reorders(by:Int):Void {
		final to = chosen + by;
		if (chosen < 0 || to < 0 || to >= style.layers.length) return;

		final held = style.layers[chosen];

		style.layers[chosen] = style.layers[to];
		style.layers[to] = held;
		chosen = to;

		changed(true);
	}

	/**
		Takes the chosen layer out, unless it is the lanes, which a style always has.
	**/
	public function removes():Void {
		final layer = chosenLayer();
		if (layer == null || layer.kind == Layer.LANES) return;

		style.layers.splice(chosen, 1);
		chosen = chosen >= style.layers.length ? style.layers.length - 1 : chosen;

		changed(true);
	}

	/**
		@return The fonts installed on this machine, read the first time they are asked for.
	**/
	public function fonts():mdd.host.Installed {
		final held = installed;
		if (held != null) return held;

		final found = mdd.host.Installed.found();
		installed = found;

		return found;
	}

	/**
		@return What the placeholders stand for in the song as it is now.
	**/
	public function words():Words {
		final root = root();
		return root == null ? Words.none() : Words.of(session.song, Words.key(session.scale,
			session.notation, root));
	}

	/**
		@return Which parts the lanes show: those the song carries, or all of them where it
			carries none.
	**/
	public function parts():Array<Int> {
		final out:Array<Int> = [];
		final song = session.song;

		for (index in 0...Part.COUNT) if (song.carries(index)) out.push(index);
		if (out.length == 0) for (index in 0...Part.COUNT) out.push(index);

		return out;
	}

	/**
		Gives back what the preview drew with, which closing the window needs.
	**/
	public function shut():Void {
		preview.shut();
	}

	override function measure(availableWidth:Float, availableHeight:Float):Void {
		wantWidth = availableWidth;
		wantHeight = availableHeight;
	}

	override function layout():Void {
		final root = root();
		final wide = root == null ? 340 : root.metrics.whole(340);
		final split = width - wide;

		preview.arrange(x, y, split < 0 ? 0 : split, height);
		panel.arrange(x + (split < 0 ? 0 : split), y, wide, height);
		scope.arrange(0, 0, 1, 1);
	}

	override function took(event:Input):Bool {
		if (event.kind != Kind.KeyDown) return false;

		final ctrl = event.ctrl();
		final shift = event.shift();

		if (ctrl && event.code == Key.Z) return shift ? redo() : undo();
		if (ctrl && event.code == Key.Y) return redo();
		if (ctrl) return false;

		final layer = chosenLayer();
		if (layer == null || root().focus != preview) return false;

		final step = shift ? 10 : 1;

		switch (event.code) {
			case Key.Delete, Key.Backspace:
				removes();
				return true;

			case Key.Left: layer.x -= step / preview.pictureWide;
			case Key.Right: layer.x += step / preview.pictureWide;
			case Key.Up: layer.y -= step / preview.pictureTall;
			case Key.Down: layer.y += step / preview.pictureTall;
			case _: return false;
		}

		changed(true);
		return true;
	}

	override function paint(paint:Paint):Void {
		final root = root();
		if (root == null) return;

		paint.rect(x, y, width, height, root.theme.panel);
		super.paint(paint);
	}
}
