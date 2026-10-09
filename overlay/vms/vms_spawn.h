/* vms_spawn.h - run a DCL command in a subprocess on OpenVMS.  */
#ifndef VMS_SPAWN_H
#define VMS_SPAWN_H

#include <stdbool.h>

/* vms_spawn_command's results besides an exit code (0-255).  */
#define VMS_SPAWN_FAILED   (-1)  /* the subprocess could not be created */
#define VMS_SPAWN_TOO_LONG (-2)  /* the command line exceeds DCL's limit */

/* Exit code for a command DCL does not know (%DCL-W-IVVERB), as a POSIX
   shell's 127 for "command not found".  */
#define VMS_SPAWN_NOT_FOUND 127

/* Run ARGV (ending with a null pointer) as a DCL command: ARGV[0] is the
   verb, foreign-command symbol or image name, unquoted; every other
   argument is quoted, so DCL keeps its case and spaces.  The command's
   output (SYS$OUTPUT and SYS$ERROR) is copied to stdout when it ends.  With
   NULL_STDIN its SYS$INPUT is NLA0:, otherwise ours.  Return its exit code:
   0 for success, N for a C program that called exit (N), otherwise 1 for a
   warning, 2 for an error and 4 for a fatal status, or VMS_SPAWN_NOT_FOUND;
   or VMS_SPAWN_FAILED or VMS_SPAWN_TOO_LONG.  PREFIX names the temporary
   files in SYS$SCRATCH.  */
int vms_spawn_command (char const *prefix, char *const *argv, bool null_stdin);

#endif
