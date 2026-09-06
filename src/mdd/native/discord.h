#ifndef MDD_DISCORD_H
#define MDD_DISCORD_H

#ifdef __cplusplus
extern "C" {
#endif

#define MDD_DISCORD_HANDSHAKE 0
#define MDD_DISCORD_FRAME 1
#define MDD_DISCORD_CLOSE 2
#define MDD_DISCORD_PING 3
#define MDD_DISCORD_PONG 4

bool mdd_discord_open(const char *application);
void mdd_discord_shut();

bool mdd_discord_live();
bool mdd_discord_ready();

int mdd_discord_poll();
bool mdd_discord_write(int opcode, const char *json);

const char *mdd_discord_user();
const char *mdd_discord_fault();

int mdd_discord_pid();
int mdd_discord_socket();
int mdd_discord_sent();
int mdd_discord_took();

#ifdef __cplusplus
}
#endif

#endif
