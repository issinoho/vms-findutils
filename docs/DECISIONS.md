# Design decisions

## D1. Running commands from find -exec and xargs: DCL through LIB$SPAWN

**Status:** decided by the user (2026-10-09); implemented in `vms/vms_spawn.c` and patches 0006 (find) and 0007 (xargs); not yet tested on VMS.

`find/exec.c` (`-exec`, `-execdir`, `-ok`, `-okdir`) and `xargs/xargs.c` run each command
with `fork()`, `execvp()` and `waitpid()`. VMS has no `fork()`. The command is usually
something a DCL user types: a DCL verb (`TYPE`, `DELETE`), a foreign-command symbol
(`grep`, `gzip` from the family's kits) or an image.

**Decision:** run the command as a DCL command line in a subprocess (`LIB$SPAWN`), as
vms-m4 (`syscmd`) and vms-tar (`vms_spawn.c`) do:
- the subprocess runs a small generated procedure that drops the SYS$OUTPUT and SYS$ERROR
  it inherits, so a redirected find or xargs output is not reopened (%DCL-W-UNDFIL, empty
  new versions);
- only the file names are quoted (what find substitutes for `{}`, the items xargs reads),
  so DCL keeps their case, spaces and slashes; the words the user typed are DCL syntax and
  are passed as they are, so qualifiers and keywords work (`-exec set file/attr=rfm:stm {} ;`,
  `-exec write sys$output {} ;`). A typed word with a space or an empty one is quoted too.
  The procedure sets PARSE_STYLE=EXTENDED, so foreign commands get unquoted words in their
  case. (Revised 2026-10-09: the first version quoted every argument, which turned
  qualifiers and keywords into strings.)
- the command's output goes to a temporary file in SYS$SCRATCH, copied to find's or
  xargs's stdout when the command ends (commands run one at a time, so order is kept);
- the exit status is 0 for success, the POSIX exit code when the program exited with one,
  otherwise derived from the VMS status's severity, so `-exec` tests and xargs's 123-127
  work.

**Rejected:** `vfork()`/`execv()` of an image (fast, but no verbs or symbols, and the
SYS$OUTPUT reopening problem); a hybrid of both (two code paths to test and explain).

**Cost:** one subprocess per command. `-exec ... \;` over many files is slow; `-exec ... +`
and xargs pass many names per command.

**xargs -P:** the first release runs commands one at a time; `-P N` acts as `-P 1`, and the
kit's README.VMS says so. Parallel runs (`LIB$SPAWN` with NOWAIT) can come later.

## D2. File-name syntax: follow the starting point

**Status:** decided by the user (2026-10-09); not yet implemented.

`find . ` and `find tree` print Unix names (`tree/sub/two.txt`), as on Unix, for scripts and
the family's Unix tools. `find []` and `find [.tree]` print VMS names (`[.tree.sub]two.txt`),
which DCL verbs in `-exec` (TYPE, DELETE, SET FILE) accept. A VMS-syntax starting point is
converted to a Unix name for the walk (as vms-tar D2), and the names are converted back on
output and for `{}`.

**Rejected:** always Unix (DCL verbs in `-exec` cannot use the names); always VMS (breaks
scripts and tools that expect find's usual output).
