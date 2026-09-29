#ifndef MDD_INSTALLER_H
#define MDD_INSTALLER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Reads what the Windows installer recorded about a copy, from the entry it leaves for Apps and
 * Features. The entry sits under the machine for a copy installed for every account and under the
 * user for one installed for the current account alone, and it names the folder the copy went into.
 * The entry says who a copy belongs to where the path cannot, because a copy for every account can be
 * installed into any folder.
 *
 * Windows only. Elsewhere this answers nought.
 *
 * @param identity The installer's application identity, with no braces.
 * @param where The folder the running copy sits in, with either separator.
 * @return Nonzero where the entry under the machine names that folder, which is a copy installed for
 *     every account and updated only by an administrator.
 */
int mdd_installer_everyone(const char *identity, const char *where);

#ifdef __cplusplus
}
#endif

#endif
