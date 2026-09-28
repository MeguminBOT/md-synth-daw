/**
	A heading a document holds: how deep it sits, its text as HTML and as plain words, and the
	identifier a link reaches it by.
**/
typedef Heading = {
	level:Int,
	html:String,
	plain:String,
	id:String
}

/**
	Renders the Markdown the repository's documents are written in, for the website.

	It reads what those documents use and nothing more: headings, paragraphs, lists, tables, fenced
	code, quotes, pictures on a line of their own, links inline and by reference, bold, italic and
	code spans. A line of raw HTML passes through untouched. Every heading takes the identifier
	GitHub gives it, so a link written against the repository lands in the same place on the site.
**/
class Markdown {
	static final HEADING = ~/^(#{1,6})\s+(.*?)\s*#*\s*$/;
	static final BULLET = ~/^[-*+]\s+(.*)$/;
	static final NUMBERED = ~/^(\d+)[.)]\s+(.*)$/;
	static final PICTURE = ~/^!\[([^\]]*)\]\(([^)\s]+)\)$/;
	static final DEFINITION = ~/^\[([^\]]+)\]:\s*(\S+)\s*$/;
	static final DIVIDER = ~/^(-{3,}|\*{3,}|_{3,})$/;
	static final SEPARATOR = ~/^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?$/;
	static final AUDIO = ~/\.(opus|ogg|wav|flac|mp3)$/i;

	/**
		Every heading, in the order the document has them.
	**/
	public final headings:Array<Heading> = [];

	/**
		The document as HTML.
	**/
	public var html(default, null):String = "";

	final resolve:String->String;
	final references:Map<String, String> = new Map();
	final taken:Map<String, Int> = new Map();
	final out:StringBuf = new StringBuf();

	/**
		Renders a document.

		@param text The Markdown, with either line ending.
		@param resolve Turns a link or a picture's address as the document wrote it into the one the
			page uses.
		@return The rendered document, with its headings.
	**/
	public static function render(text:String, resolve:String->String):Markdown {
		final markdown = new Markdown(resolve);
		markdown.read(StringTools.replace(text, "\r\n", "\n").split("\n"));
		return markdown;
	}

	/**
		The identifier GitHub gives a heading: lower case, spaces as hyphens, punctuation dropped.

		@param plain The heading's words, with no markup left in them.
		@return The identifier, before any suffix a repeated heading takes.
	**/
	public static function slug(plain:String):String {
		final built = new StringBuf();

		for (code in new haxe.iterators.StringIteratorUnicode(plain.toLowerCase())) {
			if ((code >= "a".code && code <= "z".code) || (code >= "0".code && code <= "9".code)
				|| code == "-".code || code == "_".code || code >= 0x80) {
				built.addChar(code);
			} else if (code == " ".code) {
				built.addChar("-".code);
			}
		}

		return built.toString();
	}

	/**
		Escapes text for HTML.

		@param text Anything.
		@return It with ampersands, angle brackets and quotes written as entities.
	**/
	public static function escape(text:String):String {
		return StringTools.replace(StringTools.htmlEscape(text), "\"", "&quot;");
	}

	function new(resolve:String->String) {
		this.resolve = resolve;
	}

	function read(lines:Array<String>):Void {
		for (line in lines) {
			if (DEFINITION.match(StringTools.trim(line))) {
				references.set(DEFINITION.matched(1).toLowerCase(), DEFINITION.matched(2));
			}
		}

		var at = 0;

		while (at < lines.length) {
			final trimmed = StringTools.trim(lines[at]);

			if (trimmed == "" || DEFINITION.match(trimmed)) {
				at++;
			} else if (StringTools.startsWith(trimmed, "```")) {
				at = fence(lines, at);
			} else if (HEADING.match(trimmed)) {
				heading(HEADING.matched(1).length, HEADING.matched(2));
				at++;
			} else if (DIVIDER.match(trimmed)) {
				out.add("<hr>\n");
				at++;
			} else if (StringTools.startsWith(trimmed, "<")) {
				out.add(trimmed + "\n");
				at++;
			} else if (tabled(lines, at)) {
				at = table(lines, at);
			} else if (BULLET.match(trimmed) || NUMBERED.match(trimmed)) {
				at = list(lines, at);
			} else if (PICTURE.match(trimmed)) {
				figure(PICTURE.matched(1), PICTURE.matched(2));
				at++;
			} else if (StringTools.startsWith(trimmed, ">")) {
				at = quote(lines, at);
			} else {
				at = paragraph(lines, at);
			}
		}

		html = out.toString();
	}

	function heading(level:Int, text:String):Void {
		final rendered = spans(text);
		final plain = StringTools.htmlUnescape(~/<[^>]*>/g.replace(rendered, ""));
		final base = slug(plain);
		final seen = taken.exists(base) ? taken.get(base) : 0;
		final id = seen == 0 ? base : base + "-" + seen;

		taken.set(base, seen + 1);
		headings.push({level: level, html: rendered, plain: plain, id: id});
		out.add('<h$level id="$id">$rendered</h$level>\n');
	}

	function fence(lines:Array<String>, at:Int):Int {
		final language = StringTools.trim(StringTools.trim(lines[at]).substr(3));
		final code:Array<String> = [];
		var next = at + 1;

		while (next < lines.length && !StringTools.startsWith(StringTools.trim(lines[next]), "```")) {
			code.push(lines[next]);
			next++;
		}

		final named = language == "" ? "" : ' class="language-${escape(language)}"';
		out.add('<pre><code$named>${escape(code.join("\n"))}</code></pre>\n');
		return next + 1;
	}

	/**
		Whether a table starts on this line: a row with the separator row under it.
	**/
	function tabled(lines:Array<String>, at:Int):Bool {
		return StringTools.startsWith(StringTools.trim(lines[at]), "|") && at + 1 < lines.length
			&& SEPARATOR.match(StringTools.trim(lines[at + 1]));
	}

	function table(lines:Array<String>, at:Int):Int {
		final head = cells(lines[at]);
		final aligns:Array<String> = [];

		for (cell in cells(lines[at + 1])) {
			final left = StringTools.startsWith(cell, ":");
			final right = StringTools.endsWith(cell, ":");
			aligns.push(left && right ? "center" : right ? "right" : left ? "left" : "");
		}

		out.add('<div class="table"><table>\n');
		if (head.join("") != "") {
			out.add("<thead><tr>");
			for (i in 0...head.length) out.add('<th${aligned(aligns, i)}>${spans(head[i])}</th>');
			out.add("</tr></thead>\n");
		}
		out.add("<tbody>\n");

		var next = at + 2;

		while (next < lines.length && StringTools.startsWith(StringTools.trim(lines[next]), "|")) {
			final row = cells(lines[next]);
			out.add("<tr>");
			for (i in 0...head.length) {
				out.add('<td${aligned(aligns, i)}>${i < row.length ? spans(row[i]) : ""}</td>');
			}
			out.add("</tr>\n");
			next++;
		}

		out.add("</tbody>\n</table></div>\n");
		return next;
	}

	function cells(line:String):Array<String> {
		var trimmed = StringTools.trim(line);
		if (StringTools.startsWith(trimmed, "|")) trimmed = trimmed.substr(1);
		if (StringTools.endsWith(trimmed, "|")) trimmed = trimmed.substr(0, trimmed.length - 1);

		return [for (cell in trimmed.split("|")) StringTools.trim(cell)];
	}

	/**
		The style a table cell takes from its column's alignment, or nothing where the column set none.
	**/
	function aligned(aligns:Array<String>, index:Int):String {
		return index < aligns.length && aligns[index] != "" ? ' style="text-align:${aligns[index]}"' : "";
	}

	/**
		Renders a list and returns the line after it. A numbered list interrupted by a picture or a
		table goes on in a list of its own that starts at the number it had reached.
	**/
	function list(lines:Array<String>, at:Int):Int {
		final ordered = NUMBERED.match(StringTools.trim(lines[at]));
		final first = ordered ? Std.parseInt(NUMBERED.matched(1)) : 1;

		out.add(!ordered ? "<ul>\n" : first == 1 ? "<ol>\n" : '<ol start="$first">\n');

		var next = at;

		while (next < lines.length) {
			final trimmed = StringTools.trim(lines[next]);
			final marker = ordered ? NUMBERED : BULLET;
			if (!marker.match(trimmed)) break;

			final parts:Array<Array<String>> = [[ordered ? marker.matched(2) : marker.matched(1)]];
			next++;

			while (next < lines.length) {
				final line = lines[next];
				final inner = StringTools.trim(line);

				if (inner == "") {
					final after = next + 1 < lines.length ? lines[next + 1] : "";
					if (StringTools.startsWith(after, "  ") && StringTools.trim(after) != "") {
						parts.push([]);
						next++;
						continue;
					}
					break;
				}

				if (!StringTools.startsWith(line, " ") && starts(lines, next)) break;

				parts[parts.length - 1].push(inner);
				next++;
			}

			out.add("<li>");
			if (parts.length == 1) {
				out.add(spans(parts[0].join("\n")));
			} else {
				for (part in parts) out.add("<p>" + spans(part.join("\n")) + "</p>");
			}
			out.add("</li>\n");

			var skip = next;
			while (skip < lines.length && StringTools.trim(lines[skip]) == "") skip++;
			if (skip < lines.length && marker.match(StringTools.trim(lines[skip]))
				&& !StringTools.startsWith(lines[skip], " ")) {
				next = skip;
			} else {
				break;
			}
		}

		out.add(ordered ? "</ol>\n" : "</ul>\n");
		return next;
	}

	function figure(alt:String, src:String):Void {
		out.add('<figure><img src="${escape(resolve(src))}" alt="${escape(alt)}" loading="lazy"'
			+ ' decoding="async"></figure>\n');
	}

	function quote(lines:Array<String>, at:Int):Int {
		final said:Array<String> = [];
		var next = at;

		while (next < lines.length && StringTools.startsWith(StringTools.trim(lines[next]), ">")) {
			said.push(StringTools.trim(StringTools.trim(lines[next]).substr(1)));
			next++;
		}

		out.add("<blockquote><p>" + spans(said.join("\n")) + "</p></blockquote>\n");
		return next;
	}

	function paragraph(lines:Array<String>, at:Int):Int {
		final said:Array<String> = [StringTools.trim(lines[at])];
		var next = at + 1;

		while (next < lines.length && StringTools.trim(lines[next]) != "" && !starts(lines, next)) {
			said.push(StringTools.trim(lines[next]));
			next++;
		}

		out.add("<p>" + spans(said.join("\n")) + "</p>\n");
		return next;
	}

	/**
		Whether this line starts a block of its own, which ends the paragraph or the list item before it.
	**/
	function starts(lines:Array<String>, at:Int):Bool {
		final trimmed = StringTools.trim(lines[at]);

		return StringTools.startsWith(trimmed, "```") || HEADING.match(trimmed)
			|| StringTools.startsWith(trimmed, "<") || tabled(lines, at) || BULLET.match(trimmed)
			|| NUMBERED.match(trimmed) || PICTURE.match(trimmed) || StringTools.startsWith(trimmed, ">")
			|| DIVIDER.match(trimmed);
	}

	/**
		Renders the text inside a block: code, links, pictures, bold and italic. Code and links are
		set aside while the rest is escaped and marked up, so nothing inside them is read twice.
	**/
	function spans(text:String):String {
		final codes:Array<String> = [];
		final links:Array<String> = [];

		var said = ~/`([^`]+)`/g.map(text, function(found:EReg):String {
			codes.push("<code>" + escape(found.matched(1)) + "</code>");
			return "\x00" + (codes.length - 1) + "\x00";
		});

		said = ~/<(https?:\/\/[^>\s]+)>/g.map(said, function(found:EReg):String {
			final href = escape(found.matched(1));
			links.push('<a href="$href">$href</a>');
			return "\x01" + (links.length - 1) + "\x01";
		});

		said = escape(said);

		said = ~/!\[([^\]]*)\]\(([^)\s]+)\)/g.map(said, function(found:EReg):String {
			links.push('<img src="${escape(resolve(StringTools.htmlUnescape(found.matched(2))))}"'
				+ ' alt="${found.matched(1)}" loading="lazy" decoding="async">');
			return "\x01" + (links.length - 1) + "\x01";
		});

		said = ~/\[([^\]]+)\]\(([^)\s]+)\)/g.map(said, function(found:EReg):String {
			links.push(anchor(found.matched(1), StringTools.htmlUnescape(found.matched(2))));
			return "\x01" + (links.length - 1) + "\x01";
		});

		said = ~/\[([^\]]+)\]\[([^\]]*)\]/g.map(said, function(found:EReg):String {
			final key = (found.matched(2) == "" ? found.matched(1) : found.matched(2)).toLowerCase();
			if (!references.exists(key)) return found.matched(0);

			links.push(anchor(found.matched(1), references.get(key)));
			return "\x01" + (links.length - 1) + "\x01";
		});

		said = emphasis(said);

		while (said.indexOf("\x01") >= 0) {
			said = ~/\x01(\d+)\x01/g.map(said, function(found:EReg):String {
				return links[Std.parseInt(found.matched(1))];
			});
		}

		return ~/\x00(\d+)\x00/g.map(said, function(found:EReg):String {
			return codes[Std.parseInt(found.matched(1))];
		});
	}

	/**
		A link, marked as one that plays in the page where it leads to audio.
	**/
	function anchor(text:String, href:String):String {
		final target = resolve(href);
		final heard = AUDIO.match(target.split("#")[0]);
		final attributes = heard ? ' class="listen" data-audio' : "";

		return '<a href="${escape(target)}"$attributes>${emphasis(text)}</a>';
	}

	/**
		Bold and italic, marked with asterisks. An asterisk inside a word is left alone.
	**/
	function emphasis(text:String):String {
		final bold = ~/\*\*([^*]+?)\*\*/g.replace(text, "<strong>$1</strong>");
		return ~/(^|[^*\w])\*([^*\s][^*]*?)\*(?![*\w])/g.replace(bold, "$1<em>$2</em>");
	}
}
