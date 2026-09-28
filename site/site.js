"use strict";

const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");

const loudness = { level: 0.5, muted: false };

try {
	const kept = parseFloat(localStorage.getItem("mdd-volume"));
	if (kept >= 0 && kept <= 1) loudness.level = kept;
} catch (error) {}

function heard() {
	return loudness.muted ? 0 : loudness.level;
}

function keepLoudness() {
	try {
		localStorage.setItem("mdd-volume", String(loudness.level));
	} catch (error) {}
}

function reveal() {
	const pending = document.querySelectorAll(".reveal");
	if (!pending.length) return;

	if (!("IntersectionObserver" in window) || reduced.matches) {
		pending.forEach((element) => element.classList.add("shown"));
		return;
	}

	const watcher = new IntersectionObserver((entries) => {
		for (const entry of entries) {
			if (!entry.isIntersecting) continue;
			entry.target.classList.add("shown");
			watcher.unobserve(entry.target);
		}
	}, { rootMargin: "0px 0px -8% 0px" });

	const rows = new Map();
	pending.forEach((element) => {
		const parent = element.parentElement;
		const index = rows.get(parent) || 0;
		rows.set(parent, index + 1);
		element.style.setProperty("--delay", Math.min(index, 8) * 0.05 + "s");
		watcher.observe(element);
	});
}

function clock(seconds) {
	if (!isFinite(seconds) || seconds < 0) seconds = 0;
	const whole = Math.floor(seconds);
	return Math.floor(whole / 60) + ":" + String(whole % 60).padStart(2, "0");
}

function player() {
	const bar = document.querySelector(".player");
	if (!bar) return;

	const audio = new Audio();
	audio.preload = "auto";

	const toggle = bar.querySelector(".player-toggle");
	const title = bar.querySelector(".player-title");
	const now = bar.querySelector(".player-now");
	const length = bar.querySelector(".player-length");
	const seek = bar.querySelector(".player-seek");
	const close = bar.querySelector(".player-close");
	const scope = bar.querySelector(".player-scope");
	const mute = bar.querySelector(".player-mute");
	const level = bar.querySelector(".player-level");
	const pen = scope.getContext("2d");

	let source = "";
	let analyser = null;
	let gain = null;
	let samples = null;
	let context = null;
	let drawing = 0;
	let dragging = false;

	const served = location.protocol === "http:" || location.protocol === "https:";

	function mark() {
		const playing = !audio.paused;
		document.querySelectorAll("[data-audio]").forEach((link) => {
			const same = link.getAttribute("href") === source;
			link.classList.toggle("playing", same && playing);
			const card = link.closest(".example");
			if (card && link.classList.contains("play")) card.classList.toggle("playing", same && playing);
		});
		bar.classList.toggle("running", playing);
		toggle.setAttribute("aria-label", playing ? "Pause" : "Play");
	}

	function listen() {
		if (analyser || !served || !window.AudioContext) return;
		try {
			context = new AudioContext();
			const input = context.createMediaElementSource(audio);
			analyser = context.createAnalyser();
			analyser.fftSize = 1024;
			samples = new Float32Array(analyser.fftSize);
			gain = context.createGain();
			input.connect(analyser);
			analyser.connect(gain);
			gain.connect(context.destination);
		} catch (error) {
			analyser = null;
			gain = null;
		}
		bar.classList.toggle("scoped", analyser !== null);
		loud();
	}

	function loud() {
		if (gain) {
			gain.gain.value = heard();
			audio.volume = 1;
		} else {
			audio.volume = heard();
		}
		level.value = Math.round(loudness.level * 100);
		level.style.setProperty("--done", loudness.level * 100 + "%");
		bar.classList.toggle("muted", heard() === 0);
		mute.setAttribute("aria-label", loudness.muted ? "Unmute" : "Mute");
	}

	function sized() {
		const ratio = window.devicePixelRatio || 1;
		const width = Math.round(scope.clientWidth * ratio);
		const height = Math.round(scope.clientHeight * ratio);
		if (scope.width !== width || scope.height !== height) {
			scope.width = width;
			scope.height = height;
		}
	}

	function draw() {
		drawing = 0;
		if (!analyser) return;
		sized();

		const width = scope.width;
		const height = scope.height;
		analyser.getFloatTimeDomainData(samples);

		let start = 0;
		for (let i = 1; i < samples.length / 2; i++) {
			if (samples[i - 1] < 0 && samples[i] >= 0) {
				start = i;
				break;
			}
		}

		pen.clearRect(0, 0, width, height);
		pen.strokeStyle = getComputedStyle(scope).color;
		pen.lineWidth = Math.max(1, (window.devicePixelRatio || 1) * 1.5);
		pen.lineJoin = "round";
		pen.beginPath();

		const span = samples.length / 2;
		for (let i = 0; i < span; i++) {
			const x = (i / (span - 1)) * width;
			const y = height / 2 - Math.max(-1, Math.min(1, samples[start + i] * 2)) * height * 0.45;
			if (i === 0) pen.moveTo(x, y);
			else pen.lineTo(x, y);
		}

		pen.stroke();
		if (!audio.paused) drawing = requestAnimationFrame(draw);
	}

	function tick() {
		if (dragging) return;
		const done = isFinite(audio.duration) && audio.duration > 0 ? audio.currentTime / audio.duration : 0;
		seek.value = Math.round(done * 1000);
		seek.style.setProperty("--done", done * 100 + "%");
		now.textContent = clock(audio.currentTime);
	}

	function play(href, name, colour) {
		if (href === source) {
			if (audio.paused) audio.play();
			else audio.pause();
			return;
		}

		source = href;
		audio.src = href;
		title.textContent = name;
		bar.style.setProperty("--part", colour || "");
		length.textContent = "0:00";
		bar.hidden = false;
		document.body.classList.add("listening");
		listen();
		if (context && context.state === "suspended") context.resume();
		audio.play().catch(() => mark());
	}

	function stop() {
		audio.pause();
		audio.removeAttribute("src");
		audio.load();
		source = "";
		bar.hidden = true;
		document.body.classList.remove("listening");
		mark();
	}

	document.addEventListener("click", (event) => {
		const link = event.target.closest("[data-audio]");
		if (!link || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey) return;
		event.preventDefault();

		const card = link.closest(".example");
		const colour = card ? getComputedStyle(card).getPropertyValue("--part").trim() : "";
		const name = link.dataset.title || link.textContent.trim();
		play(link.getAttribute("href"), name, colour);
	});

	toggle.addEventListener("click", () => {
		if (audio.paused) audio.play();
		else audio.pause();
	});

	close.addEventListener("click", stop);

	level.addEventListener("input", () => {
		loudness.level = level.value / 100;
		loudness.muted = false;
		loud();
	});

	level.addEventListener("change", keepLoudness);

	mute.addEventListener("click", () => {
		loudness.muted = !loudness.muted;
		loud();
	});

	loud();

	seek.addEventListener("input", () => {
		dragging = true;
		seek.style.setProperty("--done", seek.value / 10 + "%");
		if (isFinite(audio.duration)) now.textContent = clock((seek.value / 1000) * audio.duration);
	});

	seek.addEventListener("change", () => {
		dragging = false;
		if (isFinite(audio.duration)) audio.currentTime = (seek.value / 1000) * audio.duration;
	});

	audio.addEventListener("durationchange", () => {
		length.textContent = clock(audio.duration);
	});

	audio.addEventListener("timeupdate", tick);

	audio.addEventListener("play", () => {
		mark();
		if (!drawing) drawing = requestAnimationFrame(draw);
	});

	audio.addEventListener("pause", mark);

	audio.addEventListener("ended", () => {
		audio.currentTime = 0;
		tick();
		mark();
	});

	document.addEventListener("keydown", (event) => {
		if (event.key === "Escape" && !bar.hidden && document.querySelector(".lightbox").hidden) stop();
	});
}

function lightbox() {
	const box = document.querySelector(".lightbox");
	if (!box) return;

	const picture = box.querySelector("img");
	const caption = box.querySelector("figcaption");
	let group = [];
	let index = 0;
	let returnTo = null;

	function show(at) {
		index = (at + group.length) % group.length;
		const source = group[index];
		picture.src = source.currentSrc || source.src;
		picture.alt = source.alt;
		caption.textContent = source.alt;
		caption.hidden = !source.alt;
	}

	function open(image) {
		const holder = image.closest("[data-gallery]") || image.closest(".prose") || image.parentElement;
		group = Array.from(holder.querySelectorAll("img")).filter((each) => !each.closest(".example"));
		if (!group.includes(image)) group = [image];
		returnTo = document.activeElement;
		box.classList.toggle("single", group.length < 2);
		show(group.indexOf(image));
		box.hidden = false;
		document.documentElement.style.overflow = "hidden";
		box.querySelector(".lightbox-close").focus({ preventScroll: true });
	}

	function shut() {
		box.hidden = true;
		document.documentElement.style.overflow = "";
		if (returnTo) returnTo.focus({ preventScroll: true });
	}

	document.addEventListener("click", (event) => {
		const image = event.target.closest(".prose figure img, .window img, .shots img");
		if (!image) return;
		event.preventDefault();
		open(image);
	});

	box.addEventListener("click", (event) => {
		if (event.target === box || event.target.closest(".lightbox-close")) shut();
		else if (event.target.closest(".lightbox-previous")) show(index - 1);
		else if (event.target.closest(".lightbox-next")) show(index + 1);
	});

	document.addEventListener("keydown", (event) => {
		if (box.hidden) return;
		if (event.key === "Escape") shut();
		else if (event.key === "ArrowLeft") show(index - 1);
		else if (event.key === "ArrowRight") show(index + 1);
	});
}

function spy(links, sections, onChange) {
	if (!sections.length || !("IntersectionObserver" in window)) return;

	const visible = new Set();
	let current = null;

	const watcher = new IntersectionObserver((entries) => {
		for (const entry of entries) {
			if (entry.isIntersecting) visible.add(entry.target);
			else visible.delete(entry.target);
		}

		let chosen = null;
		for (const section of sections) {
			if (visible.has(section)) {
				chosen = section;
				break;
			}
		}

		if (!chosen) {
			for (const section of sections) {
				if (section.getBoundingClientRect().top < window.innerHeight * 0.3) chosen = section;
			}
		}

		if (!chosen || chosen === current) return;
		current = chosen;
		onChange(links.get(chosen.id));
	}, { rootMargin: "-72px 0px -62% 0px" });

	sections.forEach((section) => watcher.observe(section));
}

function contents() {
	const nav = document.querySelector(".contents");
	if (!nav) return;

	const scroller = nav.querySelector(".contents-scroll");
	const links = new Map();
	nav.querySelectorAll(".contents-list a").forEach((link) => {
		links.set(decodeURIComponent(link.hash.slice(1)), link);
	});

	const sections = Array.from(document.querySelectorAll(".prose h1[id], .prose h2[id], .prose h3[id]"))
		.filter((heading) => links.has(heading.id));

	spy(links, sections, (link) => {
		if (!link) return;
		nav.querySelectorAll("a.active").forEach((each) => each.classList.remove("active"));
		nav.querySelectorAll("li.open").forEach((each) => each.classList.remove("open"));
		link.classList.add("active");

		const item = link.closest(".contents-sub") ? link.closest(".contents-sub").parentElement : link.parentElement;
		if (item) item.classList.add("open");

		const top = link.offsetTop - scroller.offsetTop;
		if (top < scroller.scrollTop + 40 || top > scroller.scrollTop + scroller.clientHeight - 80) {
			scroller.scrollTo({ top: top - scroller.clientHeight / 3, behavior: reduced.matches ? "auto" : "smooth" });
		}
	});

	const filter = nav.querySelector(".contents-filter input");
	if (filter) {
		filter.addEventListener("input", () => {
			const wanted = filter.value.trim().toLowerCase();
			nav.classList.toggle("filtering", wanted !== "");
			nav.querySelectorAll(".contents-list li").forEach((item) => {
				if (item.classList.contains("contents-part")) {
					item.hidden = wanted !== "";
					return;
				}
				item.hidden = wanted !== "" && !item.textContent.toLowerCase().includes(wanted);
			});
		});
	}

	const toggle = document.querySelector(".contents-toggle");
	if (toggle) {
		toggle.addEventListener("click", () => {
			const open = !nav.classList.contains("open");
			nav.classList.toggle("open", open);
			toggle.setAttribute("aria-expanded", String(open));
		});

		const shut = () => {
			nav.classList.remove("open");
			toggle.setAttribute("aria-expanded", "false");
		};

		nav.addEventListener("click", (event) => {
			if (event.target.closest("a")) shut();
		});

		document.addEventListener("click", (event) => {
			if (nav.classList.contains("open") && !nav.contains(event.target) && !toggle.contains(event.target)) shut();
		});

		document.addEventListener("keydown", (event) => {
			if (event.key === "Escape" && nav.classList.contains("open")) {
				shut();
				toggle.focus();
			}
		});
	}
}

function aboutNav() {
	const nav = document.querySelector(".about-nav");
	if (!nav) return;

	const links = new Map();
	nav.querySelectorAll("a").forEach((link) => links.set(link.hash.slice(1), link));
	const sections = Array.from(document.querySelectorAll(".about section[id]"));

	spy(links, sections, (link) => {
		nav.querySelectorAll("a.active").forEach((each) => each.classList.remove("active"));
		if (link) link.classList.add("active");
	});
}

function platform() {
	const said = (navigator.userAgentData && navigator.userAgentData.platform) || navigator.platform || "";
	const agent = navigator.userAgent || "";
	if (/android|iphone|ipad/i.test(agent)) return "";
	if (/win/i.test(said) || /windows/i.test(agent)) return "windows";
	if (/mac/i.test(said) || /mac os/i.test(agent)) return "mac";
	if (/linux|x11/i.test(said) || /linux/i.test(agent)) return "linux";
	return "";
}

const NAMES = { windows: "Windows", mac: "macOS", linux: "Linux" };

function size(bytes) {
	return bytes >= 1048576 ? (bytes / 1048576).toFixed(1) + " MB" : Math.round(bytes / 1024) + " kB";
}

async function downloads() {
	const here = platform();

	document.querySelectorAll("[data-download]").forEach((button) => {
		if (!here) return;
		const label = button.querySelector("span") || button;
		label.textContent = "Download for " + NAMES[here];
	});

	const cards = document.querySelectorAll(".platform");
	if (!cards.length) return;

	cards.forEach((card) => card.classList.toggle("here", card.dataset.os === here));

	let release = null;
	try {
		const answer = await fetch("https://api.github.com/repos/" + document.body.dataset.github + "/releases?per_page=10", {
			headers: { Accept: "application/vnd.github+json" }
		});
		if (!answer.ok) return;
		const releases = await answer.json();
		release = releases.find((each) => !each.draft) || null;
	} catch (error) {
		return;
	}

	if (!release) return;

	const version = document.querySelector("[data-release-version]");
	if (version) version.textContent = release.tag_name.replace(/^v/, "");

	const badge = document.querySelector("[data-release-badge]");
	if (badge) badge.hidden = !release.prerelease;

	const date = document.querySelector("[data-release-date]");
	if (date && release.published_at) {
		date.textContent = new Date(release.published_at).toLocaleDateString(undefined, {
			year: "numeric", month: "long", day: "numeric"
		});
	}

	const notes = document.querySelector("[data-release-notes]");
	if (notes) notes.href = release.html_url;

	document.querySelectorAll("[data-asset]").forEach((link) => {
		const ending = link.dataset.asset;
		const asset = release.assets.find((each) => each.name.endsWith(ending));
		if (!asset) return;
		link.href = asset.browser_download_url;
		const small = link.querySelector("small");
		if (small) small.textContent = small.textContent.split(" · ")[0] + " · " + size(asset.size);
		link.title = asset.name;
	});
}

function toTop() {
	const button = document.querySelector(".to-top");
	if (!button) return;

	let shown = false;
	const check = () => {
		const want = window.scrollY > 900;
		if (want === shown) return;
		shown = want;
		button.classList.toggle("shown", want);
	};

	window.addEventListener("scroll", check, { passive: true });
	check();
}

let youtubeReady = null;

function youtube() {
	if (!youtubeReady) {
		youtubeReady = new Promise((resolve, reject) => {
			if (window.YT && window.YT.Player) {
				resolve(window.YT);
				return;
			}
			const previous = window.onYouTubeIframeAPIReady;
			window.onYouTubeIframeAPIReady = () => {
				if (previous) previous();
				resolve(window.YT);
			};
			const script = document.createElement("script");
			script.src = "https://www.youtube.com/iframe_api";
			script.onerror = () => {
				youtubeReady = null;
				reject(new Error("the YouTube player did not load"));
			};
			document.head.appendChild(script);
		});
	}
	return youtubeReady;
}

function videos() {
	document.querySelectorAll(".playlist").forEach((holder) => {
		const list = holder.dataset.list;
		const songs = holder.querySelectorAll(".song");
		let stage = holder.querySelector(".video");
		let video = null;

		if (location.protocol === "file:") {
			holder.querySelectorAll("a").forEach((link) => {
				link.target = "_blank";
				link.rel = "noopener";
			});
			return;
		}

		function current(id) {
			songs.forEach((song) => song.toggleAttribute("aria-current", song.dataset.youtube === id));
		}

		async function start(id, address) {
			current(id);
			if (video) {
				video.destroy();
				video = null;
			}

			const box = document.createElement("div");
			box.className = "video started";
			const mount = document.createElement("div");
			box.appendChild(mount);
			stage.replaceWith(box);
			stage = box;

			let api = null;
			try {
				api = await youtube();
			} catch (error) {
				location.href = address;
				return;
			}

			video = new api.Player(mount, {
				host: "https://www.youtube-nocookie.com",
				videoId: id,
				playerVars: { list: list, listType: "playlist", rel: 0, playsinline: 1, origin: location.origin },
				events: {
					onReady: (event) => {
						event.target.setVolume(Math.round(heard() * 100));
						event.target.playVideo();
					},
					onStateChange: (event) => {
						const data = event.target.getVideoData ? event.target.getVideoData() : null;
						if (data && data.video_id) current(data.video_id);
					}
				}
			});
		}

		function wanted(event) {
			return event.button === 0 && !event.metaKey && !event.ctrlKey && !event.shiftKey;
		}

		stage.addEventListener("click", (event) => {
			if (!wanted(event)) return;
			event.preventDefault();
			start(stage.dataset.youtube, stage.href);
		});

		songs.forEach((song) => {
			song.addEventListener("click", (event) => {
				if (!wanted(event)) return;
				event.preventDefault();
				start(song.dataset.youtube, song.href);
			});
		});
	});
}

reveal();
player();
lightbox();
contents();
aboutNav();
downloads();
toTop();
videos();
