#ifndef MDD_DISCORD_H
#define MDD_DISCORD_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Opcode: the frame that opens the connection.
 */
#define MDD_DISCORD_HANDSHAKE 0

/**
 * Opcode: an ordinary frame carrying JSON.
 */
#define MDD_DISCORD_FRAME 1

/**
 * Opcode: the client is closing the connection.
 */
#define MDD_DISCORD_CLOSE 2

/**
 * Opcode: a keepalive from the client.
 */
#define MDD_DISCORD_PING 3

/**
 * Opcode: the answer to one.
 */
#define MDD_DISCORD_PONG 4

/**
 * Connects to a running Discord client and sends the handshake. The transport is a
 * local socket, an eight byte header and a JSON payload, which is the whole of the
 * protocol both official libraries wrap.
 *
 * @param application The application identifier to announce as.
 * @return False where no client answered on any of the sockets it tries.
 */
bool mdd_discord_open(const char *application);

/**
 * Closes the connection.
 */
void mdd_discord_shut();

/**
 * @return Whether the socket is open.
 */
bool mdd_discord_live();

/**
 * @return Whether the client has answered the handshake, so presence can be sent.
 */
bool mdd_discord_ready();

/**
 * Reads whatever the client has sent, answering pings as they arrive. Call once a
 * frame; it never blocks.
 *
 * @return How many frames were read.
 */
int mdd_discord_poll();

/**
 * Sends one frame.
 *
 * @param opcode One of the MDD_DISCORD_ values.
 * @param json The payload.
 * @return False where the socket would not take it.
 */
bool mdd_discord_write(int opcode, const char *json);

/**
 * @return Who the client is signed in as, or an empty string before the handshake.
 */
const char *mdd_discord_user();

/**
 * @return What went wrong last, or an empty string where nothing did.
 */
const char *mdd_discord_fault();

/**
 * @return This process identifier, which a presence payload has to carry.
 */
int mdd_discord_pid();

/**
 * @return Which of the sockets the client was found on, for a report.
 */
int mdd_discord_socket();

/**
 * @return How many frames have been sent.
 */
int mdd_discord_sent();

/**
 * @return How many have been read.
 */
int mdd_discord_took();

#ifdef __cplusplus
}
#endif

#endif
