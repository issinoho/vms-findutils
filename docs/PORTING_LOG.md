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
