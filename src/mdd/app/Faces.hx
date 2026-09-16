package mdd.app;

import mdd.host.Atomic;
import mdd.host.Paths;
import sys.FileSystem;
import sys.io.File;

@:unreflective

/**
	The faces one language needs and nothing else does, which an installer may have left
	out, and the download that puts one back.

	A language whose face is present in neither the install nor the userdata folder still
	appears in the language lists, with the size of what picking it downloads. Picking it
	is the consent: nothing reaches the network before that.

	The face is fetched from the commit the build file pins it to and checked against the
	SHA-256 pinned beside it before it is put where anything reads it, so the file that
	lands is byte for byte the one a full install ships. It is written under a partial name
	first, so a download that stops halfway is never taken for a face.
**/
final class Faces {
	/**
		Nothing is being fetched.
	**/
	public static inline final IDLE = 0;

	/**
		A face is on its way.
	**/
	public static inline final FETCHING = 1;

	/**
		A face arrived, matched its pin, and is in place.
	**/
	public static inline final FETCHED = 2;

	/**
		The download did not complete.
	**/
	public static inline final UNREACHABLE = 3;

	/**
		Something arrived and it was not the pinned file, so it was deleted.
	**/
	public static inline final BROKEN = 4;

	static inline final PARTIAL = ".part";

	/**
		The folder the install ships its faces in.
	**/
	public final installed:String;

	/**
		The folder a fetched face is kept in. It is not made until a face is fetched into it.
	**/
	public final kept:String;

	/**
		Which language the running download, or the last one to finish, was for.
	**/
	public var language(default, null):String = "";

	final held:Atomic = new Atomic(IDLE);

	var partial:String = "";
	var expected:Int = 0;

	/**
		@param installed The folder the install ships its faces in.
		@param kept The folder a fetched face goes in, which is made only when one is.
	**/
	public function new(installed:String, kept:String) {
		this.installed = installed;
		this.kept = kept;
	}

	/**
		@return Where a face this copy fetches is kept: a folder of its own under the
			userdata folder, because an installed copy's own folder is not written to.
	**/
	public static function keptFolder():String {
		return Paths.userdata() + "/fonts";
	}

	/**
		@param code A language code.
		@return Which pinned face it needs, as an index into the `Typeface` tables, or -1
			where it needs none of its own.
	**/
	public static function slotOf(code:String):Int {
		return mdd.Typeface.LANGUAGE_FACE_FOR.indexOf(code);
	}

	/**
		@param code A language code.
		@return How many bytes picking it would download, or nought where it downloads
			nothing.
	**/
	public static function bytesOf(code:String):Int {
		final slot = slotOf(code);
		return slot < 0 ? 0 : mdd.Typeface.LANGUAGE_FACE_BYTES[slot];
	}

	/**
		@param code A language code.
		@return Whether everything it needs to be drawn is here: true for a language that
			needs no face of its own, and for one whose face is in either folder.
	**/
	public function present(code:String):Bool {
		final slot = slotOf(code);
		if (slot < 0) return true;

		final name = mdd.Typeface.LANGUAGE_FACES[slot];

		return FileSystem.exists(installed + "/" + name) || FileSystem.exists(kept + "/" + name);
	}

	/**
		@param codes Language codes.
		@return The ones among them that cannot be drawn until their face is fetched.
	**/
	public function absent(codes:Array<String>):Array<String> {
		return [for (code in codes) if (!present(code)) code];
	}

	/**
		@return Where the download is: one of the states above.
	**/
	public inline function state():Int {
		return held.load();
	}

	/**
		Starts fetching the face a language needs, on a thread of its own.

		@param code A language code.
		@return False where nothing was started: the language needs no face, its face is
			already here, or a download is already running.
	**/
	public function fetches(code:String):Bool {
		final slot = slotOf(code);
		if (slot < 0 || present(code) || held.load() == FETCHING) return false;

		language = code;
		expected = mdd.Typeface.LANGUAGE_FACE_BYTES[slot];
		partial = kept + "/" + mdd.Typeface.LANGUAGE_FACES[slot] + PARTIAL;

		held.store(FETCHING);

		sys.thread.Thread.create(function():Void {
			mdd.host.Crash.thread("the font download thread");
			held.store(fetched(slot));
		});

		return true;
	}

	/**
		Downloads and checks the face. This is the download thread.

		@param slot Which pinned face.
		@return The state the download settles in.
	**/
	function fetched(slot:Int):Int {
		final name = mdd.Typeface.LANGUAGE_FACES[slot];
		final settled = into(mdd.Typeface.LANGUAGE_FACE_FROM[slot],
			mdd.Typeface.LANGUAGE_FACE_SHA256[slot], kept + "/" + name);

		if (settled != FETCHED) return settled;

		final notice = mdd.Typeface.LANGUAGE_FACE_NOTICE[slot];

		try {
			if (FileSystem.exists(installed + "/" + notice)) {
				File.copy(installed + "/" + notice, kept + "/" + notice);
			}
		} catch (e:Dynamic) {}

		return settled;
	}

	/**
		Downloads one file to a partial name, checks it, and only then gives it its own.

		It blocks for as long as the download takes, so it belongs on a thread of its own
		everywhere but a check. It aborts a transfer that stalls below a kilobyte a second
		for half a minute rather than leaving the thread waiting for ever.

		@param from Where the file is.
		@param want Its SHA-256, in lower case hexadecimal.
		@param where Where it goes once it matches.
		@return `FETCHED`, `UNREACHABLE` or `BROKEN`.
	**/
	public static function into(from:String, want:String, where:String):Int {
		final part = where + PARTIAL;

		Paths.make(haxe.io.Path.directory(where));
		Paths.clear(part);

		final answered = Sys.command("curl", ["-sL", "--fail", "--connect-timeout", "20",
			"-y", "30", "-Y", "1024", "-o", part, from]);

		if (answered != 0 || !FileSystem.exists(part)) {
			Paths.clear(part);
			return UNREACHABLE;
		}

		final made = haxe.crypto.Sha256.make(File.getBytes(part)).toHex().toLowerCase();

		if (made != want) {
			Paths.clear(part);
			return BROKEN;
		}

		try {
			Paths.clear(where);
			FileSystem.rename(part, where);
		} catch (e:Dynamic) {
			Paths.clear(part);
			return UNREACHABLE;
		}

		return FileSystem.exists(where) ? FETCHED : UNREACHABLE;
	}

	/**
		@return How far through the download is, 0 to 1, or a negative number where that is
			not known.
	**/
	public function pulling():Float {
		if (expected <= 0 || partial == "" || !FileSystem.exists(partial)) return -1;

		final part = FileSystem.stat(partial).size / expected;
		return part < 0 ? 0 : (part > 1 ? 1 : part);
	}

	/**
		Goes back to idle once a finished download has been acted on.
	**/
	public function forget():Void {
		if (held.load() == FETCHING) return;
		held.store(IDLE);
	}
}
