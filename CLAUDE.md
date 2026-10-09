# CLAUDE.md

Guidance for working in this repository: a port of GNU findutils to OpenVMS (IA64 and x86-64)
that stores only our deltas over the upstream release tarball. Read README.md first; it
describes the workflow and design. This file covers the rules and the pitfalls.

## Ground rules

- **Never edit `staging/`, `cache/` or `out/`.** They are regenerated. Every VMS change is
  either a patch (`patches/NNNN-*.patch`, listed in `patches/series`) or a new file in
  `overlay/`. `tools/prepare.sh` refuses overlay files that would replace upstream files.
- **Change an upstream file with a patch.** Make a pristine copy under `a/` and an edited
  copy under `b/`, run `diff -u a/<path> b/<path>`, and put a `Subject:` line and a short
  explanation above the diff. Guard VMS-only code with `#ifdef __VMS` so the patch could go
  upstream. Patches to the same file stack, so diff against the tree as it stands after the
  earlier patches.
- **Configuration answers** go in `overlay/vms/config/vms-manual.site`, each with a comment
  explaining why. Plain `var=value` lines there override the generated
  `configure-<node>.cache`. Overriding a gnulib result often needs its `gl_cv_*` variable
  too, not just `ac_cv_*` (`mempcpy` needed `gl_cv_onwards_func_mempcpy`).
- **Committed files must not contain real node details.** Use `<ia64-host>`, `<x86-host>`
  and `DISK$USER:[USERNAME.VMS_FINDUTILS]`. The real values live only in the git-ignored
  `tools/nodes.conf`.
- Keep `docs/TESTING.md` and the README status table in step with test results.

## Commands

```sh
tools/prepare.sh                        # always first after changing patches/overlay
tools/build.sh <ia64|x86> [ALL|CLEAN] [KEEP_GOING]
tools/test.sh <node>                    # smoke test
tools/vms.sh <node> dcl '<cmd>' ...     # run DCL; also run/batch/put/get
tools/kit.sh <node>                     # PCSI kit -> out/kits/ (producer ISSINOHO)
tools/installcheck.sh <node>            # install kit, verify, smoke-test, remove (changes system; ask first)
tools/vms_configure.sh <node>           # once per upstream release (slow)
```

Run configure (about an hour per node) and full builds with `run_in_background`.
MMS does not track compiler flags: after changing `ccflags.txt` or `CFLAGS` in
`descrip.mms`, run `tools/build.sh <node> CLEAN` first.

## VMS and tooling pitfalls (learned the hard way)

- **Use `tools/vms.sh`, never raw `ssh host cmd`.** Raw ssh output is often lost, and
  sessions sometimes never close. vms.sh logs to a file and waits for a completion marker.
- **Never use `WAIT` in DCL run over ssh**; it hangs (batch jobs are fine).
- **Never edit a bash script that is running.** bash reads scripts incrementally. Replace
  long-running tools atomically (write a copy, then `mv`).
- **Don't use `pkill -f` / `pgrep -f`** with a pattern that also matches your own shell's
  command line. Kill by explicit PID. On VMS, stop only processes this session started
  (they are network/batch processes of the work account); leave interactive sessions alone.
- **DCL details:**
  - `F$SEARCH` with a wildcard needs a stream id when other `F$SEARCH` calls happen in the
    same loop.
  - Batch jobs default to `/LIST` and `/MAP`.
  - DCL command lines are limited to about 4096 bytes (hence the wildcard librarian step).
  - `CALL` arguments are upper-cased unless quoted.
  - `SYS$LOGIN:[.X]` is not valid on these nodes.
- **`sftp put -r` into an existing directory nests a copy**; push.sh uploads file by file.
- **Run `tools/prepare.sh` after every change to `patches/` or `overlay/`.** build.sh and
  kit.sh push whatever is in `staging/`; forgetting this once shipped a stale kit.
- **stdout on VMS is often record-oriented** (terminal, `/OUTPUT` log, mailbox). The CRTL
  turns each `fwrite` item into a record (patch 0004), and a host-side `grep` treats
  output containing a NUL as binary (use `grep -a`).
- **Layout:** gnulib is in `gl/lib/` (LIBGNU.OLB, objects in `[.OBJ_<arch>.LIB]`).
  findutils' own `lib/` (libfind) and `find/`'s libfindtools are compiled into
  `[.OBJ_<arch>]` and linked directly. Four images: FIND, XARGS, LOCATE, FRCODE (frcode
  shares locate's `word_io.c`). `config.h` is at the top of the tree
  (`GEN_MMS_CONFIG_DIR=` in prepare.sh). `gen_mms.py` takes one `MACRO=<dir>:<list>`
  group per program.
- **Exit codes:** find's 1 and xargs's 1 and 123-127 all mean failure; `vms/vms_exit.c`
  gives every non-zero code error severity (unlike vms-tar, where 1 is a warning).
- **Known porting work** (from the CRTL quirks met in vms-gzip, vms-grep and vms-tar):
  - `find -exec`/`-execdir`/`-ok` (`find/exec.c`) and xargs (`xargs/xargs.c`) run
    commands with `fork()` + `execvp()` + `waitpid()`; VMS has no `fork()`. How a command
    runs on VMS (image vs DCL command, quoting, output) is docs/DECISIONS.md D1;
  - `open()` of a directory fails with ENOENT (patch 0005, from vms-tar);
  - a directory named in VMS syntax lists VMS-form entries (`one^.txt;1`); starting points
    given as `[.dir]` will need translating to Unix names (vms-tar D2, `vms_names.c`);
  - `updatedb` is a shell script; locate needs a DCL replacement before it can ship;
  - `>` on the command line is not redirected; use `PIPE`;
  - no `#include_next`; `mempcpy` is a macro; argument case under traditional parse style.

## Commits

Commit in logical steps with messages that explain the VMS reason for each change. Don't
push without the user asking. The GitHub remote is `origin`
(github.com/issinoho/vms-findutils), branch `main`.
