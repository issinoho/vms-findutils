# Design decisions

## D1. Running commands from find -exec and xargs: DCL through LIB$SPAWN

**Status:** decided by the user (2026-10-09); implemented in `vms/vms_spawn.c` and patches 0006 (find), 0007 (xargs) and 0008 (line length); smoke-tested on IA64.

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
- a file name that is unmistakably a VMS file specification (it has `[`, `<` or `:` and no
  space, `/`, quote, `!` or `'`) is not quoted either: DCL verbs do not strip quotes from a
  file specification (`TYPE "[.tree]one.txt"` fails with %RMS-F-FNM). A `@procedure` then
  gets it upper-cased, as DCL does with any unquoted parameter;
- the line length is DCL's, not `ARG_MAX`: a foreign command's arguments are one command
  element, and 3997 bytes worked where 4002 gave %DCL-W-TKNOVF (probed on IA64). find and
  xargs budget `VMS_SPAWN_ARGS_MAX` (3990); a line that is still too long after quoting is
  refused before spawning, and buildcmd retries with fewer arguments;
- the procedure exits with the command's status and the message suppressed
  (`STS$M_INHIB_MSG`), so a failing command's message appears once;
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

**Status:** decided by the user (2026-10-09); implemented in `vms/vms_names.c` and patch 0009;
smoke-tested on IA64.

`find . ` and `find tree` print Unix names (`tree/sub/two.txt`), as on Unix, for scripts and
the family's Unix tools. `find []` and `find [.tree]` print VMS names (`[.tree.sub]two.txt`),
which DCL verbs in `-exec` (TYPE, DELETE, SET FILE) accept. A VMS-syntax starting point is
converted to a Unix name for the walk (as vms-tar D2), and the names are converted back on
output and for `{}`:
- VMS syntax is anything with `[`, `<`, `:` or `;`, or ending in `.dir`; it is converted with
  the C RTL's `decc$translate_vms`, as in vms-tar;
- names are shown as `[.tree.sub]two.txt`, a directory as `[.tree]sub.DIR` (the file a DCL
  command acts on), always with a directory part (`[]one.txt`), with ODS-5 escapes (`^.`,
  `^_`); the starting point itself is shown as typed. `decc$to_vms` is not used: it
  upper-cases names and rejects ODS-5 ones (probed);
- covered: `-print`, `-fprint`, `-print0`, `-fprint0`, `-ls`, `-fls`, `-printf %p`, and `{}`
  in `-exec`/`-ok`; `-execdir`'s `./name` is `[]name`. Other `-printf` directives (`%h`,
  `%P`, `%f`) still give Unix forms.

**Rejected:** always Unix (DCL verbs in `-exec` cannot use the names); always VMS (breaks
scripts and tools that expect find's usual output).
