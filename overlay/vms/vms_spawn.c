/* vms_spawn.c - run a DCL command in a subprocess on OpenVMS.

   OpenVMS has no fork(), so find -exec and xargs cannot run a command the
   Unix way.  They run it as DCL instead (docs/DECISIONS.md D1), so DCL
   verbs and foreign-command symbols work as well as images.  The
   subprocess (LIB$SPAWN) runs a small generated procedure.  LIB$SPAWN
   copies our process logical names, including a SYS$OUTPUT or SYS$ERROR
   that redirects our own output, and those would make the command reopen
   the user's file (%DCL-W-UNDFIL, or an empty new version); so the
   procedure drops them first, then runs the command with the file names
   quoted and the user's own words as DCL syntax.  The command's output goes to a temporary file,
   copied to our stdout when it ends: commands run one at a time, so their
   output stays in order with find's own.  (As in vms-m4 and vms-tar.)

   Part of the OpenVMS port of GNU findutils
   (github.com/issinoho/vms-findutils); distributed under the GNU General
   Public License, version 3 or later.  */

#include <config.h>
#include "vms_spawn.h"

#include <descrip.h>
#include <lib$routines.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

/* The longest DCL command line: 8192 bytes on V8.4 and later, less some
   room for the verb's own expansion.  */
#define VMS_DCL_MAX 8000

/* %DCL-W-IVVERB, "unrecognized command verb".  */
#define CLI_IVVERB 0x00038090

static void
delete_all (char const *name)
{
  char spec[256];
  struct dsc$descriptor_s d;
  snprintf (spec, sizeof spec, "%s;*", name);
  d.dsc$w_length = (unsigned short) strlen (spec);
  d.dsc$b_dtype = DSC$K_DTYPE_T;
  d.dsc$b_class = DSC$K_CLASS_S;
  d.dsc$a_pointer = spec;
  lib$delete_file (&d, 0, 0, 0, 0, 0, 0, 0, 0, 0);
}

static void
set_descriptor (struct dsc$descriptor_s *d, char const *s)
{
  d->dsc$w_length = (unsigned short) strlen (s);
  d->dsc$b_dtype = DSC$K_DTYPE_T;
  d->dsc$b_class = DSC$K_CLASS_S;
  d->dsc$a_pointer = (char *) s;
}

/* Whether argument I of ARGV is written in quotes.  */
static bool
quoted (char *const *argv, bool const *quote, size_t i)
{
  return (quote ? quote[i] : true)
         || argv[i][0] == '\0' || strpbrk (argv[i], " \t\"") != NULL;
}

/* The length of ARGV as one DCL command line, as written below.  */
static size_t
command_length (char *const *argv, bool const *quote)
{
  size_t n = strlen (argv[0]);
  size_t i;
  for (i = 1; argv[i]; i++)
    {
      char const *p;
      n += 1 + (quoted (argv, quote, i) ? 2 : 0);
      for (p = argv[i]; *p; p++)
        n += 1 + (*p == '"');
    }
  return n;
}

int
vms_spawn_command (char const *prefix, char *const *argv,
                   bool const *quote, bool null_stdin)
{
  static unsigned int counter;
  char com[96], out[96], spawncmd[112];
  struct dsc$descriptor_s cmd_d, in_d, out_d;
  unsigned int status, completion = 0;
  size_t i;
  FILE *c;
  int ch;

  if (command_length (argv, quote) > VMS_DCL_MAX)
    return VMS_SPAWN_TOO_LONG;

  ++counter;
  snprintf (com, sizeof com, "SYS$SCRATCH:%s_%08X_%u.COM",
            prefix, (unsigned int) getpid (), counter);
  snprintf (out, sizeof out, "SYS$SCRATCH:%s_%08X_%u.TMP",
            prefix, (unsigned int) getpid (), counter);
  c = fopen (com, "w");
  if (!c)
    return VMS_SPAWN_FAILED;
  fputs ("$ set noon\n"
         "$ set message/nofacility/noseverity/noidentification/notext\n"
         "$ if f$trnlnm(\"SYS$OUTPUT\",\"LNM$PROCESS\",,\"USER\") .nes. \"\""
         " then deassign/user sys$output\n"
         "$ if f$trnlnm(\"SYS$OUTPUT\",\"LNM$PROCESS\",,\"SUPERVISOR\") .nes. \"\""
         " then deassign sys$output\n"
         "$ if f$trnlnm(\"SYS$ERROR\",\"LNM$PROCESS\",,\"USER\") .nes. \"\""
         " then deassign/user sys$error\n"
         "$ if f$trnlnm(\"SYS$ERROR\",\"LNM$PROCESS\",,\"SUPERVISOR\") .nes. \"\""
         " then deassign sys$error\n"
         "$ set message/facility/severity/identification/text\n"
         "$ set process/parse_style=extended\n", c);
  fprintf (c, "$ %s", argv[0]);
  /* One argument per line: DCL limits the length of a record.  */
  for (i = 1; argv[i]; i++)
    {
      char const *p;
      bool q = quoted (argv, quote, i);
      fputs (q ? " -\n \"" : " -\n ", c);
      for (p = argv[i]; *p; p++)
        {
          if (*p == '"')
            putc ('"', c);      /* DCL doubles quotes */
          putc (*p, c);
        }
      if (q)
        putc ('"', c);
    }
  fputs ("\n$ exit $status\n", c);
  if (fclose (c) != 0)
    {
      delete_all (com);
      return VMS_SPAWN_FAILED;
    }

  snprintf (spawncmd, sizeof spawncmd, "@%s", com);
  set_descriptor (&cmd_d, spawncmd);
  set_descriptor (&in_d, "NLA0:");
  set_descriptor (&out_d, out);
  fflush (stdout);
  fflush (stderr);
  status = lib$spawn (&cmd_d, null_stdin ? &in_d : 0, &out_d, 0, 0, 0,
                      &completion, 0, 0, 0, 0, 0, 0);
  delete_all (com);
  c = fopen (out, "r");
  if (c)
    {
      /* putc, not fwrite: to a record-oriented stdout the C RTL writes
         each fwrite item as a record.  */
      while ((ch = getc (c)) != EOF)
        putc (ch, stdout);
      fclose (c);
      fflush (stdout);
    }
  delete_all (out);
  if (!(status & 1))
    return VMS_SPAWN_FAILED;
  /* A C program's exit (N) is %X35A000 + N*8 + severity.  Test it before
     the severity: the C RTL's own encoding has success severity even for
     N != 0 (the family's ports give it error severity, see vms_exit.c).  */
  if ((completion & 0x0FFFF000) == 0x0035A000 && (completion & 0x7F8) != 0)
    return (completion & 0x7F8) >> 3;
  if (completion & 1)
    return 0;
  if ((completion & 0x0FFFFFFF) == CLI_IVVERB)
    return VMS_SPAWN_NOT_FOUND;
  switch (completion & 7)
    {
    case 0: return 1;           /* warning */
    case 4: return 4;           /* fatal */
    default: return 2;          /* error */
    }
}
