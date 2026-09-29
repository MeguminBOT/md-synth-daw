package mdd.gate;

import mdd.app.Update;
import mdd.host.Paths;
import sys.FileSystem;
import sys.io.File;
import sys.net.Host;
import sys.net.Socket;

@:unreflective
@:access(mdd.app.Update)
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
		handed(where, port, archive);
		elevated(where, port, archive);
		installed(where, port);
		bare();
		tentative();
		truthful(port);
		strangers(archive);
		unsummed(port, archive);
		twice(where, port, archive);
		changed(where, port);

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

	/**
		Points an updater at the local server, both for the release document and for the
		files the release carries.

		@param update The updater.
		@param port The port the server is on.
	**/
	static function pointed(update:Update, port:Int):Void {
		update.looksAt("http://127.0.0.1:" + port + "/repos/", "http://127.0.0.1:" + port + "/");
	}

	/**
		@param port The port the server is on.
		@return Where the local server serves the offered release's files, laid out as GitHub
			lays out a release's downloads.
	**/
	static function served(port:Int):String {
		return "http://127.0.0.1:" + port + "/owner/name/releases/download/v" + OFFERED + "/";
	}

	static function release(port:Int, archive:String):String {
		final leaf = haxe.io.Path.withoutDirectory(archive);
		final at = served(port);
		final size = FileSystem.stat(archive).size;

		final other = mdd.Config.SHORT + "-" + OFFERED + "-" + Paths.platform() + "-"
			+ Paths.machine() + (Paths.platform() == "windows" ? "-setup.exe"
				: (Paths.platform() == "mac" ? ".dmg" : "-installer.tar.gz"));

		File.saveBytes(lot + "/" + other, File.getBytes(archive));
		sums(archive, [leaf, other]);

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
		Writes the hash file the release publishes, the way sha256sum writes one. The installer
		the release offers is the same bytes as the archive under another name, so one hash
		serves every name.

		@param archive The file to list.
		@param leaves What the release calls it, once for each name it carries it under.
	**/
	static function sums(archive:String, leaves:Array<String>):Void {
		final hash = haxe.crypto.Sha256.make(File.getBytes(archive)).toHex().toLowerCase();
		wrote(lot + "/" + Update.SUMS, [for (leaf in leaves) hash + "  " + leaf + "\n"].join(""));
	}

	/**
		Serves bytes that are not the ones the hashes list, and expects them to be refused:
		once the same length as the real file, which only the hash can catch, and once a
		different length, which the size the release lists catches first.

		Every other check here runs against a server telling the truth, so none of them can
		tell a download that arrived whole from one that did not. The archive is put back
		before this returns, because the checks after it read the real one.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function tampered(where:String, port:Int, archive:String):Void {
		final was = File.getBytes(archive);
		final flipped = was.sub(0, was.length);
		final middle = flipped.length >> 1;

		flipped.set(middle, flipped.get(middle) ^ 0xFF);

		refuses(where, port, archive, flipped, "a download that does not match is refused");
		refuses(where, port, archive, haxe.io.Bytes.ofString("not the file that was built"),
			"and one of the wrong size");

		File.saveBytes(archive, was);
	}

	/**
		Serves other bytes in place of the archive and expects the download to be refused and
		deleted.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
		@param served What it hands out instead.
		@param name What the check is called.
	**/
	static function refuses(where:String, port:Int, archive:String, served:haxe.io.Bytes,
			name:String):Void {
		File.saveBytes(archive, served);

		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		pointed(update, port);
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

		says(name, refused && gone,
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
		pointed(same, port);
		same.look();

		final settledAt = waits(same);

		says("a release matching the running version", settledAt == Update.CURRENT,
			"0.1.0 offered to 0.1.0 settled at " + phase(settledAt) + " rather than waiting");

		papers = "";

		final gone = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		pointed(gone, port);
		gone.look();

		final missed = waits(gone);

		says("and a releases page that answers 404", missed == Update.UNREACHABLE,
			"settled at " + phase(missed) + " rather than waiting");

		papers = was;
	}

	/**
		Only a file the offered release carries in this repository is taken. Every address in
		the document is handed to the downloader, so one pointing anywhere else, another
		repository, another release, plain http or another file's address, has to leave
		nothing to download, while the same document pointing home still offers the file.

		@param archive The file the server hands out.
	**/
	static function strangers(archive:String):Void {
		final leaf = haxe.io.Path.withoutDirectory(archive);
		final home = "https://github.com/owner/name/releases/download/v" + OFFERED + "/";

		final elsewhere = [
			"https://example.com/owner/name/releases/download/v" + OFFERED + "/" + leaf,
			"https://github.com/other/name/releases/download/v" + OFFERED + "/" + leaf,
			"https://github.com/owner/name/releases/download/v1.0.0/" + leaf,
			"http://github.com/owner/name/releases/download/v" + OFFERED + "/" + leaf,
			home + "renamed-" + leaf
		];

		var taken = 0;

		for (url in elsewhere) {
			final update = fresh();
			update.read(listing(leaf, url, home + Update.SUMS));

			if (update.saidAt != "") taken++;
		}

		final control = fresh();
		control.read(listing(leaf, home + leaf, home + Update.SUMS));

		final homely = control.saidAt == home + leaf && control.sumsAt == home + Update.SUMS;

		says("a file from outside the release goes", taken == 0 && homely,
			taken + " of " + elsewhere.length + " addresses outside the release taken, and the"
			+ " release's own " + (homely ? "taken with its hashes" : "not taken"));
	}

	/**
		@param leaf What the release calls its one file.
		@param url Where the document says that file is.
		@param sums Where it says the hashes are.
		@return A release document offering the one file and the hashes.
	**/
	static function listing(leaf:String, url:String, sums:String):String {
		return "{\"tag_name\":\"v" + OFFERED + "\",\"assets\":["
			+ "{\"name\":\"" + leaf + "\",\"size\":16,\"browser_download_url\":\"" + url + "\"},"
			+ "{\"name\":\"" + Update.SUMS + "\",\"size\":0,\"browser_download_url\":\"" + sums
			+ "\"}]}";
	}

	/**
		A release publishing no hashes is not offered, because nothing it carries could be
		checked, and a download that cannot be checked is refused after it has been fetched.

		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function unsummed(port:Int, archive:String):Void {
		final was = papers;
		final leaf = haxe.io.Path.withoutDirectory(archive);

		papers = "{\"tag_name\":\"v" + OFFERED + "\",\"assets\":[{\"name\":\"" + leaf
			+ "\",\"size\":" + FileSystem.stat(archive).size + ",\"browser_download_url\":\""
			+ served(port) + leaf + "\"}]}";

		final update = fresh();
		pointed(update, port);
		update.look();

		final settledAt = waits(update);

		says("a release without hashes is not offered", settledAt == Update.UNREACHABLE,
			"settled at " + phase(settledAt) + " with " + update.named() + " and no "
			+ Update.SUMS);

		papers = was;
	}

	/**
		A hash file listing the chosen file twice says two different things about it, and
		taking either line would be a guess.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function twice(where:String, port:Int, archive:String):Void {
		final list = lot + "/" + Update.SUMS;
		final was = File.getContent(list);
		final leaf = haxe.io.Path.withoutDirectory(archive);

		File.saveContent(list, was + StringTools.lpad("", "0", 64) + "  " + leaf + "\n");

		final update = fresh();
		pointed(update, port);
		update.look();

		final into = where + "/downloads/twice";
		final waiting = settles(update, Update.WAITING);

		if (waiting) update.take(into);

		final settledAt = waiting ? downloads(update) : update.state();

		File.saveContent(list, was);

		says("a name listed twice is refused", settledAt == Update.BROKEN,
			!waiting ? "the api would not answer"
				: "settled at " + phase(settledAt) + (update.wrong == "" ? "" : ": " + update.wrong));
	}

	/**
		A download is checked when it arrives and installed later, so the file is checked
		again before anything is replaced, and one changed in between is refused and deleted.

		@param where The working folder.
		@param port The port the server is on.
	**/
	static function changed(where:String, port:Int):Void {
		final install = where + "/unchanged";

		wrote(install + "/" + mdd.Config.SHORT + ending(), "the old program, 0.1.0\n");

		final update = fresh();
		pointed(update, port);
		update.look();

		final waiting = settles(update, Update.WAITING);
		final into = where + "/downloads/changed-" + update.named();

		if (waiting) update.take(into);

		final pulled = waiting && downloads(update) == Update.FETCHED;

		if (pulled) File.saveContent(into, "swapped for something else after the check");
		if (pulled) update.applies(install, false, false);

		final settledAt = pulled ? applying(update) : update.state();
		final program = File.getContent(install + "/" + mdd.Config.SHORT + ending());

		says("a file changed after the check is refused",
			settledAt == Update.BROKEN && !FileSystem.exists(into) && program.indexOf(OFFERED) < 0,
			!pulled ? "the download did not arrive"
				: "settled at " + phase(settledAt) + (update.wrong == "" ? "" : ": " + update.wrong)
				+ (FileSystem.exists(into) ? ", and the file was kept" : ", and it was deleted"));
	}

	/**
		@param update One that has been told to download.
		@return The state it settles in once the download has finished or been refused.
	**/
	static function downloads(update:Update):Int {
		final until = Sys.time() + PATIENCE;

		while (Sys.time() < until && update.state() == Update.FETCHING) Sys.sleep(0.02);

		return update.state();
	}

	/**
		@param update One that has been told to apply what it downloaded.
		@return The state it settles in once applying has finished.
	**/
	static function applying(update:Update):Int {
		final until = Sys.time() + PATIENCE;

		while (Sys.time() < until && update.state() == Update.APPLYING) Sys.sleep(0.02);

		return update.state();
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
			case Update.FETCHED: "fetched";
			case Update.APPLIED: "applied";
			case Update.BROKEN: "broken";
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
		pointed(update, port);

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

		says("a writable copy is replaced as this account",
			!update.elevates && update.restarts == "",
			update.elevates ? "the handover would ask to run as an administrator"
				: "the handover runs as this account and starts the program itself");

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

	/**
		The handover the application launches waits for the application to close and then swaps the
		new copy in by itself. It is started through `hands`, as the application starts it, with
		the lock held the way the application holds it, and letting go of that lock stands in for
		the application closing.

		A handover that inherited the lock held it open itself, so it waited forever and nothing
		was ever replaced, and running the script by hand, as the check above does, could not
		show that.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function handed(where:String, port:Int, archive:String):Void {
		final install = where + "/handed";
		final program = install + "/" + mdd.Config.SHORT + ending();

		wrote(program, "the old program, 0.1.0\n");
		wrote(install + "/portable.txt", "portable\n");

		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		pointed(update, port);

		update.look();

		if (!settles(update, Update.WAITING)) {
			says("the handover waits for the program to close", false, "the api would not answer");
			return;
		}

		final into = where + "/handing/" + update.named();
		Paths.make(where + "/handing");

		update.take(into);

		if (!settles(update, Update.FETCHED)) {
			says("the handover waits for the program to close", false, "the download did not arrive");
			return;
		}

		update.applies(install, false, true);

		if (!settles(update, Update.APPLIED)) {
			says("the handover waits for the program to close", false,
				"state " + update.state() + ", " + update.wrong);
			return;
		}

		final launched = update.hands();

		Sys.sleep(1.5);
		final early = saying(program).indexOf(OFFERED) >= 0;

		if (update.lock != null) {
			update.lock.close();
			update.lock = null;
		}

		final until = Sys.time() + PATIENCE;
		var swapped = false;

		while (Sys.time() < until && !swapped) {
			swapped = saying(program).indexOf(OFFERED) >= 0;
			if (!swapped) Sys.sleep(0.1);
		}

		says("the handover waits for the program to close", launched && !early,
			!launched ? "it would not start" : (early ? "it replaced the program while it still ran"
				: "nothing was replaced while the lock was held"));

		says("and then swaps the new one in by itself", swapped,
			swapped ? "the program says " + OFFERED + " once the lock was let go"
				: "the old program is still there " + PATIENCE + " s after the lock was let go");
	}

	/**
		A copy in a folder this account cannot write to is replaced by a handover that runs as an
		administrator, which the application asks Windows to allow before it closes, and the new copy
		is started by a second script that runs as this account. Nothing here can answer the question
		Windows puts on the screen, so the check never asks it: it refuses itself writing into the
		folder so the updater has to see it as one, reads both scripts, then writes again and runs
		the handover by hand as the administrator would.

		@param where The working folder.
		@param port The port the server is on.
		@param archive The file the server hands out.
	**/
	static function elevated(where:String, port:Int, archive:String):Void {
		if (Paths.platform() != "windows") return;

		final named = "an unwritable copy is replaced elevated";
		final install = where + "/elevated";
		final program = install + "/" + mdd.Config.SHORT + ending();

		wrote(program, "the old program, 0.1.0\n");
		wrote(install + "/portable.txt", "portable\n");
		wrote(install + "/userdata/settings/kept.txt", "the reader's own settings\n");

		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), true);
		pointed(update, port);

		update.look();

		if (!settles(update, Update.WAITING)) {
			says(named, false, "the api would not answer");
			return;
		}

		final into = where + "/elevating/" + update.named();
		Paths.make(where + "/elevating");

		update.take(into);

		if (!settles(update, Update.FETCHED)) {
			says(named, false, "the download did not arrive");
			return;
		}

		final refused = denies(install, true);

		update.applies(install, true, false);

		final ready = settles(update, Update.APPLIED);
		final allowed = denies(install, false);

		says(named, refused && ready && update.elevates,
			!refused ? "icacls would not refuse writing into the folder"
				: (!ready ? "state " + update.state() + ", " + update.wrong
					: (update.elevates ? "the handover asks to run as an administrator"
						: "the handover would run as this account and fail")));

		if (!ready || !allowed) {
			if (!allowed) says("and writing is allowed again", false, "icacls would not take the refusal back");
			return;
		}

		final beside = haxe.io.Path.directory(into);
		final marker = "\"" + StringTools.replace(beside + "/" + Update.DONE, "/", "\\") + "\"";
		final again = "start \"\" \"" + StringTools.replace(program, "/", "\\") + "\"";
		final script = saying(update.handover);
		final restart = saying(update.restarts);

		final handsOver = script.indexOf("echo done> " + marker) >= 0 && script.indexOf(again) < 0;
		final waitsFor = restart.indexOf("if exist " + marker + " goto done") >= 0
			&& restart.indexOf(again) > restart.indexOf(":done");

		says("and restarts as this account after it", handsOver && waitsFor,
			!handsOver ? "the elevated handover starts the program itself, as an administrator"
				: (waitsFor ? "restart.cmd waits for " + Update.DONE + " and then starts the program"
					: "restart.cmd does not wait for the handover"));

		final code = mdd.host.Command.runs("cmd", ["/d", "/c", StringTools.replace(update.handover, "/", "\\")]);
		final swapped = saying(program).indexOf(OFFERED) >= 0;
		final done = FileSystem.exists(beside + "/" + Update.DONE);

		says("the elevated handover swaps it and says so",
			code == 0 && swapped && done,
			!swapped ? "exit " + code + ", the old program is still there"
				: (done ? "the program says " + OFFERED + " and " + Update.DONE + " is there"
					: "nothing was left for the restart to wait for"));
	}

	/**
		@param folder A folder.
		@param refused Whether this account is to be refused writing into it, or allowed again.
		@return Whether icacls did it.
	**/
	static function denies(folder:String, refused:Bool):Bool {
		final user = Sys.getEnv("USERNAME");
		final path = StringTools.replace(folder, "/", "\\");

		if (user == null || user == "") return false;

		return mdd.host.Command.runs("icacls", refused ? [path, "/deny", user + ":(W)"]
			: [path, "/remove:d", user]) == 0;
	}

	/**
		@param path A file.
		@return What it says, or nothing where it cannot be read, as while it is being copied over.
	**/
	static function saying(path:String):String {
		try {
			return FileSystem.exists(path) ? File.getContent(path) : "";
		} catch (e:Dynamic) {
			return "";
		}
	}

	static function installed(where:String, port:Int):Void {
		final update = new Update("owner/name", "0.1.0", Paths.platform(), Paths.machine(), false);
		pointed(update, port);

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

		if (Paths.platform() != "windows") return;

		final into = where + "/installing/" + update.named();
		final install = where + "/installed";
		Paths.make(where + "/installing");
		Paths.make(install);

		update.take(into);

		if (!settles(update, Update.FETCHED)) {
			says("the installer is run as cmd reads a path", false, "the installer did not arrive");
			return;
		}

		update.applies(install, true, false);

		if (!settles(update, Update.APPLIED)) {
			says("the installer is run as cmd reads a path", false,
				"state " + update.state() + ", " + update.wrong);
			return;
		}

		final script = saying(update.handover);
		final setup = "\"" + StringTools.replace(into, "/", "\\") + "\"";
		final again = "\"" + StringTools.replace(install + "/" + mdd.Config.SHORT + ending(), "/", "\\") + "\"";
		final waited = script.indexOf("start \"\" /wait " + setup + " /SILENT") >= 0;
		final scoped = script.indexOf("/CURRENTUSER") >= 0;
		final restarted = script.indexOf("start \"\" " + again) > script.indexOf(setup);

		says("the installer is run as cmd reads a path", waited && scoped,
			waited ? "waited on, quoted in double quotes, for the current account"
				: "the script runs " + script.split("\r\n").filter(function(line:String):Bool
					return line.indexOf("SILENT") >= 0).join(" "));

		says("and the program starts again after it", restarted,
			restarted ? "the installed program is started after the installer" : "nothing is started after it");
	}
}
