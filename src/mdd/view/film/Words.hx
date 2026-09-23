package mdd.view.film;

import mdd.song.Scale;
import mdd.song.Song;
import mdd.ui.Root;

/**
	What a text layer's placeholders stand for: the piece's description, its tempo and its key,
	each written `{name}` in the text, `{title}` or `{bpm}` for instance.

	A placeholder whose value is empty reads as nothing, and anything in braces that names none
	of them is left as it was typed.
**/
@:unreflective
final class Words {
	/**
		The placeholders, in the order their values are held: the piece's eight descriptions in
		`Song`'s order, then the tempo and the key.
	**/
	public static final NAMES:Array<String> = ["title", "artist", "composer", "album", "year",
		"genre", "track", "comment", "bpm", "key"];

	final values:Array<String> = [];

	function new() {}

	/**
		@param song The piece.
		@param key The key, written out, or an empty string where it has none.
		@return What the placeholders stand for in it.
	**/
	public static function of(song:Song, key:String):Words {
		final out = new Words();

		for (which in 0...Song.DESCRIPTIONS) out.values.push(song.described(which));

		final beats = song.tempo.beatsAt(0);
		final whole = Math.round(beats);

		out.values.push(Math.abs(beats - whole) < 0.005 ? "" + whole : "" + Math.round(beats * 10) / 10);
		out.values.push(key);

		return out;
	}

	/**
		@param scale The key the piano roll is set to.
		@param notation How notes are written, one of `mdd.song.Notation`'s styles.
		@param root Where the scale's name is translated.
		@return The key written out, such as "A Natural minor", or an empty string where the scale
			is chromatic and so names none.
	**/
	public static function key(scale:Scale, notation:Int, root:Root):String {
		if (scale.kind == Scale.CHROMATIC) return "";
		return Scale.rootOf(scale.root, notation) + " " + root.translate(mdd.view.Scales.NAMES[scale.kind]);
	}

	/**
		@return Words in which every placeholder stands for nothing.
	**/
	public static function none():Words {
		final out = new Words();
		for (name in NAMES) out.values.push("");
		return out;
	}

	/**
		@param text What a text layer says.
		@return It with every placeholder replaced by what it stands for. It allocates only where
			the text has a brace in it.
	**/
	public function filled(text:String):String {
		if (text.indexOf("{") < 0) return text;

		var out = text;

		for (index in 0...NAMES.length) {
			out = StringTools.replace(out, "{" + NAMES[index] + "}", values[index]);
		}

		return out;
	}
}
