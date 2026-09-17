/**
 * One instance at a time: a named lock the second copy finds already taken, and a channel the
 * second copy hands what it was opened with over.
 *
 * On Windows the lock is a named mutex and the channel a named pipe. Elsewhere the lock is a lock
 * file under the run directory, held open for the life of the process so the kernel releases it on
 * a crash, and the channel a socket beside it.
 */
#include "instance.h"

#include <stdio.h>
#include <string.h>

#define MDD_INSTANCE_ROOM 65536
#define MDD_INSTANCE_PATIENCE 250
#define MDD_INSTANCE_PAUSE 25

static char mdd_instance_text[MDD_INSTANCE_ROOM];

const char *mdd_instance_taken(void) {
	return mdd_instance_text;
}

#if defined(_WIN32)

#include <windows.h>
#include <shellapi.h>

static HANDLE mdd_instance_local = NULL;
static HANDLE mdd_instance_global = NULL;
static int mdd_instance_first = 0;

static HANDLE mdd_instance_pipe = INVALID_HANDLE_VALUE;
static HANDLE mdd_instance_signal = NULL;
static HANDLE mdd_instance_reading = NULL;
static OVERLAPPED mdd_instance_waiting;
static int mdd_instance_connected = 0;

static char mdd_instance_word[32768 * 3];

int mdd_instance_claim(const char *name) {
	char held[256];

	if (mdd_instance_local != NULL) return mdd_instance_first;
	if (name == NULL || name[0] == 0) return 1;

	mdd_instance_local = CreateMutexA(NULL, FALSE, name);
	mdd_instance_first = GetLastError() == ERROR_ALREADY_EXISTS ? 0 : 1;

	snprintf(held, sizeof(held), "Global\\%s", name);
	mdd_instance_global = CreateMutexA(NULL, FALSE, held);

	if (mdd_instance_global != NULL && GetLastError() == ERROR_ALREADY_EXISTS)
		mdd_instance_first = 0;

	return mdd_instance_first;
}

int mdd_instance_held(void) {
	return mdd_instance_local != NULL ? mdd_instance_first : 0;
}

/**
 * Closes the pipe and both events, where they are open.
 */
static void mdd_instance_deaf(void) {
	if (mdd_instance_pipe != INVALID_HANDLE_VALUE) {
		CancelIo(mdd_instance_pipe);
		CloseHandle(mdd_instance_pipe);
		mdd_instance_pipe = INVALID_HANDLE_VALUE;
	}

	if (mdd_instance_signal != NULL) {
		CloseHandle(mdd_instance_signal);
		mdd_instance_signal = NULL;
	}

	if (mdd_instance_reading != NULL) {
		CloseHandle(mdd_instance_reading);
		mdd_instance_reading = NULL;
	}

	mdd_instance_connected = 0;
}

void mdd_instance_release(void) {
	mdd_instance_deaf();

	if (mdd_instance_global != NULL) {
		CloseHandle(mdd_instance_global);
		mdd_instance_global = NULL;
	}

	if (mdd_instance_local != NULL) {
		CloseHandle(mdd_instance_local);
		mdd_instance_local = NULL;
	}

	mdd_instance_first = 0;
}

/**
 * @param name The name the lock was claimed under.
 * @param into Where the pipe's path goes.
 * @param room How many bytes that holds.
 */
static void mdd_instance_named(const char *name, char *into, size_t room) {
	snprintf(into, room, "\\\\.\\pipe\\%s", name);
}

/**
 * Waits for the next copy to connect, without blocking.
 *
 * @return Nonzero where the pipe is waiting or already connected.
 */
static int mdd_instance_accept(void) {
	memset(&mdd_instance_waiting, 0, sizeof(mdd_instance_waiting));
	ResetEvent(mdd_instance_signal);

	mdd_instance_waiting.hEvent = mdd_instance_signal;
	mdd_instance_connected = 0;

	if (ConnectNamedPipe(mdd_instance_pipe, &mdd_instance_waiting)) {
		mdd_instance_connected = 1;
		return 1;
	}

	switch (GetLastError()) {
		case ERROR_IO_PENDING:
			return 1;

		case ERROR_PIPE_CONNECTED:
			mdd_instance_connected = 1;
			return 1;

		default:
			return 0;
	}
}

int mdd_instance_listen(const char *name) {
	char path[320];

	if (mdd_instance_pipe != INVALID_HANDLE_VALUE) return 1;
	if (name == NULL || name[0] == 0 || !mdd_instance_held()) return 0;

	mdd_instance_named(name, path, sizeof(path));

	mdd_instance_signal = CreateEventA(NULL, TRUE, FALSE, NULL);
	mdd_instance_reading = CreateEventA(NULL, TRUE, FALSE, NULL);

	if (mdd_instance_signal == NULL || mdd_instance_reading == NULL) {
		mdd_instance_deaf();
		return 0;
	}

	mdd_instance_pipe = CreateNamedPipeA(path,
		PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
		PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1, 0,
		MDD_INSTANCE_ROOM, 0, NULL);

	if (mdd_instance_pipe == INVALID_HANDLE_VALUE || !mdd_instance_accept()) {
		mdd_instance_deaf();
		return 0;
	}

	return 1;
}

int mdd_instance_take(void) {
	int held = 0;

	if (mdd_instance_pipe == INVALID_HANDLE_VALUE) return -1;

	if (!mdd_instance_connected) {
		DWORD ignored = 0;

		if (WaitForSingleObject(mdd_instance_signal, 0) != WAIT_OBJECT_0) return -1;

		if (!GetOverlappedResult(mdd_instance_pipe, &mdd_instance_waiting, &ignored, FALSE)) {
			DisconnectNamedPipe(mdd_instance_pipe);
			if (!mdd_instance_accept()) mdd_instance_deaf();
			return -1;
		}

		mdd_instance_connected = 1;
	}

	while (held < MDD_INSTANCE_ROOM - 1) {
		OVERLAPPED part;
		DWORD got = 0;

		memset(&part, 0, sizeof(part));
		ResetEvent(mdd_instance_reading);
		part.hEvent = mdd_instance_reading;

		if (!ReadFile(mdd_instance_pipe, mdd_instance_text + held,
				(DWORD)(MDD_INSTANCE_ROOM - 1 - held), &got, &part)) {
			if (GetLastError() != ERROR_IO_PENDING) break;

			if (WaitForSingleObject(mdd_instance_reading, MDD_INSTANCE_PATIENCE) != WAIT_OBJECT_0) {
				CancelIo(mdd_instance_pipe);
				GetOverlappedResult(mdd_instance_pipe, &part, &got, TRUE);
				break;
			}

			if (!GetOverlappedResult(mdd_instance_pipe, &part, &got, FALSE)) break;
		}

		if (got == 0) break;
		held += (int)got;
	}

	mdd_instance_text[held] = 0;

	DisconnectNamedPipe(mdd_instance_pipe);
	if (!mdd_instance_accept()) mdd_instance_deaf();

	return held;
}

int mdd_instance_hand(const char *name, const char *text, int wait) {
	char path[320];
	const size_t length = text == NULL ? 0 : strlen(text);
	const DWORD began = GetTickCount();

	if (name == NULL || name[0] == 0 || length >= MDD_INSTANCE_ROOM) return 0;

	mdd_instance_named(name, path, sizeof(path));

	for (;;) {
		HANDLE pipe = CreateFileA(path, GENERIC_WRITE, 0, NULL, OPEN_EXISTING, 0, NULL);

		if (pipe != INVALID_HANDLE_VALUE) {
			ULONG server = 0;
			DWORD wrote = 0;
			BOOL written = TRUE;

			if (GetNamedPipeServerProcessId(pipe, &server)) AllowSetForegroundWindow(server);
			if (length > 0) written = WriteFile(pipe, text, (DWORD)length, &wrote, NULL);

			CloseHandle(pipe);
			return written && (size_t)wrote == length ? 1 : 0;
		}

		const DWORD fault = GetLastError();

		if (fault != ERROR_PIPE_BUSY && fault != ERROR_FILE_NOT_FOUND) return 0;
		if ((int)(GetTickCount() - began) >= wait) return 0;

		if (fault == ERROR_PIPE_BUSY) WaitNamedPipeA(path, MDD_INSTANCE_PAUSE);
		else Sleep(MDD_INSTANCE_PAUSE);
	}
}

int mdd_instance_arguments(void) {
	int count = 0;
	LPWSTR *wide = CommandLineToArgvW(GetCommandLineW(), &count);

	if (wide == NULL) return -1;

	LocalFree(wide);
	return count;
}

const char *mdd_instance_argument(int index) {
	int count = 0;
	LPWSTR *wide = CommandLineToArgvW(GetCommandLineW(), &count);

	mdd_instance_word[0] = 0;
	if (wide == NULL) return mdd_instance_word;

	if (index >= 0 && index < count
			&& WideCharToMultiByte(CP_UTF8, 0, wide[index], -1, mdd_instance_word,
				(int)sizeof(mdd_instance_word), NULL, NULL) == 0) {
		mdd_instance_word[0] = 0;
	}

	LocalFree(wide);
	return mdd_instance_word;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

static int mdd_instance_lock = -1;
static int mdd_instance_first = 0;
static char mdd_instance_path[512];

static int mdd_instance_listener = -1;
static char mdd_instance_socket[sizeof(((struct sockaddr_un *)0)->sun_path)];

/**
 * @param name The name the lock was claimed under.
 * @param suffix What follows the name in the file's own name.
 * @param into Where the path goes.
 * @param room How many bytes that holds.
 * @return Nonzero where the whole path fitted.
 */
static int mdd_instance_where(const char *name, const char *suffix, char *into, size_t room) {
	const char *base = getenv("XDG_RUNTIME_DIR");

	if (base == NULL || base[0] == 0) base = "/tmp";
	return snprintf(into, room, "%s/%s%s", base, name, suffix) < (int)room ? 1 : 0;
}

int mdd_instance_claim(const char *name) {
	if (mdd_instance_lock >= 0) return mdd_instance_first;
	if (name == NULL || name[0] == 0) return 1;

	mdd_instance_where(name, ".lock", mdd_instance_path, sizeof(mdd_instance_path));
	mdd_instance_lock = open(mdd_instance_path, O_CREAT | O_RDWR, 0644);

	if (mdd_instance_lock < 0) return 1;

	mdd_instance_first = flock(mdd_instance_lock, LOCK_EX | LOCK_NB) == 0 ? 1 : 0;
	return mdd_instance_first;
}

int mdd_instance_held(void) {
	return mdd_instance_lock >= 0 ? mdd_instance_first : 0;
}

void mdd_instance_release(void) {
	if (mdd_instance_listener >= 0) {
		close(mdd_instance_listener);
		unlink(mdd_instance_socket);
		mdd_instance_listener = -1;
	}

	if (mdd_instance_lock < 0) return;

	if (mdd_instance_first) {
		flock(mdd_instance_lock, LOCK_UN);
		unlink(mdd_instance_path);
	}

	close(mdd_instance_lock);
	mdd_instance_lock = -1;
	mdd_instance_first = 0;
}

/**
 * @param name The name the lock was claimed under.
 * @param into The socket address to fill in.
 * @return Nonzero where the socket's path fitted in the address.
 */
static int mdd_instance_address(const char *name, struct sockaddr_un *into) {
	memset(into, 0, sizeof(*into));
	into->sun_family = AF_UNIX;

	return mdd_instance_where(name, ".sock", into->sun_path, sizeof(into->sun_path));
}

int mdd_instance_listen(const char *name) {
	struct sockaddr_un address;

	if (mdd_instance_listener >= 0) return 1;
	if (name == NULL || name[0] == 0 || !mdd_instance_held()) return 0;
	if (!mdd_instance_address(name, &address)) return 0;

	unlink(address.sun_path);

	mdd_instance_listener = socket(AF_UNIX, SOCK_STREAM, 0);
	if (mdd_instance_listener < 0) return 0;

	if (bind(mdd_instance_listener, (struct sockaddr *)&address, sizeof(address)) != 0
			|| listen(mdd_instance_listener, 4) != 0) {
		close(mdd_instance_listener);
		mdd_instance_listener = -1;
		return 0;
	}

	chmod(address.sun_path, 0600);
	fcntl(mdd_instance_listener, F_SETFL, fcntl(mdd_instance_listener, F_GETFL, 0) | O_NONBLOCK);

	memcpy(mdd_instance_socket, address.sun_path, sizeof(mdd_instance_socket));
	return 1;
}

int mdd_instance_take(void) {
	struct timeval patience;
	int held = 0;

	if (mdd_instance_listener < 0) return -1;

	const int client = accept(mdd_instance_listener, NULL, NULL);
	if (client < 0) return -1;

	fcntl(client, F_SETFL, fcntl(client, F_GETFL, 0) & ~O_NONBLOCK);

	patience.tv_sec = 0;
	patience.tv_usec = MDD_INSTANCE_PATIENCE * 1000;
	setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &patience, sizeof(patience));

	while (held < MDD_INSTANCE_ROOM - 1) {
		const ssize_t got = recv(client, mdd_instance_text + held,
			(size_t)(MDD_INSTANCE_ROOM - 1 - held), 0);

		if (got < 0 && errno == EINTR) continue;
		if (got <= 0) break;

		held += (int)got;
	}

	mdd_instance_text[held] = 0;
	close(client);

	return held;
}

int mdd_instance_hand(const char *name, const char *text, int wait) {
	struct sockaddr_un address;
	struct timespec pause;
	const size_t length = text == NULL ? 0 : strlen(text);
	int spent = 0;

	if (name == NULL || name[0] == 0 || length >= MDD_INSTANCE_ROOM) return 0;
	if (!mdd_instance_address(name, &address)) return 0;

	pause.tv_sec = 0;
	pause.tv_nsec = MDD_INSTANCE_PAUSE * 1000000L;

	for (;;) {
		const int held = socket(AF_UNIX, SOCK_STREAM, 0);
		if (held < 0) return 0;

#ifdef SO_NOSIGPIPE
		const int quiet = 1;
		setsockopt(held, SOL_SOCKET, SO_NOSIGPIPE, &quiet, sizeof(quiet));
#endif

		if (connect(held, (struct sockaddr *)&address, sizeof(address)) == 0) {
			size_t sent = 0;

			while (sent < length) {
#ifdef MSG_NOSIGNAL
				const ssize_t went = send(held, text + sent, length - sent, MSG_NOSIGNAL);
#else
				const ssize_t went = send(held, text + sent, length - sent, 0);
#endif

				if (went < 0 && errno == EINTR) continue;
				if (went <= 0) break;

				sent += (size_t)went;
			}

			close(held);
			return sent == length ? 1 : 0;
		}

		const int fault = errno;
		close(held);

		if (fault != ENOENT && fault != ECONNREFUSED && fault != EAGAIN) return 0;
		if (spent >= wait) return 0;

		nanosleep(&pause, NULL);
		spent += MDD_INSTANCE_PAUSE;
	}
}

int mdd_instance_arguments(void) {
	return -1;
}

const char *mdd_instance_argument(int index) {
	(void)index;
	return "";
}

#endif
