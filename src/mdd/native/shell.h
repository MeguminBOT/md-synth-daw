#ifndef MDD_SHELL_H
#define MDD_SHELL_H

#ifdef __cplusplus
extern "C" {
#endif

int mdd_shell_supported(void);
int mdd_shell_associated(const char *suffix, const char *identity);
int mdd_shell_associate(const char *suffix, const char *identity, const char *label,
	const char *mime, const char *name, const char *about);
int mdd_shell_forget(const char *suffix, const char *identity);
int mdd_shell_leftovers(const char *suffix, const char *identity);

#ifdef __cplusplus
}
#endif

#endif
