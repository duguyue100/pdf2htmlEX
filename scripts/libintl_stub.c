/*
 * Minimal libintl replacement for fully-static builds without NLS.
 * Satisfies the libintl_* symbol prefix used by glib's proxy-libintl
 * and expected by fontforge when HAVE_LIBINTL_H is defined.
 * All translation functions are identity stubs (English only).
 */
#include <locale.h>

char *libintl_gettext(const char *msgid) { return (char *)msgid; }
char *libintl_dgettext(const char *domain, const char *msgid) { return (char *)msgid; }
char *libintl_dcgettext(const char *domain, const char *msgid, int category) { return (char *)msgid; }
char *libintl_ngettext(const char *msgid1, const char *msgid2, unsigned long n)
    { return (char *)(n == 1 ? msgid1 : msgid2); }
char *libintl_dngettext(const char *domain, const char *msgid1, const char *msgid2, unsigned long n)
    { return (char *)(n == 1 ? msgid1 : msgid2); }
char *libintl_bindtextdomain(const char *domain, const char *dirname) { (void)domain; (void)dirname; return 0; }
char *libintl_bind_textdomain_codeset(const char *domain, const char *codeset) { (void)domain; (void)codeset; return 0; }
char *libintl_textdomain(const char *domainname) { (void)domainname; return 0; }
char *libintl_setlocale(int category, const char *locale) { return setlocale(category, locale); }
