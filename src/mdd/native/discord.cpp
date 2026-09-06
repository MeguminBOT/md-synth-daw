#include "discord.h"

#include <cstdio>
#include <cstring>

#define MDD_DISCORD_ROOM 16384
#define MDD_DISCORD_SOCKETS 10

static char mddDiscordUser[128];
static char mddDiscordFault[192];

static unsigned char mddDiscordHead[8];
static int mddDiscordHeadHeld = 0;

static char mddDiscordBody[MDD_DISCORD_ROOM];
static int mddDiscordBodyOpcode = 0;
static int mddDiscordBodyWant = 0;
static int mddDiscordBodyHeld = 0;

static char mddDiscordOut[MDD_DISCORD_ROOM];

static bool mddDiscordAnswered = false;
static int mddDiscordSocket = -1;
static int mddDiscordSent = 0;
static int mddDiscordTook = 0;

#ifdef _WIN32

#include <windows.h>

static HANDLE mddDiscordPipe = INVALID_HANDLE_VALUE;

static bool mdd_discord_holding() {
	return mddDiscordPipe != INVALID_HANDLE_VALUE;
}

static void mdd_discord_dropped() {
	if (mddDiscordPipe == INVALID_HANDLE_VALUE) return;

	CloseHandle(mddDiscordPipe);
	mddDiscordPipe = INVALID_HANDLE_VALUE;
}

static bool mdd_discord_dialled(int index) {
	char path[64];
	_snprintf_s(path, sizeof(path), _TRUNCATE, "\\\\.\\pipe\\discord-ipc-%d", index);

	const HANDLE held = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
		OPEN_EXISTING, 0, nullptr);

	if (held == INVALID_HANDLE_VALUE) return false;

	DWORD mode = PIPE_READMODE_BYTE;
	SetNamedPipeHandleState(held, &mode, nullptr, nullptr);

	mddDiscordPipe = held;
	return true;
}

static int mdd_discord_reads(void *into, int want) {
	DWORD ready = 0;
	if (!PeekNamedPipe(mddDiscordPipe, nullptr, 0, nullptr, &ready, nullptr)) return -1;
	if (ready == 0) return 0;

	DWORD take = (DWORD)want;
	if (take > ready) take = ready;

	DWORD got = 0;
	if (!ReadFile(mddDiscordPipe, into, take, &got, nullptr)) return -1;

	return (int)got;
}

static bool mdd_discord_writes(const void *from, int want) {
	DWORD put = 0;
	if (!WriteFile(mddDiscordPipe, from, (DWORD)want, &put, nullptr)) return false;

	return put == (DWORD)want;
}

#else

#include <cstdlib>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

static int mddDiscordFile = -1;

static bool mdd_discord_holding() {
	return mddDiscordFile >= 0;
}

static void mdd_discord_dropped() {
	if (mddDiscordFile < 0) return;

	close(mddDiscordFile);
	mddDiscordFile = -1;
}

static const char *mdd_discord_beside() {
	static const char *named[4] = {"XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"};

	for (int index = 0; index < 4; index++) {
		const char *held = getenv(named[index]);
		if (held != nullptr && held[0] != 0) return held;
	}

	return "/tmp";
}

static bool mdd_discord_dialled(int index) {
	static const char *within[4] = {"", "app/com.discordapp.Discord/", "snap.discord/",
		".flatpak/dev.vencord.Vesktop/xdg-run/"};

	const char *base = mdd_discord_beside();

	for (int at = 0; at < 4; at++) {
		char path[256];
		snprintf(path, sizeof(path), "%s/%sdiscord-ipc-%d", base, within[at], index);

		struct sockaddr_un where;
		memset(&where, 0, sizeof(where));
		where.sun_family = AF_UNIX;

		if (strlen(path) >= sizeof(where.sun_path)) continue;
		strncpy(where.sun_path, path, sizeof(where.sun_path) - 1);

		const int held = socket(AF_UNIX, SOCK_STREAM, 0);
		if (held < 0) return false;

		if (connect(held, (struct sockaddr *)&where, sizeof(where)) != 0) {
			close(held);
			continue;
		}

#ifdef SO_NOSIGPIPE
		int on = 1;
		setsockopt(held, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
#endif

		fcntl(held, F_SETFL, O_NONBLOCK);
		mddDiscordFile = held;

		return true;
	}

	return false;
}

static int mdd_discord_reads(void *into, int want) {
	const ssize_t got = recv(mddDiscordFile, into, (size_t)want, 0);

	if (got > 0) return (int)got;
	if (got == 0) return -1;

	return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) ? 0 : -1;
}

static bool mdd_discord_writes(const void *from, int want) {
	const char *at = (const char *)from;
	int left = want;

	for (int guard = 0; guard < 4096 && left > 0; guard++) {
		const ssize_t put = send(mddDiscordFile, at, (size_t)left, MSG_NOSIGNAL);

		if (put > 0) {
			at += put;
			left -= (int)put;

			continue;
		}

		if (put < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) continue;

		return false;
	}

	return left == 0;
}

#endif

static void mdd_discord_lift(const char *from, const char *key, char *into, int room) {
	const char *at = strstr(from, key);
	if (at == nullptr) return;

	at += strlen(key);
	while (*at == ' ') at++;

	if (*at != '"') return;
	at++;

	int held = 0;

	while (*at != 0 && *at != '"' && held < room - 1) {
		if (*at == '\\' && at[1] != 0) at++;
		into[held++] = *at++;
	}

	into[held] = 0;
}

extern "C" bool mdd_discord_write(int opcode, const char *json) {
	if (!mdd_discord_holding()) return false;

	const int length = json == nullptr ? 0 : (int)strlen(json);
	if (length > MDD_DISCORD_ROOM - 8) return false;

	mddDiscordOut[0] = (char)(opcode & 0xFF);
	mddDiscordOut[1] = (char)((opcode >> 8) & 0xFF);
	mddDiscordOut[2] = (char)((opcode >> 16) & 0xFF);
	mddDiscordOut[3] = (char)((opcode >> 24) & 0xFF);

	mddDiscordOut[4] = (char)(length & 0xFF);
	mddDiscordOut[5] = (char)((length >> 8) & 0xFF);
	mddDiscordOut[6] = (char)((length >> 16) & 0xFF);
	mddDiscordOut[7] = (char)((length >> 24) & 0xFF);

	if (length > 0) memcpy(mddDiscordOut + 8, json, (size_t)length);

	if (!mdd_discord_writes(mddDiscordOut, length + 8)) {
		mdd_discord_dropped();
		mddDiscordAnswered = false;

		return false;
	}

	mddDiscordSent++;
	return true;
}

extern "C" void mdd_discord_shut() {
	if (mdd_discord_holding()) mdd_discord_write(MDD_DISCORD_CLOSE, "{}");

	mdd_discord_dropped();

	mddDiscordAnswered = false;
	mddDiscordSocket = -1;

	mddDiscordHeadHeld = 0;
	mddDiscordBodyOpcode = 0;
	mddDiscordBodyWant = 0;
	mddDiscordBodyHeld = 0;

	mddDiscordUser[0] = 0;
}

static void mdd_discord_framed(int opcode, const char *body) {
	mddDiscordTook++;

	if (opcode == MDD_DISCORD_PING) {
		mdd_discord_write(MDD_DISCORD_PONG, body);
		return;
	}

	if (opcode == MDD_DISCORD_CLOSE) {
		mdd_discord_lift(body, "\"message\":", mddDiscordFault, (int)sizeof(mddDiscordFault));

		mdd_discord_dropped();
		mddDiscordAnswered = false;

		return;
	}

	if (opcode != MDD_DISCORD_FRAME) return;

	if (strstr(body, "\"evt\":\"READY\"") != nullptr) {
		mddDiscordAnswered = true;
		mddDiscordUser[0] = 0;

		mdd_discord_lift(body, "\"global_name\":", mddDiscordUser, (int)sizeof(mddDiscordUser));

		if (mddDiscordUser[0] == 0) {
			mdd_discord_lift(body, "\"username\":", mddDiscordUser, (int)sizeof(mddDiscordUser));
		}

		return;
	}

	if (strstr(body, "\"evt\":\"ERROR\"") != nullptr) {
		mdd_discord_lift(body, "\"message\":", mddDiscordFault, (int)sizeof(mddDiscordFault));
	}
}

extern "C" int mdd_discord_poll() {
	int frames = 0;

	for (int guard = 0; guard < 64 && mdd_discord_holding(); guard++) {
		if (mddDiscordHeadHeld < 8) {
			const int got = mdd_discord_reads(mddDiscordHead + mddDiscordHeadHeld,
				8 - mddDiscordHeadHeld);

			if (got < 0) {
				mdd_discord_dropped();
				mddDiscordAnswered = false;

				return frames;
			}

			if (got == 0) break;

			mddDiscordHeadHeld += got;
			if (mddDiscordHeadHeld < 8) break;

			mddDiscordBodyOpcode = (int)mddDiscordHead[0] | ((int)mddDiscordHead[1] << 8)
				| ((int)mddDiscordHead[2] << 16) | ((int)mddDiscordHead[3] << 24);

			mddDiscordBodyWant = (int)mddDiscordHead[4] | ((int)mddDiscordHead[5] << 8)
				| ((int)mddDiscordHead[6] << 16) | ((int)mddDiscordHead[7] << 24);

			mddDiscordBodyHeld = 0;

			if (mddDiscordBodyWant < 0) {
				mdd_discord_dropped();
				mddDiscordAnswered = false;

				return frames;
			}
		}

		if (mddDiscordBodyHeld < mddDiscordBodyWant) {
			char scratch[1024];

			const int room = MDD_DISCORD_ROOM - 1 - mddDiscordBodyHeld;
			int want = mddDiscordBodyWant - mddDiscordBodyHeld;
			char *into;

			if (room > 0) {
				into = mddDiscordBody + mddDiscordBodyHeld;
				if (want > room) want = room;
			} else {
				into = scratch;
				if (want > (int)sizeof(scratch)) want = (int)sizeof(scratch);
			}

			const int got = mdd_discord_reads(into, want);

			if (got < 0) {
				mdd_discord_dropped();
				mddDiscordAnswered = false;

				return frames;
			}

			if (got == 0) break;

			mddDiscordBodyHeld += got;
		}

		if (mddDiscordBodyHeld < mddDiscordBodyWant) break;

		const int kept = mddDiscordBodyHeld < MDD_DISCORD_ROOM - 1
			? mddDiscordBodyHeld : MDD_DISCORD_ROOM - 1;

		mddDiscordBody[kept] = 0;

		const int opcode = mddDiscordBodyOpcode;

		mddDiscordHeadHeld = 0;
		mddDiscordBodyWant = 0;
		mddDiscordBodyHeld = 0;

		frames++;
		mdd_discord_framed(opcode, mddDiscordBody);
	}

	return frames;
}

extern "C" bool mdd_discord_open(const char *application) {
	mdd_discord_shut();

	if (application == nullptr || application[0] == 0) {
		snprintf(mddDiscordFault, sizeof(mddDiscordFault), "no application id");
		return false;
	}

	for (int index = 0; index < MDD_DISCORD_SOCKETS; index++) {
		if (!mdd_discord_dialled(index)) continue;

		char said[192];
		snprintf(said, sizeof(said), "{\"v\":1,\"client_id\":\"%.64s\"}", application);

		if (mdd_discord_write(MDD_DISCORD_HANDSHAKE, said)) {
			mddDiscordSocket = index;
			mddDiscordFault[0] = 0;

			return true;
		}

		mdd_discord_dropped();
	}

	snprintf(mddDiscordFault, sizeof(mddDiscordFault), "discord is not listening");
	return false;
}

extern "C" bool mdd_discord_live() {
	return mdd_discord_holding();
}

extern "C" bool mdd_discord_ready() {
	return mddDiscordAnswered && mdd_discord_holding();
}

extern "C" const char *mdd_discord_user() {
	return mddDiscordUser;
}

extern "C" const char *mdd_discord_fault() {
	return mddDiscordFault;
}

extern "C" int mdd_discord_pid() {
#ifdef _WIN32
	return (int)GetCurrentProcessId();
#else
	return (int)getpid();
#endif
}

extern "C" int mdd_discord_socket() {
	return mddDiscordSocket;
}

extern "C" int mdd_discord_sent() {
	return mddDiscordSent;
}

extern "C" int mdd_discord_took() {
	return mddDiscordTook;
}
