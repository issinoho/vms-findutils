# Porting log

One entry per build or run problem, newest last. Triage codes:
- T toolchain
- P probe or configure
- H header
- L libc (CRTL)
- F filesystem
- S shell or process
- U upstream

## 2026-10-09: scaffold (from vms-tar)

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| – | Generic patches from vms-tar | gnulib is in `gl/lib/`, not `gnu/`; findutils' gnulib is newer | Patches 0001-0004 retargeted. 0003 (assert guard) rebased: config.h.in no longer has the `__sgi` block |
| L | `open()` of a directory (vms-tar patch 0008) | gnulib's `open.c` now checks `lstatif` and `check_directory` | Patch 0005 rebased onto it; still keeps `open()`'s errno instead of EACCES |
| P | Host prepare: `sed: unknown option to 's'` making `stdbit.h` | glibc has `<stdbit.h>`; gnulib's rule puts `NEXT_STDBIT_H` (a path) into a `/`-delimited sed expression | `vms-manual.site`: `ac_cv_header_stdbit_h=no` (VSI C has no STDBIT module) |
| T | `prepare.sh` not executable | Copied from vms-tar, where it is mode 644 in git | `chmod +x` |

## 2026-10-09: configure and first build (IA64 V8.4-2L3)

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| P | configure: 70 min, 636 tests compiled on VMS | findutils' gnulib is larger than tar's | none; 48 answers left from the host run, all build-tool paths except `am_cv_func_working_getline` (gnulib's getline is used, harmless) |
| H | `_POSIX_ARG_MAX`, `_POSIX_OPEN_MAX` undeclared (`lib/buildcmd.c`, `lib/fdleak.c`) | VSI C's `<limits.h>` lacks the POSIX minimum constants | `ccflags.txt` defines them with POSIX's fixed values, 4096 and 20 |
| U | `#error "Please port gnulib mountlist.c to your platform!"` | gnulib's mount list has no OpenVMS method | `mountlist.c` left out (`lib-exclude.txt`); `vms_mountlist.c` returns no list, which find handles: `-fstype` reports "unknown" |
| T | `LOCATE_DB` undeclared in `locate.c` | locate's Makefile passes it with `-D` | locate and frcode left out of `ALL` (target `LOCATE` keeps their rules) until updatedb has a DCL replacement |

## 2026-10-09: smoke test (IA64)

`[.VMS]TEST_SMOKE.COM` passes 25 of 25 on IA64.

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| S | xargs: `assert (bc_ctl.arg_max >= LINE_MAX)` at startup | The C RTL's ARG_MAX is 4096 (LINE_MAX 2048); less xargs's 2048 bytes of POSIX headroom and the environment, under 2048 were left | Patch 0008: the budget is DCL's (D1), with no headroom or environment; xargs skips the `sysconf` clamp (patch 0007) |
| S | `%DCL-W-TKNOVF` for long xargs commands | A foreign command's arguments are one DCL command element, limited to about 4000 bytes (probed: 3997 ok, 4002 not; 16 x 250-byte arguments not) | `VMS_SPAWN_ARGS_MAX` 3990; longer lines are refused before spawning and buildcmd retries with fewer arguments (800 names run as several commands) |
| S | `-exec failcmd ;` was true | `-exec ... ;` decodes `last_child_status` with `WIFEXITED`, which launch () never set on VMS | Patch 0006 stores the exit code there and tests it directly |
| S | A failing command's message shown twice | The generated procedure's `exit $status` repeated it | Exit with `STS$M_INHIB_MSG` set |
| S | `TYPE "[.tree]one.txt"`: %RMS-F-FNM | DCL verbs keep the quotes of a quoted file specification | VMS file specifications are not quoted (D1) |
| F | `find [.tree]`: "no such file or directory" | find walks with Unix names and openat; `[.tree]/sub` would be no use either | D2: `vms_names.c` + patch 0009 |
| – | Test expectations | The C RTL's strerror is lower case ("no such file or directory"); DCL upper-cases a `@procedure`'s unquoted parameters; `$SEVERITY` must be read before a `CALL` | Smoke test corrected |

## 2026-10-10: locate (D3)

| Code | Problem | Root cause | Fix |
|------|---------|------------|-----|
| S | No updatedb | It is a shell script | `vms/updatedb.com`: FIND.EXE, SORT, FRCODE.EXE |
| F | The database could not be written from DCL | Redirected standard output is a record file; the database holds NULs and 0x0A bytes | Patch 0010: frcode writes the file named by its argument, in binary |
| P | `LOCATE_DB` undefined | findutils' Makefile passes it with `-D` | descrip.mms: `FINDUTILS$ROOT:[DB]LOCATEDB.` |
| S | `locate x` with no match left DCL success | `main` returned instead of calling `exit()` | Patch 0011: `exit()` on VMS (a missing database still exits 0, as upstream) |
| – | A device root in a DCL parameter came out lower case | Traditional parse style lower-cases unquoted arguments to a C program | UPDATEDB.COM quotes each root and runs with PARSE_STYLE=EXTENDED |
