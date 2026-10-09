# Design decisions

## D1. Running commands from find -exec and xargs (open)

`find/exec.c` (`-exec`, `-execdir`, `-ok`, `-okdir`) and `xargs/xargs.c` run each command
with `fork()`, `execvp()` and `waitpid()`. VMS has no `fork()`. The command is usually
something a DCL user types: a DCL verb (`TYPE`, `DELETE`), a foreign-command symbol
(`grep`, `gzip` from the family's kits) or an image.

To settle:
- **How it runs:** `LIB$SPAWN` of a DCL command line (verbs and symbols work; one
  subprocess per command, which is slow for `-exec ... \;` over many files) or
  `vfork()`/`execv()` of an image (fast, but no verbs or symbols).
  vms-tar's `vms_spawn.c` uses `LIB$SPAWN` with a generated procedure.
- **Quoting:** each argument must survive DCL with its case (quote every argument).
- **Output:** the command's SYS$OUTPUT should be find's or xargs's stdout, not a file.
- **Exit status:** map the subprocess's VMS status to the 0 / non-zero that `-exec` and
  xargs's 123-127 depend on.
- **Parallel xargs (`-P`)** needs asynchronous `LIB$SPAWN` (NOWAIT) and a wait for any.
