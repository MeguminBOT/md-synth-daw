package mdd.gate;

import mdd.app.Update;
import mdd.host.Paths;
import sys.FileSystem;
import sys.io.File;
import sys.net.Host;
import sys.net.Socket;

@:unreflective
class UpdateCheck {
	static inline final FIRST_PORT = 8760;
	static inline final LAST_PORT = 8790;
	static inline final PATIENCE = 30.0;
	static inline final OFFERED = "9.9.9";

	static var ran = 0;
	static var failed = 0;

	static var lot:String = "";
	static var papers:String = "";
	static var listening:Null<Socket> = null;

	public static function run(args:Array<String>):Int {
		ran = 0;
		failed = 0;

		Sys.println("  update");

		if (!reachable()) {
			Sys.println("    not run: curl is not on the path");
			return Gate.SKIPPED;
		}

		final where = Gate.root + "/export/gate/update";

		Paths.clear(where);
		Paths.make(where);

		final port = opens();

		if (port == 0) {
			Sys.println("    not run: no loopback port between " + FIRST_PORT + " and "
				+ LAST_PORT);
			return Gate.SKIPPED;
		}

		final archive = packed(where);

		if (archive == "") {
			says("an archive of the new copy is built", false, "the archive tool would not run");
			shuts();

			Sys.println("    " + (ran - failed) + " of " + ran + " checks");
			Sys.println("    failed");

			return 1;
		}

		papers = release(port, archive);

		carried(where, port, archive);
		installed(where, port);
		bare();
		tentative();
		truthful(port);

		shuts();

		Sys.println("    " + (ran - failed) + " of " + ran + " checks");
		Sys.println(failed == 0 ? "    passed" : "    failed");

		return failed == 0 ? 0 : 1;
	}

	static function says(name:String, ok:Bool, said:String):Void {
		ran++;
		if (!ok) failed++;

		Sys.println("    " + StringTools.rpad(name, " ", 44) + said + (ok ? "" : "   FAILED"));
	}

	static function reachable():Bool {
		try {
			final run = new sys.io.Process("curl", ["--version"]);
			final code = run.exitCode();

			run.close();
			return code == 0;
		} catch (e:Dynamic) {
			return false;
		}
	}

	static function opens():Int {
		for (port in FIRST_PORT...LAST_PORT + 1) {
			try {
				final socket = new Socket();

				socket.bind(new Host("127.0.0.1"), port);
				socket.listen(8);

				listening = socket;
				sys.thread.Thread.create(function():Void serves());

				return port;
			} catch (e:Dynamic) {}
		}

		return 0;
	}

	static function shuts():Void {
		final socket = listening;
		listening = null;

		if (socket == null) return;

		try {
			socket.close();
		} catch (e:Dynamic) {}
	}

	static function serves():Void {
		while (listening != null) {
			final socket = listening;
			if (socket == null) return;

			var client:Null<Socket> = null;

			try {
				client = socket.accept();
			} catch (e:Dynamic) {
				return;
			}

			if (client == null) continue;

			try {
				answered(client);
			} catch (e:Dynamic) {}

			try {
				client.close();
			} catch (e:Dynamic) {}
		}
	}

	static function answered(client:Socket):Void {
		final line = client.input.readLine();

		while (true) {
			final header = StringTools.trim(client.input.readLine());
			if (header == "") break;
		}

		final parts = line.split(" ");
		final path = parts.length > 1 ? parts[1] : "";

		if (path.indexOf("/releases/latest") >= 0 && papers != "") {
			sends(client, "application/json", haxe.io.Bytes.ofString(papers));
			return;
		}

		final cut = path.split("/");
		final name = cut.length == 0 ? "" : cut[cut.length - 1];
		final file = lot + "/" + name;

		if (name != "" && FileSystem.exists(file)) {
			sends(client, "application/octet-stream", File.getBytes(file));
			return;
		}

		client.output.writeString("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n"
			+ "Connection: close\r\n\r\n");
		client.output.flush();
	}

	static function sends(client:Socket, kind:String, body:haxe.io.Bytes):Void {
		client.output.writeString("HTTP/1.1 200 OK\r\nContent-Type: " + kind
			+ "\r\nContent-Length: " + body.length + "\r\nConnection: close\r\n\r\n");

		client.output.writeBytes(body, 0, body.length);
		client.output.flush();
	}

	static function ending():String {
		return Paths.platform() == "windows" ? ".exe" : "";
	}

	static function named():String {
		return mdd.Config.SHORT + "-" + OFFERED + "-" + Paths.platform() + "-" + Paths.machine()
			+ "-portable";
	}

	static function wrote(where:String, said:String):Void {
		Paths.make(haxe.io.Path.directory(where));
		File.saveContent(where, said);
	}

	static function packed(where:String):String {
		final leaf = named();
		final fresh = where + "/fresh";
		final inside = fresh + "/" + leaf;

		lot = where + "/lot";
		Paths.make(lot);

		wrote(inside + "/" + mdd.Config.SHORT + ending(), "the new program, " + OFFERED + "\n");
		wrote(inside + "/assets/note.txt", "new asset\n");
		wrote(inside + "/portable.txt", "portable\n");
		wrote(inside + "/userdata/settings/.keep", "");

		final zipped = Paths.platform() == "windows";
		final archive = lot + "/" + leaf + (zipped ? ".zip" : ".tar.gz");

		final code = zipped
			? Sys.command("powershell", ["-NoProfile", "-NonInteractive", "-Command",
				"Compress-Archive -Path '" + inside + "' -DestinationPath '" + archive
				+ "' -Force"])
			: Sys.command("tar", ["-czf", archive, "-C", fresh, leaf]);

		return code == 0 && FileSystem.exists(archive) ? archive : "";
	}

	static function release(port:Int, archive:String):String {
		final leaf = haxe.io.Path.withoutDirectory(archive);
		final at = "http://127.0.0.1:" + port + "/assets/";
		final size = FileSystem.stat(archive).size;

		final other = mdd.Config.SHORT + "-" + OFFERED + "-" + Paths.platform() + "-"
			+ Paths.machine() + (Paths.platform() == "windows" ? "-setup.exe"
				: (Paths.platform() == "mac" ? ".dmg" : "-installer.tar.gz"));

		sums(archive, leaf);

		return "{\"tag_name\":\"v" + OFFERED + "\","
			+ "\"html_url\":\"http://127.0.0.1:" + port + "/release\","
			+ "\"body\":\"A newer copy.\\nAnd a second line nobody should read.\","
			+ "\"assets\":["
			+ "{\"name\":\"" + leaf + "\",\"size\":" + size
			+ ",\"browser_download_url\":\"" + at + leaf + "\"},"
			+ "{\"name\":\"" + Update.SUMS + "\",\"size\":0"
			+ ",\"browser_download_url\":\"" + at + Update.SUMS + "\"},"
			+ "{\"name\":\"" + other + "\",\"size\":" + size
			+ ",\"browser_download_url\":\"" + at + other + "\"}]}";
	}

	/**
		Writes the hash file the release publishes, the way sha256sum writes one.

		@param archive The file to list.
		@param leaf What the release calls it.
	**/
	static function sums(archive:String, leaf:String):Void {
		final hash = haxe.crypto.Sha256.make(File.getBytes(archive)).toHex().toLowerCase();
		wrote(lot + "/" + Update.SUMS, hash + "  " + leaf + "\n");
	}

	/**
		Serves bytes that are not the ones the hashes list, and expects them to be refused.

		Every other check here runs against a server telling the truth, so none of them can
		tell a download that arrived whole from one that did not. The archive is put back
		before this returns, because the checks after it read the real one.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function tampered(where:String, port:Int, archive:String):Void {
		final was = File.getBytes(archive);
		File.saveBytes(archive, haxe.io.Bytes.ofString("not the file that was built"));

		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		update.looksAt("http://127.0.0.1:" + port + "/repos/");
		update.look();

		final waiting = settles(update, Update.WAITING);
		final into = where + "/downloads/tampered";

		var refused = false;

		if (waiting) {
			update.take(into);

			final until = Sys.time() + PATIENCE;

			while (Sys.time() < until && update.state() != Update.BROKEN
					&& update.state() != Update.FETCHED) {
				Sys.sleep(0.02);
			}

			refused = update.state() == Update.BROKEN;
		}

		final gone = !FileSystem.exists(into);

		File.saveBytes(archive, was);

		says("a download that does not match is refused", refused && gone,
			!waiting ? "the api would not answer"
				: (refused ? "refused: " + update.wrong + (gone ? ", and deleted" : ", but kept")
					: "state " + update.state() + " rather than broken"));
	}

	/**
		A release nothing can be taken from is not offered.

		Reaching `WAITING` is what puts the notice in front of the reader, and the only
		answer they can give it is download. A newer release carrying no file this copy
		can use leaves nowhere to download from, so offering it wastes the one thing they
		can do and tells them so afterwards.
	**/
	static function bare():Void {
		final update = fresh();

		update.read("{\"tag_name\":\"v" + OFFERED + "\",\"body\":\"newer\",\"assets\":[]}");

		says("a release with no files offers nothing", update.saidAt == "",
			"tag " + update.offered + " read, " + update.assets
			+ " assets, nowhere to download from");
	}

	/**
		A release the document marks as unfinished is not offered.

		The releases page is asked for the latest, which leaves pre-releases and drafts
		out on its own, so nothing here should ever see one. This holds if that is ever
		pointed somewhere that does answer with one, and costs a pair of reads to do it.
	**/
	static function tentative():Void {
		final flagged = fresh();
		flagged.read("{\"tag_name\":\"v" + OFFERED + "\",\"prerelease\":true,\"assets\":[]}");

		says("a release flagged as a pre-release goes", flagged.offered == "",
			"tag v" + OFFERED + " flagged prerelease, offered \"" + flagged.offered + "\"");

		final drafted = fresh();
		drafted.read("{\"tag_name\":\"v" + OFFERED + "\",\"draft\":true,\"assets\":[]}");

		says("and so is a draft", drafted.offered == "",
			"tag v" + OFFERED + " flagged draft, offered \"" + drafted.offered + "\"");

		final whole = fresh();
		whole.read("{\"tag_name\":\"v" + OFFERED + "\",\"assets\":[]}");

		says("while a finished one is still read", whole.offered == OFFERED,
			"tag v" + OFFERED + " offered " + whole.offered);
	}

	static function fresh():Update {
		return new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
	}

	/**
		The states a real repository actually puts it in, driven end to end.

		Both of these were reached by a copy in the field and neither may raise a notice.
		A release whose tag is the version already running is not newer, and a releases
		page that answers 404, which is what one carrying only pre-releases does, is not
		an answer at all. Each is checked through the whole path rather than by reading
		the document, because reaching the waiting state is what puts the notice up.

		@param port The port the server is on.
	**/
	static function truthful(port:Int):Void {
		final was = papers;

		papers = "{\"tag_name\":\"v0.1.0\",\"html_url\":\"http://127.0.0.1:" + port
			+ "/release\",\"body\":\"same\",\"assets\":[]}";

		final same = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		same.looksAt("http://127.0.0.1:" + port + "/repos/");
		same.look();

		final settledAt = waits(same);

		says("a release matching the running version", settledAt == Update.CURRENT,
			"0.1.0 offered to 0.1.0 settled at " + phase(settledAt) + " rather than waiting");

		papers = "";

		final gone = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		gone.looksAt("http://127.0.0.1:" + port + "/repos/");
		gone.look();

		final missed = waits(gone);

		says("and a releases page that answers 404", missed == Update.UNREACHABLE,
			"settled at " + phase(missed) + " rather than waiting");

		papers = was;
	}

	/**
		@param update One that has been told to look.
		@return The state it settles in, once it has stopped looking.
	**/
	static function waits(update:Update):Int {
		final until = Sys.time() + PATIENCE;

		while (Sys.time() < until) {
			final now = update.state();
			if (now != Update.IDLE && now != Update.LOOKING) return now;

			Sys.sleep(0.02);
		}

		return update.state();
	}

	static function phase(state:Int):String {
		return switch (state) {
			case Update.IDLE: "idle";
			case Update.LOOKING: "looking";
			case Update.CURRENT: "current";
			case Update.WAITING: "WAITING";
			case Update.UNREACHABLE: "unreachable";
			case _: "" + state;
		}
	}

	static function settles(update:Update, want:Int):Bool {
		final until = Sys.time() + PATIENCE;

		while (Sys.time() < until) {
			final now = update.state();

			if (now == want) return true;
			if (now == Update.BROKEN || now == Update.UNREACHABLE) return false;

			Sys.sleep(0.02);
		}

		return false;
	}

	static function carried(where:String, port:Int, archive:String):Void {
		final install = where + "/install";

		wrote(install + "/" + mdd.Config.SHORT + ending(), "the old program, 0.1.0\n");
		wrote(install + "/assets/note.txt", "old asset\n");
		wrote(install + "/portable.txt", "portable\n");
		wrote(install + "/userdata/settings/kept.txt", "the reader's own settings\n");

		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		update.looksAt("http://127.0.0.1:" + port + "/repos/");

		update.look();

		final found = settles(update, Update.WAITING);

		says("the api answers and a newer version is read", found && update.offered == OFFERED,
			found ? "offered " + update.offered + ", " + update.assets + " assets"
				: "state " + update.state() + " rather than waiting");

		says("the notes are one line", update.notes == "A newer copy.",
			"\"" + update.notes + "\"");

		final leaf = haxe.io.Path.withoutDirectory(archive);

		says("a portable copy is offered the archive", update.named() == leaf,
			update.named() == "" ? "nothing chosen" : update.named());

		final into = where + "/downloads/" + update.named();
		Paths.make(where + "/downloads");

		update.take(into);

		final pulled = settles(update, Update.FETCHED);
		final same = pulled && FileSystem.exists(into)
			&& File.getBytes(into).compare(File.getBytes(archive)) == 0;

		says("the download is the file the server holds", same,
			pulled ? (same ? FileSystem.stat(into).size + " bytes, byte for byte"
				: "the bytes differ") : "state " + update.state() + " rather than fetched");

		says("and it was checked against the hashes", update.sumsAt != "",
			update.sumsAt == "" ? "no " + Update.SUMS + " was found in the release"
				: Update.SUMS + " listed " + update.chosen);

		tampered(where, port, archive);

		update.applies(install, false, false);

		final ready = settles(update, Update.APPLIED);
		final script = update.handover;

		says("a handover script is written", ready && script != "" && FileSystem.exists(script),
			ready ? haxe.io.Path.withoutDirectory(script)
				: "state " + update.state() + ", " + update.wrong);

		says("the staged copy carries the program",
			update.staged != ""
				&& FileSystem.exists(update.staged + "/" + mdd.Config.SHORT + ending()),
			update.staged == "" ? "nothing staged"
				: haxe.io.Path.withoutDirectory(update.staged));

		if (!ready || script == "") return;

		final code = Paths.platform() == "windows"
			? Sys.command("cmd", ["/c", script])
			: Sys.command("sh", [script]);

		final program = install + "/" + mdd.Config.SHORT + ending();
		final swapped = FileSystem.exists(program)
			&& File.getContent(program).indexOf(OFFERED) >= 0;

		says("the handover replaces the program", code == 0 && swapped,
			swapped ? "now says " + OFFERED : "exit " + code + ", the old program is still there");

		final asset = install + "/assets/note.txt";
		final fresh = FileSystem.exists(asset) && File.getContent(asset).indexOf("new") >= 0;

		says("and everything beside it", fresh, fresh ? "assets/note.txt is the new one"
			: "assets/note.txt was not replaced");

		final kept = install + "/userdata/settings/kept.txt";

		says("without touching what the reader owns", FileSystem.exists(kept),
			FileSystem.exists(kept) ? "userdata survived the swap" : "userdata was lost");

		says("the download and the staging are cleared up",
			!FileSystem.exists(into) && !FileSystem.exists(update.staged),
			(FileSystem.exists(into) ? "the archive is still there" : "")
				+ (FileSystem.exists(update.staged) ? " the staging is still there" : "")
				+ (!FileSystem.exists(into) && !FileSystem.exists(update.staged)
					? "nothing left behind" : ""));
	}

	static function installed(where:String, port:Int):Void {
		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), false);
		update.looksAt("http://127.0.0.1:" + port + "/repos/");

		update.look();

		if (!settles(update, Update.WAITING)) {
			says("an installed copy is offered the installer", false, "the api would not answer");
			return;
		}

		final wanted = Paths.platform() == "windows" ? "setup.exe"
			: (Paths.platform() == "mac" ? ".dmg" : "installer.tar.gz");

		says("an installed copy is offered the installer",
			StringTools.endsWith(update.named(), wanted),
			update.named() == "" ? "nothing chosen" : update.named());
	}
}
