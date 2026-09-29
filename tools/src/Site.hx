import sys.FileSystem;
import sys.io.File;

/**
	A tab in the website's header: the page it opens and what it is called.
**/
private typedef Tab = {
	page:String,
	title:String
}

/**
	One of the examples the manual lists: its number, its name, the channels it plays on, the
	audio of it, and the numbered section of the manual that explains it with the heading it
	links to.
**/
private typedef Example = {
	number:Int,
	title:String,
	channels:String,
	audio:String,
	section:String,
	id:String
}

/**
	A video in a playlist: its identifier, its name with the channel's own wording around it taken
	off, the day it went up, and the largest still YouTube has of it.
**/
private typedef Song = {
	id:String,
	title:String,
	published:String,
	still:String
}

/**
	Writes the website into the output directory, as GitHub Pages publishes it.

	Every page in `site/` is wrapped in the one layout there, and the pieces a page asks for are
	filled in from the documents they describe: the user manual from `docs/user-manual.md`, the
	examples from the table in it, and whole sections of `README.md`, so the website says what the
	repository says without a second copy to keep in step. The pictures and the example audio are
	copied in beside the pages, and the result opens from disk the same way it opens online.
**/
@:access(Run)
class Site {
	static inline final SOURCE = "site";
	static inline final MANUAL = "docs/user-manual.md";
	static inline final README = "README.md";

	/**
		The header's tabs in the order they are shown. A tab whose page is not in `site/` is left
		out rather than drawn as a way to nowhere.
	**/
	static final TABS:Array<Tab> = [
		{page: "index", title: "Home"},
		{page: "manual", title: "Manual"},
		{page: "examples", title: "Examples"},
		{page: "music", title: "Music"},
		{page: "download", title: "Download"},
		{page: "about", title: "About"}
	];

	/**
		The eleven channels, as the manual names them, each with the colour it has in the
		application.
	**/
	static final PARTS:Array<String> = [
		"FM1", "FM2", "FM3", "FM4", "FM5", "FM6", "PSG1", "PSG2", "PSG3", "NOISE", "DAC"
	];

	/**
		The link a heading carries to itself, as a replacement whose first group is the heading's
		identifier.
	**/
	static inline final ANCHOR = '<a class="anchor" href="#$1" aria-label="Link to this section">#</a>';

	/**
		File types a link to the repository downloads rather than shows.
	**/
	static final DOWNLOADED:Array<String> = ["mdsyn", "zip", "vgm", "mid", "wav", "tfi", "xgm"];

	/**
		Writes every page and copies everything they show.

		@param root The repository root.
		@param project What the build file declares.
		@return False where `site/` has no layout to wrap the pages in.
	**/
	public static function write(root:String, project:Project):Bool {
		final from = root + "/" + SOURCE;

		if (!FileSystem.exists(from + "/layout.html")) {
			Sys.println("mdd: " + SOURCE + "/layout.html is missing, so there is nothing to wrap the pages in");
			return false;
		}

		final to = root + "/" + project.output + "/site";
		Run.tree(to);

		Run.copyTree(root + "/docs/images", to + "/images");
		Run.copyTree(root + "/docs/examples", to + "/examples");

		for (entry in FileSystem.readDirectory(from)) {
			if (StringTools.endsWith(entry, ".html")) continue;

			if (FileSystem.isDirectory(from + "/" + entry)) Run.copyTree(from + "/" + entry, to + "/" + entry);
			else Run.copyFile(from + "/" + entry, to + "/" + entry);
		}

		final repository = "https://github.com/" + project.github;
		final layout = File.getContent(from + "/layout.html");
		final shown = [for (tab in TABS) if (FileSystem.exists(from + "/" + tab.page + ".html")) tab];
		final manual = File.getContent(root + "/" + MANUAL);
		final readme = File.getContent(root + "/" + README);
		final listed = examples(manual);

		for (tab in shown) {
			final source = StringTools.replace(File.getContent(from + "/" + tab.page + ".html"), "\r\n", "\n");
			final split = source.indexOf("\n---\n");
			final front = split < 0 ? "" : source.substr(0, split);
			var body = split < 0 ? source : source.substr(split + 5);

			final said:Map<String, String> = new Map();
			for (line in front.split("\n")) {
				final colon = line.indexOf(":");
				if (colon <= 0) continue;
				said.set(StringTools.trim(line.substr(0, colon)), StringTools.trim(line.substr(colon + 1)));
			}

			if (body.indexOf("{{manual}}") >= 0 || body.indexOf("{{contents}}") >= 0) {
				final rendered = guide(manual, repository);
				body = StringTools.replace(body, "{{contents}}", contents(rendered.headings));
				body = StringTools.replace(body, "{{manual}}", decorated(rendered.html));
			}

			body = ~/\{\{examples(?::([\d,]+))?\}\}/g.map(body, function(found:EReg):String {
				final picked = found.matched(1) == null ? null
					: [for (number in found.matched(1).split(",")) Std.parseInt(number)];
				return cards([for (example in listed)
					if (picked == null || picked.indexOf(example.number) >= 0) example]);
			});

			body = ~/\{\{readme:([a-z0-9-]+)\}\}/g.map(body, function(found:EReg):String {
				return section(readme, found.matched(1), repository);
			});

			body = ~/\{\{playlist:([A-Za-z0-9_-]+)\}\}/g.map(body, function(found:EReg):String {
				return playlist(found.matched(1), project.title);
			});

			final titled = said.exists("title") && tab.page != "index"
				? said.get("title") + " · " + project.title : project.title;

			var page = layout;
			page = StringTools.replace(page, "{{title}}", Markdown.escape(titled));
			page = StringTools.replace(page, "{{description}}", Markdown.escape(said.exists("description")
				? said.get("description") : project.description));
			page = StringTools.replace(page, "{{page}}", tab.page);
			page = StringTools.replace(page, "{{tabs}}", tabs(shown, tab));
			page = StringTools.replace(page, "{{content}}", body);
			page = StringTools.replace(page, "{{version}}", project.version);
			page = StringTools.replace(page, "{{releases}}", repository + "/releases");
			page = StringTools.replace(page, "{{repository}}", repository);
			page = StringTools.replace(page, "{{github}}", project.github);
			page = StringTools.replace(page, "{{site}}", published(project.github));

			File.saveContent(to + "/" + tab.page + ".html", measured(page, to));
		}

		Sys.println("  " + StringTools.rpad("site", " ", 14) + shown.length + " pages and "
			+ listed.length + " examples into " + project.output + "/site/");
		return true;
	}

	/**
		Renders the manual for its page: without its title, its written table of contents or the
		links back to the top, which the page's own navigation stands in for.
	**/
	static function guide(manual:String, repository:String):Markdown {
		final kept:Array<String> = [];
		var skipping = false;
		var titled = false;

		for (line in StringTools.replace(manual, "\r\n", "\n").split("\n")) {
			final trimmed = StringTools.trim(line);

			if (!titled && StringTools.startsWith(trimmed, "# ")) {
				titled = true;
				continue;
			}

			if (trimmed == "## Contents") skipping = true;
			else if (skipping && StringTools.startsWith(trimmed, "# ")) skipping = false;

			if (skipping || trimmed == "---" || trimmed.indexOf("back to top</a>)") >= 0) continue;
			kept.push(line);
		}

		return Markdown.render(kept.join("\n"), resolver("docs", repository));
	}

	/**
		Marks up the manual's headings for the page: a part's number above its title, a section's
		number set apart from its words, a link to every heading, and the paragraphs that hold
		examples to listen to.
	**/
	static function decorated(html:String):String {
		var marked = ~/<h1 id="([^"]+)">Part (\d+): (.*?)<\/h1>/g.replace(html,
			'<h1 id="$1" class="part-title"><span class="eyebrow">Part $2</span>$3</h1>');

		marked = ~/<h2 id="([^"]+)">(\d+)\. (.*?)<\/h2>/g.replace(marked,
			'<h2 id="$1"><span class="number">$2</span>$3' + ANCHOR + '</h2>');

		marked = ~/<h3 id="([^"]+)">(.*?)<\/h3>/g.replace(marked, '<h3 id="$1">$2' + ANCHOR + '</h3>');

		return StringTools.replace(marked, "<p><strong>Hear it:</strong>", '<p class="hear"><strong>Hear it:</strong>');
	}

	/**
		The manual's navigation: its parts, their numbered sections, and the headings under each.
	**/
	static function contents(headings:Array<Markdown.Heading>):String {
		final built = new StringBuf();
		final part = ~/^Part (\d+): (.*)$/;
		final numbered = ~/^(\d+)\. (.*)$/;
		var open = false;
		var inner = false;

		built.add('<ol class="contents-list">\n');

		for (heading in headings) {
			switch (heading.level) {
				case 1:
					if (inner) built.add("</ol>");
					if (open) built.add("</li>\n");
					if (part.match(heading.plain)) {
						built.add('<li class="contents-part"><a href="#${heading.id}">'
							+ '<span class="eyebrow">Part ${part.matched(1)}</span>'
							+ '${Markdown.escape(part.matched(2))}</a></li>\n');
					}
					open = false;
					inner = false;
				case 2:
					if (inner) built.add("</ol>");
					if (open) built.add("</li>\n");
					if (numbered.match(heading.plain)) {
						built.add('<li><a href="#${heading.id}"><span class="number">${numbered.matched(1)}</span>'
							+ '${Markdown.escape(numbered.matched(2))}</a>');
					} else {
						built.add('<li><a href="#${heading.id}">${Markdown.escape(heading.plain)}</a>');
					}
					open = true;
					inner = false;
				case 3:
					if (!open) continue;
					if (!inner) built.add('<ol class="contents-sub">');
					built.add('<li><a href="#${heading.id}">${Markdown.escape(heading.plain)}</a></li>');
					inner = true;
				case _:
			}
		}

		if (inner) built.add("</ol>");
		if (open) built.add("</li>\n");
		built.add("</ol>");

		return built.toString();
	}

	/**
		Reads the examples out of the manual's table of them, and finds for each the section whose
		"Hear it" line plays it.
	**/
	static function examples(manual:String):Array<Example> {
		final lines = StringTools.replace(manual, "\r\n", "\n").split("\n");
		final row = ~/^\|\s*(\d+)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*\[[^\]]*\]\(([^)]+)\)\s*\|$/;
		final heading = ~/^(#{2,3})\s+(.*)$/;
		final numbered = ~/^(\d+)\. /;
		final linked = ~/\]\((examples\/[^)]+)\)/g;
		final explained:Map<String, Array<String>> = new Map();
		final listed:Array<Example> = [];
		var under = "";
		var section = "";
		var hearing = false;

		for (line in lines) {
			final trimmed = StringTools.trim(line);

			if (heading.match(trimmed)) {
				under = heading.matched(2);
				if (heading.matched(1).length == 2) section = numbered.match(under) ? numbered.matched(1) : "";
				hearing = false;
				continue;
			}

			if (StringTools.startsWith(trimmed, "**Hear it:**")) hearing = true;
			else if (trimmed == "") hearing = false;

			if (hearing) {
				var rest = trimmed;
				while (linked.match(rest)) {
					final audio = linked.matched(1);
					if (!explained.exists(audio)) explained.set(audio, [section, Markdown.slug(under)]);
					rest = linked.matchedRight();
				}
			}

			if (row.match(trimmed)) {
				final audio = row.matched(4);
				listed.push({
					number: Std.parseInt(row.matched(1)),
					title: row.matched(2),
					channels: row.matched(3),
					audio: audio,
					section: "",
					id: ""
				});
			}
		}

		for (example in listed) {
			if (!explained.exists(example.audio)) continue;
			example.section = explained.get(example.audio)[0];
			example.id = explained.get(example.audio)[1];
		}

		return listed;
	}

	/**
		The examples as cards, each playing its audio and linking to where the manual explains it.
	**/
	static function cards(listed:Array<Example>):String {
		final built = new StringBuf();

		built.add('<div class="examples">\n');

		for (example in listed) {
			final first = firstPart(example.channels);
			final colour = first == "" ? "var(--accent)" : "var(--" + first.toLowerCase() + ")";
			final number = StringTools.lpad(Std.string(example.number), "0", 2);
			final title = Markdown.escape(example.title);

			built.add('<article class="example reveal" style="--part:$colour">\n');
			built.add('<a class="play" href="${example.audio}" data-audio data-title="$title" aria-label="Play $title">'
				+ '<svg viewBox="0 0 24 24" aria-hidden="true"><path class="icon-play" d="M8 5.5v13l10.5-6.5z"/>'
				+ '<path class="icon-pause" d="M7 5h3.5v14H7zM13.5 5H17v14h-3.5z"/></svg></a>\n');
			built.add('<div class="example-text"><span class="example-number">$number</span>'
				+ '<h3>$title</h3><p class="channels">${channels(example.channels)}</p></div>\n');
			if (example.id != "") {
				final named = example.section == "" ? "Read how it is made" : "Read section " + example.section;
				built.add('<a class="example-more" href="manual.html#${example.id}">$named</a>\n');
			}
			built.add("</article>\n");
		}

		built.add("</div>");
		return built.toString();
	}

	/**
		The first channel a list names, which gives an example's card its colour, or nothing where
		it names none.
	**/
	static function firstPart(channels:String):String {
		final named = ~/\b(FM[1-6]|PSG[1-3]|noise|NOISE|DAC)\b/;
		return named.match(channels) ? named.matched(1).toUpperCase() : "";
	}

	/**
		A list of channels with every channel's name drawn as a chip in its colour, and the commas
		between them left out where the chips stand alone.
	**/
	static function channels(said:String):String {
		return [for (piece in said.split(",")) chipped(StringTools.trim(piece))].join("");
	}

	/**
		One piece of a list of channels, with the channel names in it drawn as chips.
	**/
	static function chipped(said:String):String {
		return ~/\b(FM[1-6]|PSG[1-3]|noise|NOISE|DAC)\b/g.map(Markdown.escape(said), function(found:EReg):String {
			final name = found.matched(1).toUpperCase();
			return PARTS.indexOf(name) < 0 ? found.matched(0)
				: '<span class="part" style="--part:var(--${name.toLowerCase()})">$name</span>';
		});
	}

	/**
		One section of the README, rendered without its own heading, which the page gives it.

		@param id The heading's identifier as GitHub gives it.
	**/
	static function section(readme:String, id:String, repository:String):String {
		final lines = StringTools.replace(readme, "\r\n", "\n").split("\n");
		final heading = ~/^(#{1,6})\s+(.*?)\s*$/;
		final definition = ~/^\[[^\]]+\]:\s*\S+\s*$/;
		final kept:Array<String> = [];
		var level = 0;
		var fenced = false;

		for (line in lines) {
			final trimmed = StringTools.trim(line);
			if (StringTools.startsWith(trimmed, "```")) fenced = !fenced;

			if (!fenced && heading.match(trimmed)) {
				final depth = heading.matched(1).length;

				if (level > 0 && depth <= level) break;
				if (level == 0 && Markdown.slug(heading.matched(2)) == id) {
					level = depth;
					continue;
				}
			}

			if (level > 0 && trimmed.indexOf("back to top</a>)") < 0) kept.push(line);
		}

		if (level == 0) throw "mdd: README.md has no section " + id;

		for (line in lines) if (definition.match(StringTools.trim(line))) kept.push(line);

		return Markdown.render(kept.join("\n"), resolver("", repository)).html;
	}

	/**
		A YouTube playlist as one player and the songs to choose from beside it, read from the
		playlist's public feed as the site is written, so a song added to the playlist is on the
		page the next time the site is published. Where the feed cannot be read, a link to the
		playlist stands in and the command says so.

		@param id The playlist's identifier.
		@param title The project's name, which the channel puts before every song's own.
	**/
	static function playlist(id:String, title:String):String {
		final address = "https://www.youtube.com/playlist?list=" + id;
		final songs = feed(id, title);
		final built = new StringBuf();

		if (songs.length == 0) {
			Sys.println("  " + StringTools.rpad("site", " ", 14) + "the playlist " + id
				+ " could not be read, so the page links to it instead");
			return '<p class="more"><a class="button" href="$address">The playlist on YouTube</a></p>';
		}

		final first = songs[0];
		final watch = "https://www.youtube.com/watch?list=" + id + "&amp;v=";

		built.add('<div class="playlist" data-list="$id">\n');
		built.add('<a class="video" href="$watch${first.id}" data-youtube="${first.id}"'
			+ ' data-title="${Markdown.escape(first.title)}">'
			+ '<img src="${first.still}" alt="" width="1280" height="720">'
			+ '<span class="video-play" aria-hidden="true">'
			+ '<svg viewBox="0 0 24 24"><path d="M8 5.5v13l10.5-6.5z"/></svg></span>'
			+ '<span class="video-title">${Markdown.escape(first.title)}</span></a>\n');
		built.add('<ol class="songs">\n');

		for (song in songs) {
			final current = song == first ? ' aria-current="true"' : "";
			built.add('<li><a class="song" href="$watch${song.id}" data-youtube="${song.id}"'
				+ ' data-title="${Markdown.escape(song.title)}"$current>'
				+ '<img src="https://i.ytimg.com/vi/${song.id}/mqdefault.jpg" alt=""'
				+ ' width="320" height="180" loading="lazy">'
				+ '<span><b>${Markdown.escape(song.title)}</b><small>${song.published}</small></span></a></li>\n');
		}

		built.add("</ol>\n</div>\n");
		built.add('<p class="more"><a class="button" href="$address">The playlist on YouTube</a></p>');

		return built.toString();
	}

	/**
		The songs in a playlist, in the playlist's order, or none where the feed cannot be fetched or
		read. It fetches through `curl`, which the build already needs.
	**/
	static function feed(id:String, title:String):Array<Song> {
		final songs:Array<Song> = [];

		try {
			final run = new sys.io.Process("curl", ["-sL", "--fail", "-m", "30",
				"https://www.youtube.com/feeds/videos.xml?playlist_id=" + id]);
			final said = run.stdout.readAll().toString();
			final code = run.exitCode();
			run.close();
			if (code != 0) return [];

			final months = ["January", "February", "March", "April", "May", "June", "July", "August",
				"September", "October", "November", "December"];

			for (entry in Xml.parse(said).firstElement().elementsNamed("entry")) {
				final video = text(entry, "yt:videoId");
				final day = text(entry, "published").split("T")[0].split("-");
				final published = day.length == 3
					? Std.parseInt(day[2]) + " " + months[Std.parseInt(day[1]) - 1] + " " + day[0] : "";
				var named = text(entry, "title");
				final bar = named.indexOf(" | ");
				if (bar > 0) named = named.substr(0, bar);
				if (StringTools.startsWith(named, title + " - ")) named = named.substr(title.length + 3);

				final large = "https://i.ytimg.com/vi/" + video + "/maxresdefault.jpg";
				songs.push({
					id: video,
					title: StringTools.trim(named),
					published: published,
					still: exists(large) ? large : "https://i.ytimg.com/vi/" + video + "/hqdefault.jpg"
				});
			}
		} catch (e:Dynamic) {
			return [];
		}

		return songs;
	}

	/**
		The text of the first element of a name inside another, or nothing where it has none.
	**/
	static function text(parent:Xml, name:String):String {
		for (child in parent.elementsNamed(name)) {
			final inner = child.firstChild();
			return inner == null ? "" : inner.nodeValue;
		}
		return "";
	}

	/**
		Whether an address answers with something rather than an error.
	**/
	static function exists(address:String):Bool {
		try {
			final run = new sys.io.Process("curl", ["-sI", "--fail", "-m", "15", address]);
			run.stdout.readAll();
			final code = run.exitCode();
			run.close();
			return code == 0;
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
		The header's tabs, with the one for this page marked.
	**/
	static function tabs(shown:Array<Tab>, here:Tab):String {
		final built = new StringBuf();

		for (tab in shown) {
			if (tab == here) {
				built.add('<a class="tab" href="${tab.page}.html" aria-current="page">${tab.title}'
					+ '<span class="tab-mark"></span></a>');
			} else {
				built.add('<a class="tab" href="${tab.page}.html">${tab.title}</a>');
			}
		}

		return built.toString();
	}

	/**
		Turns a link a document wrote into the one the website uses. The documents' pictures and
		examples are published with the site, a link to the manual stays on the site, and anything
		else in the repository is reached on GitHub.

		@param base The folder the document sits in, from the repository root.
	**/
	static function resolver(base:String, repository:String):String->String {
		return function(href:String):String {
			if (href == "#readme-top") return "#top";
			if (StringTools.startsWith(href, "#") || ~/^[a-z][a-z0-9+.-]*:/i.match(href)) return href;

			final hash = href.indexOf("#");
			final fragment = hash < 0 ? "" : href.substr(hash);
			final path = normalised((base == "" ? "" : base + "/") + (hash < 0 ? href : href.substr(0, hash)));

			if (StringTools.startsWith(path, "docs/images/") || StringTools.startsWith(path, "docs/examples/")) {
				return path.substr(5) + fragment;
			}

			if (path == MANUAL) return "manual.html" + fragment;

			final extension = haxe.io.Path.extension(path).toLowerCase();
			final way = DOWNLOADED.indexOf(extension) >= 0 ? "/raw/main/" : "/blob/main/";

			return repository + way + path + fragment;
		};
	}

	/**
		Where GitHub Pages publishes the website of a repository.

		@param github The repository as owner and name.
	**/
	public static function published(github:String):String {
		final slash = github.indexOf("/");
		return "https://" + github.substr(0, slash).toLowerCase() + ".github.io/" + github.substr(slash + 1) + "/";
	}

	/**
		A path from the repository root with every `.` and `..` in it resolved.
	**/
	static function normalised(path:String):String {
		final kept:Array<String> = [];

		for (part in path.split("/")) {
			if (part == "" || part == ".") continue;
			if (part == "..") kept.pop();
			else kept.push(part);
		}

		return kept.join("/");
	}

	/**
		Gives every picture published with the site the size it is drawn at, so the page does not
		move as the pictures arrive.
	**/
	static function measured(page:String, to:String):String {
		return ~/<img src="([^"]+)"([^>]*)>/g.map(page, function(found:EReg):String {
			final src = found.matched(1);
			final rest = found.matched(2);
			if (rest.indexOf("width=") >= 0 || ~/^[a-z]+:/i.match(src)
				|| !StringTools.endsWith(src.toLowerCase(), ".png")) return found.matched(0);

			final path = to + "/" + src;
			if (!FileSystem.exists(path)) return found.matched(0);

			final input = File.read(path, true);
			final head = input.read(24);
			input.close();

			final width = (head.get(16) << 24) | (head.get(17) << 16) | (head.get(18) << 8) | head.get(19);
			final height = (head.get(20) << 24) | (head.get(21) << 16) | (head.get(22) << 8) | head.get(23);

			return '<img src="$src" width="$width" height="$height"$rest>';
		});
	}
}
