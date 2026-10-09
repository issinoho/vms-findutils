# vms-findutils

GNU findutils 4.11.0 (find and xargs) for OpenVMS (IA64 and x86-64), built natively with VSI C.

The repository stores only our changes over the signed upstream release:
- `patches/` holds changes to upstream files, applied in `patches/series` order.
- `overlay/` holds new files: VMS build procedures, C RTL shims and the PCSI kit.

`tools/prepare.sh` combines them with the tarball into `staging/`, which is pushed to a VMS node and built there with MMS. The tooling is shared with the other ports in the family; see [vms-grep](https://github.com/issinoho/vms-grep) for the list.

## Status

| Step | IA64 (V8.4-2L3) | x86-64 (E9.2-4) |
|------|-----------------|-----------------|
| Configure with VSI C (`tools/vms_configure.sh`) | done | done (same answers) |
| Build (`tools/build.sh`) | clean | clean |
| DCL smoke test, 25 checks (`tools/test.sh`) | 25/25 | 25/25 |
| PCSI kit `ISSINOHO <base> FINDUTILS V4.11-0E1` (`tools/kit.sh`) | built | built |
| Install check (`tools/installcheck.sh`): install, smoke 25/25, clean removal | pass | pass |

## Using it

```
$ @FINDUTILS$ROOT:[000000]FINDUTILS$SETUP.COM
$ find . -name "*.c"                          ! Unix names: ./src/main.c
$ find [] -name "*.c"                         ! VMS names:  [.src]main.c
$ find [] -name "*.log" -exec delete {};* ;   ! DCL verbs work with VMS names
$ pipe find . -name "*.c" | xargs grep -l main
```

- **Commands:** `-exec`, `-execdir`, `-ok` and xargs run the command as DCL in a subprocess
  (LIB$SPAWN), so DCL verbs, foreign-command symbols and `@procedures` all work. The words
  you type are DCL syntax, so qualifiers work; file names are quoted unless they are VMS file
  specifications. See [docs/DECISIONS.md](docs/DECISIONS.md) D1.
- **File names:** a starting point in VMS syntax (`[]`, `[.dir]`, `DKA0:[X]`, `dir.dir`) gives
  VMS names (`[.dir.sub]file.txt`, a directory as `[.dir]sub.DIR`); a Unix one (`.`, `dir`)
  gives Unix names. See D2.

**Known limits** (also in the kit's README.VMS):
- locate, updatedb and frcode are not included: updatedb is a shell script and needs a DCL
  replacement.
- `xargs -P N` runs one command at a time.
- One subprocess per command: `-exec ... ;` over many files is slow; use `-exec ... +` or
  xargs.
- A command's arguments are limited to about 4000 bytes (DCL's limit); find and xargs split
  longer lists over several commands.
- A `@procedure` gets unquoted parameters upper-cased by DCL, VMS file names included.
- `-fstype` reports `unknown`. With a VMS starting point, `-printf`'s `%h`, `%P` and `%f`
  still give Unix forms.
- `>` on the command line is not redirected by the C RTL; use `PIPE`.

## Workflow

```sh
cp tools/nodes.conf.example tools/nodes.conf   # then fill in the real nodes
tools/prepare.sh                               # fetch, verify, patch, configure, stage
tools/vms_configure.sh <node>                  # once per upstream release: configure with VSI C
tools/build.sh <node>                          # push and build with MMS
tools/test.sh <node>                           # smoke test
tools/kit.sh <node>                            # PCSI kit
tools/installcheck.sh <node>                   # install, verify, remove
```

See `CLAUDE.md` for the rules and pitfalls, `docs/PORTING_LOG.md` for each problem met and
`docs/DECISIONS.md` for the design decisions.
