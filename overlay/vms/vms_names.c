/* vms_names.c - VMS-syntax starting points and names (DECISIONS D2).

   find names each file after its starting point: "find tree" prints
   tree/sub/two.txt.  A starting point in VMS syntax ("[.tree]") could
   not be walked at all (the C RTL stats it, but find's openat path does
   not open it), and "[.tree]/sub" would be no use to anyone.  So on VMS a
   VMS-syntax starting point is converted to a Unix name for the walk, as
   vms-tar does with its operands:

     [.tree]          -> tree
     []               -> .
     [-.a]b.c         -> ../a/b.c
     tree.dir         -> tree         (only when it is a directory)
     DKA0:[x]y        -> /DKA0/x/y

   and the names under it are shown in VMS syntax, by -print, -fprint,
   -print0, -ls, -printf %p and -exec's {}: the starting point as typed,
   then [.tree.sub]two.txt, a directory as [.tree]sub.DIR (the file a DCL
   command acts on), with ODS-5 escapes (^. ^_ ...) where a name needs
   them.  A Unix starting point keeps Unix names.

   The VMS -> Unix direction is the C RTL's decc$translate_vms, as in
   vms-tar; the other is done here, because decc$to_vms upper-cases names
   and rejects ODS-5 ones (a.b.c, names with spaces; probed 2026-10-09).

   Part of the OpenVMS port of GNU findutils
   (github.com/issinoho/vms-findutils); distributed under the GNU General
   Public License, version 3 or later.  */

#include <config.h>
#include "vms_names.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/types.h>
#include <sys/stat.h>

/* decc$translate_vms, declared here: <unixlib.h> clashes with gnulib's
   mkdir replacement.  Upper case, as the C RTL exports it (/NAMES=AS_IS).  */
extern char *DECC$TRANSLATE_VMS (char const *vms_filespec);

static bool vms_mode;
static char *start_unix;
static char const *start_typed;

static bool
ends_in_dir (char const *name, size_t len)
{
  return len > 4 && strcasecmp (name + len - 4, ".dir") == 0;
}

/* NAME in Unix syntax: NAME itself when it needs no change, otherwise a
   new string from malloc.  (vms-tar's vms_unix_name.)  */
static char *
unix_name (char *name)
{
  char *u, *r;
  size_t len;
  struct stat st;

  if (strchr (name, '/'))
    return name;
  len = strlen (name);
  if (!strpbrk (name, "[<:;") && !ends_in_dir (name, len))
    return name;

  r = DECC$TRANSLATE_VMS (name);
  if (r == NULL || r == (char *) -1)
    return name;
  while (r[0] == '.' && r[1] == '/')
    r += 2;
  u = strdup (*r ? r : ".");
  if (u == NULL)
    return name;

  /* "tree.dir" names the directory "tree".  */
  len = strlen (u);
  if (ends_in_dir (u, len) && stat (u, &st) == 0 && S_ISDIR (st.st_mode))
    u[len - 4] = '\0';
  /* "[.tree]" gives "tree/"; find would print "tree//sub".  */
  while (len > 1 && u[len - 1] == '/')
    u[--len] = '\0';
  return u;
}

char *
vms_start_point (char *arg)
{
  char *u = unix_name (arg);
  if (start_unix && start_unix != start_typed)
    free (start_unix);
  vms_mode = u != arg;
  start_unix = u;
  start_typed = arg;
  return u;
}

bool
vms_display_vms (void)
{
  return vms_mode;
}

/* The output buffer.  */
static char *buf;
static size_t buf_size, buf_len;

static void
put (char c)
{
  if (buf_len + 2 > buf_size)
    {
      size_t n = buf_size ? 2 * buf_size : 256;
      char *b = realloc (buf, n);
      if (b == NULL)
        return;
      buf = b;
      buf_size = n;
    }
  buf[buf_len++] = c;
  buf[buf_len] = '\0';
}

static void
puts_raw (char const *s)
{
  while (*s)
    put (*s++);
}

/* Component S (N bytes) with ODS-5 escapes.  Every dot is escaped, except
   the one at KEEP_DOT (a file type's), if any.  */
static void
put_escaped (char const *s, size_t n, char const *keep_dot)
{
  size_t i;
  for (i = 0; i < n; i++)
    {
      char c = s[i];
      if (c == ' ')
        puts_raw ("^_");
      else if (c == '.' && s + i == keep_dot)
        put ('.');
      else
        {
          if (strchr (".,;[]<>!&'()+@{}#%`~=^", c))
            put ('^');
          put (c);
        }
    }
}

char const *
vms_display_name (char const *path, bool is_dir)
{
  char const *comp[256];
  size_t len[256];
  size_t n = 0, i, first = 0, ups = 0;
  bool absolute = path[0] == '/';
  char const *p = path;

  if (!vms_mode)
    return path;
  if (strcmp (path, start_unix) == 0)
    return start_typed;

  /* Split into components, dropping empty ones and ".".  */
  while (*p)
    {
      char const *e = strchr (p, '/');
      size_t l = e ? (size_t) (e - p) : strlen (p);
      if (l > 0 && !(l == 1 && p[0] == '.'))
        {
          if (n == sizeof comp / sizeof *comp)
            return path;
          comp[n] = p;
          len[n++] = l;
        }
      p += l + (e != NULL);
    }
  if (n == 0)
    return path;

  buf_len = 0;
  if (absolute)
    {
      /* /DEV/a/b/name -> DEV:[a.b]name */
      if (n < 2)
        return path;
      put_escaped (comp[0], len[0], NULL);
      put (':');
      put ('[');
      if (n == 2)
        puts_raw ("000000");
      for (i = 1; i + 1 < n; i++)
        {
          if (i > 1)
            put ('.');
          put_escaped (comp[i], len[i], NULL);
        }
      put (']');
    }
  else
    {
      /* a/b/name -> [.a.b]name, ../a/name -> [-.a]name, name -> []name */
      while (first + 1 < n && len[first] == 2 && strncmp (comp[first], "..", 2) == 0)
        first++, ups++;
      put ('[');
      for (i = 0; i < ups; i++)
        puts_raw (i ? ".-" : "-");
      for (i = first; i + 1 < n; i++)
        {
          put ('.');
          put_escaped (comp[i], len[i], NULL);
        }
      put (']');
    }

  /* The name: a file keeps its type's dot; a directory is NAME.DIR.  */
  {
    char const *name = comp[n - 1];
    size_t l = len[n - 1];
    char const *dot = NULL;
    if (!is_dir)
      for (i = l; i-- > 0; )
        if (name[i] == '.')
          {
            dot = name + i;
            break;
          }
    put_escaped (name, l, dot);
    if (is_dir)
      puts_raw (".DIR");
  }
  return buf ? buf : path;
}
