#ifndef MDD_SHELL_H
#define MDD_SHELL_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @return Nonzero where this platform can register a file suffix at all.
 */
int mdd_shell_supported(void);

/**
 * @param suffix The file suffix, with no dot.
 * @param identity The name the application registers under.
 * @return Nonzero where the suffix is registered to this application.
 */
int mdd_shell_associated(const char *suffix, const char *identity);

/**
 * Registers the suffix with the desktop, so a double click opens it here.
 *
 * @param suffix The file suffix, with no dot.
 * @param identity The name the application registers under.
 * @param label What the file type is called.
 * @param mime Its media type.
 * @param name What the application is called.
 * @param about A line describing it.
 * @return Nonzero where every key was written.
 */
int mdd_shell_associate(const char *suffix, const char *identity, const char *label,
	const char *mime, const char *name, const char *about);

/**
 * Unregisters the suffix, taking back everything mdd_shell_associate wrote.
 *
 * @param suffix The file suffix, with no dot.
 * @param identity The name the application registers under.
 * @return Nonzero where it was taken back.
 */
int mdd_shell_forget(const char *suffix, const char *identity);

/**
 * @param suffix The file suffix, with no dot.
 * @param identity The name the application registers under.
 * @return How many keys are still there after unregistering, which should be nought.
 */
int mdd_shell_leftovers(const char *suffix, const char *identity);

#ifdef __cplusplus
}
#endif

#endif
