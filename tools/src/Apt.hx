import sys.FileSystem;
import sys.io.File;

/**
	The apt repository the website serves the Debian packages from: the packages in a pool, the
	list apt reads for each architecture, and a release file naming those lists by their hashes,
	signed so that `apt update` can trust them. `apt-ftparchive` writes the lists and the release
	file, and gpg signs it with the key in the keyring, which is only there where whoever builds
	the website put it.
**/
@:access(Run)
class Apt {
	/**
		The suite the repository publishes, which is the one word in a source line after the address.
	**/
	public static inline final SUITE = "stable";

	/**
		Writes the repository into `to`, or clears it and writes nothing. A repository with no
		signature is refused by apt, so no signing key means no repository rather than one nobody
		can use.

		@param root The repository root.
		@param project What the build file declares.
		@param from A folder holding the Debian packages, or an empty string for none.
		@param to Where the repository goes, inside the website.
		@return Whether a signed repository was written.
	**/
	public static function write(root:String, project:Project, from:String, to:String):Bool {
		if (FileSystem.exists(to)) Run.remove(to);
		if (from == "") return false;

		final packages = FileSystem.exists(from)
			? [for (entry in FileSystem.readDirectory(from)) if (StringTools.endsWith(entry, ".deb")) entry] : [];

		if (packages.length == 0) {
			said("not written: " + from + " holds no Debian package");
			return false;
		}

		for (tool in ["apt-ftparchive", "gpg", "gzip"]) {
			if (Sys.command("sh", ["-c", "command -v " + tool + " >/dev/null 2>&1"]) != 0) {
				said("not written: " + tool + " is not installed");
				return false;
			}
		}

		final key = signer();

		if (key == "") {
			said("not written: the keyring holds no secret key to sign it with");
			return false;
		}

		packages.sort(ordered);

		final pool = to + "/pool/main";
		Run.tree(pool);

		final architectures:Array<String> = [];

		for (name in packages) {
			Run.copyFile(from + "/" + name, pool + "/" + name);

			final underscore = name.lastIndexOf("_");
			final architecture = name.substring(underscore + 1, name.length - 4);
			if (underscore > 0 && architectures.indexOf(architecture) < 0) architectures.push(architecture);
		}

		architectures.sort(ordered);

		final dists = to + "/dists/" + SUITE;

		for (architecture in architectures) {
			final lists = dists + "/main/binary-" + architecture;
			Run.tree(lists);

			final listed = captured(to, ["apt-ftparchive", "--arch", architecture, "packages", "pool"]);

			if (listed == null) {
				said("not written: apt-ftparchive would not list the " + architecture + " packages");
				Run.remove(to);
				return false;
			}

			File.saveContent(lists + "/Packages", listed);
			captured(lists, ["gzip", "-9nkf", "Packages"]);
		}

		final release = captured(dists, ["apt-ftparchive",
			"-o", "APT::FTPArchive::Release::Origin=" + project.title,
			"-o", "APT::FTPArchive::Release::Label=" + project.title,
			"-o", "APT::FTPArchive::Release::Suite=" + SUITE,
			"-o", "APT::FTPArchive::Release::Codename=" + SUITE,
			"-o", "APT::FTPArchive::Release::Components=main",
			"-o", "APT::FTPArchive::Release::Architectures=" + architectures.join(" "),
			"-o", "APT::FTPArchive::Release::Description=" + project.description,
			"release", "."]);

		if (release == null) {
			said("not written: apt-ftparchive would not write the release file");
			Run.remove(to);
			return false;
		}

		File.saveContent(dists + "/Release", release);

		final signed = captured(dists, ["gpg", "--batch", "--yes", "--local-user", key, "--clearsign",
			"--output", "InRelease", "Release"]) != null
			&& captured(dists, ["gpg", "--batch", "--yes", "--local-user", key, "--armor", "--detach-sign",
				"--output", "Release.gpg", "Release"]) != null
			&& captured(to, ["gpg", "--batch", "--yes", "--output", project.debianPackage + ".gpg",
				"--export", key]) != null
			&& captured(to, ["gpg", "--batch", "--yes", "--armor", "--output", project.debianPackage + ".asc",
				"--export", key]) != null;

		if (!signed) {
			said("not written: gpg would not sign with " + key);
			Run.remove(to);
			return false;
		}

		said(packages.length + (packages.length == 1 ? " package" : " packages") + " for " + architectures.join(" and ") + " into "
			+ to.substr(root.length + 1) + ", signed by " + key.substr(key.length - 16));
		return true;
	}

	/**
		@return The fingerprint to sign with: the one `MDD_APT_KEY` names, or else the first
			secret key in the keyring, or an empty string where there is none.
	**/
	static function signer():String {
		final named = Sys.getEnv("MDD_APT_KEY");
		if (named != null && named != "") return named;

		final listed = captured(".", ["gpg", "--batch", "--with-colons", "--list-secret-keys"]);
		if (listed == null) return "";

		var secret = false;

		for (line in listed.split("\n")) {
			if (StringTools.startsWith(line, "sec:")) secret = true;
			else if (secret && StringTools.startsWith(line, "fpr:")) return line.split(":")[9];
		}

		return "";
	}

	/**
		@param at The folder to run it in.
		@param command The program and its arguments.
		@return What it printed, or null where it failed.
	**/
	static function captured(at:String, command:Array<String>):Null<String> {
		try {
			final run = new sys.io.Process("sh", ["-c", "cd \"$0\" && exec \"$@\"", at].concat(command));
			final out = run.stdout.readAll().toString();
			run.stderr.readAll();

			final code = run.exitCode();
			run.close();

			return code == 0 ? out : null;
		} catch (e:haxe.Exception) {
			return null;
		}
	}

	static function ordered(one:String, two:String):Int {
		return one < two ? -1 : (one > two ? 1 : 0);
	}

	static function said(what:String):Void {
		Sys.println("  " + StringTools.rpad("apt", " ", 14) + what);
	}
}
