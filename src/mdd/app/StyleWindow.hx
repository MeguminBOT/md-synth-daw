package mdd.app;

import mdd.host.Chooser;
import mdd.host.Dialog;
import mdd.host.Event;
import mdd.host.Paths;
import mdd.view.film.Studio;
import mdd.view.film.Style;

/**
	The video style editor in a window of its own beside the main one: the window, the studio that
	fills it, the picture it is asking for and the folder saved styles are kept in.

	The main loop hands it the events that belong to its window and asks it to draw once a frame;
	it asks for nothing else. Its studio edits the style it is given in place, the one the next
	video is drawn from, and every change it settles on is written into the settings so the style
	is still there the next time the application starts.

	Saved styles are files in a `styles` folder beside the settings, one a style, named for it.
**/
@:unreflective
final class StyleWindow {
	/**
		What a saved style's file ends in.
	**/
	public static inline final SUFFIX = ".mdstyle";

	/**
		The window and everything drawn in it.
	**/
	public final stage:Stage;

	/**
		The editor filling it.
	**/
	public final studio:Studio;

	var chooser:cpp.Star<Chooser> = null;
	var picking:Int = -1;
	var settings:Null<mdd.host.Settings> = null;

	function new(stage:Stage, studio:Studio) {
		this.stage = stage;
		this.studio = studio;
	}

	/**
		Opens the editor in a window of its own, dressed the way the main one is.

		@param main The main window, whose theme, colours, language and faces it takes.
		@param session The session whose song is shown.
		@param style The style to edit, in place.
		@param video The video export's sheet, whose size, lanes and speed the preview takes and
			whose waveform or spectrum it sets.
		@param settings Where a settled style is written, or null.
		@return The editor's window, or null where the window would not open.
	**/
	public static function opened(main:Stage, session:Session, style:Style,
			video:mdd.view.overlay.Export, settings:Null<mdd.host.Settings>):Null<StyleWindow> {
		final studio = new Studio(session, style);
		final stage = new Stage();
		final mixing = video.mixing;

		stage.driver = main.driver;
		stage.typeface = main.typeface;
		stage.textScale = main.textScale;

		studio.pictureWide = mixing.wide();
		studio.pictureTall = mixing.tall();
		studio.face = main.sans();
		studio.scope.shows(mixing.scopeView);
		studio.scope.paces(mixing.scopeSpeed);
		studio.scope.refines(mixing.scopeAccuracy);
		studio.onView = function(which:Int):Void video.viewed(which);

		final title = main.root.translate(Locale.FILM_TITLE);
		if (!stage.opensAside(studio, title, 1280, 820)) return null;

		stage.root.theme.wear(main.root.theme.which);
		stage.root.theme.chooses(main.root.theme.palette);
		stage.root.flow = main.root.flow;
		Languages.speak(stage.root.translation, main.root.translation.language);

		final out = new StyleWindow(stage, studio);
		out.settings = settings;
		out.wires();

		stage.measured();
		stage.root.reshape();
		stage.draw(false);
		stage.show(false);

		return out;
	}

	function wires():Void {
		studio.onChange = function():Void kept();
		studio.onPick = function(what:Int):Void asks(what);
		studio.onSizes = function(tall:Int):Null<mdd.ui.Metrics> return stage.bakes(tall / Filming.DESIGNED);
		studio.onUnsized = function(sizes:mdd.ui.Metrics):Void stage.shuts(sizes);
		studio.onStyles = function():Array<String> return saved();
		studio.onSave = function(name:String):Void saves(name);
		studio.onLoad = function(name:String):Void loads(name);
		studio.onDelete = function(name:String):Void deletes(name);
	}

	/**
		Takes an event that belongs to this window.

		@param event The event.
		@return False where it was the window closing, after which it is to be shut.
	**/
	public function took(event:Event):Bool {
		return stage.took(event);
	}

	/**
		Moves time on, follows a picture being chosen, and draws where anything changed.

		@param since How long since the last frame, in seconds.
		@param playing Whether the song is playing, which redraws the preview every frame.
		@return Whether a frame was drawn.
	**/
	public function frame(since:Float, playing:Bool):Bool {
		stage.root.advance(since);
		polled();

		if (playing) studio.preview.invalidate();

		return stage.draw(false);
	}

	/**
		Gives back the window, the preview's textures and a dialog left open.
	**/
	public function shut():Void {
		if (chooser != null) Dialog.close(chooser);

		chooser = null;
		studio.shut();
		stage.shut();
	}

	/**
		Writes the style into the settings.
	**/
	function kept():Void {
		final held = settings;
		if (held == null) return;

		held.put("style", studio.style.spelt());
		held.save();
	}

	/**
		Opens a dialog for a picture. The answer is followed by `polled`.

		@param what Which picture it is for, one of `Studio`'s.
	**/
	function asks(what:Int):Void {
		if (chooser != null) return;

		picking = what;
		chooser = Dialog.open(stage.window, "png, jpeg", "png;jpg;jpeg", Paths.within("projects"));
	}

	function polled():Void {
		if (chooser == null) return;

		final state = Dialog.state(chooser);
		if (state == Dialog.WAITING) return;

		final where = state == Dialog.CHOSEN ? (Dialog.path(chooser) : String) : "";

		Dialog.close(chooser);
		chooser = null;

		if (where != "") studio.picked(picking, where);
	}

	/**
		@return The folder saved styles are kept in, made where it is not there.
	**/
	static function folder():String {
		return Paths.within("styles");
	}

	/**
		@return The names of the styles saved, sorted.
	**/
	function saved():Array<String> {
		final out:Array<String> = [];
		final held:Array<String> = try sys.FileSystem.readDirectory(folder()) catch (e:Dynamic) [];

		for (name in held) {
			if (StringTools.endsWith(name.toLowerCase(), SUFFIX)) out.push(name.substr(0, name.length - SUFFIX.length));
		}

		out.sort(function(one:String, two:String):Int return mdd.Names.inOrder(one, two));
		return out;
	}

	/**
		@param name A style's name.
		@return The file it is saved in, the name made safe for a file.
	**/
	static function fileOf(name:String):String {
		final safe = new StringBuf();

		for (index in 0...name.length) {
			final code = name.charCodeAt(index);
			final bad = code == null || code < 32 || "\\/:*?\"<>|".indexOf(name.charAt(index)) >= 0;
			safe.add(bad ? "_" : name.charAt(index));
		}

		final said = StringTools.trim(safe.toString());
		return folder() + "/" + (said == "" ? "style" : said) + SUFFIX;
	}

	function saves(name:String):Void {
		try {
			sys.io.File.saveContent(fileOf(name), studio.style.spelt());
		} catch (e:Dynamic) {}
	}

	function loads(name:String):Void {
		final said = try sys.io.File.getContent(fileOf(name)) catch (e:Dynamic) "";
		if (said != "") studio.restyles(Style.read(said));
	}

	function deletes(name:String):Void {
		try {
			sys.FileSystem.deleteFile(fileOf(name));
		} catch (e:Dynamic) {}
	}
}
