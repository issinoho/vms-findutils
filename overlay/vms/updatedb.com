$! UPDATEDB.COM - build the locate database (DCL in place of updatedb.sh)
$!
$! Usage:  @FINDUTILS$ROOT:[BIN]UPDATEDB [directories] [database] [image-dir]
$!
$!   P1  directories to index, separated by commas, in VMS syntax
$!       (DKA0:[USERS],DKA100:[000000]); default: [000000] of every mounted
$!       local disk (not foreign mounts, shadow set members or remote disks)
$!   P2  the database; default FINDUTILS$ROOT:[DB]LOCATEDB.
$!   P3  the directory holding FIND.EXE and FRCODE.EXE; default
$!       FINDUTILS$ROOT:[BIN]
$!
$! The names are in VMS syntax (DKA0:[USERS.X]LOGIN.COM; docs/DECISIONS.md
$! D3): FIND.EXE walks each directory, SORT orders the names, and FRCODE.EXE
$! writes the database, which replaces the old one only when all of this
$! worked.  Directories the account may not read are skipped, as by
$! updatedb on Unix; run it from a privileged account (or a batch job
$! submitted by the system manager) to index everything:
$!
$!   $ SUBMIT/NOPRINT/AFTER="TOMORROW+02:00" FINDUTILS$ROOT:[BIN]UPDATEDB.COM
$!
$ set noon
$ on control_y then goto done
$ status = 44                           ! SS$_ABORT unless it completes
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ roots = p1
$ db = p2
$ if db .eqs. "" then db = "FINDUTILS$ROOT:[DB]LOCATEDB."
$ bin = p3
$ if bin .eqs. "" then bin = "FINDUTILS$ROOT:[BIN]"
$ u_find = "$" + f$parse("FIND.EXE", bin)
$ u_frcode = "$" + f$parse("FRCODE.EXE", bin)
$!
$! The directories: each one quoted, so DCL keeps its case.
$ args = ""
$ if roots .nes. "" then goto list_given
$ dev_loop:
$ dev = f$device("*", "DISK")
$ if dev .eqs. "" then goto list_done
$ if .not. f$getdvi(dev, "MNT") then goto dev_loop
$ if f$getdvi(dev, "FOR") then goto dev_loop
$ if f$getdvi(dev, "SHDW_MEMBER") then goto dev_loop
$ if f$getdvi(dev, "REMOTE_DEVICE") then goto dev_loop
$ name = f$getdvi(dev, "DEVNAM") - "_"
$ args = args + " """ + name + "[000000]"""
$ goto dev_loop
$ list_given:
$ i = 0
$ given_loop:
$ r = f$element(i, ",", roots)
$ if r .eqs. "," then goto list_done
$ r = f$edit(r, "TRIM")
$ if r .nes. "" then args = args + " """ + r + """"
$ i = i + 1
$ goto given_loop
$ list_done:
$ if args .eqs. ""
$ then
$   write sys$error "UPDATEDB: nothing to index"
$   goto done
$ endif
$!
$ tag = f$getjpi("", "PID")
$ names = "SYS$SCRATCH:UPDATEDB_''tag'_NAMES.TMP"
$ sorted = "SYS$SCRATCH:UPDATEDB_''tag'_SORTED.TMP"
$ errors = "SYS$SCRATCH:UPDATEDB_''tag'_ERRORS.TMP"
$ new = f$parse(".TMP_NEW", db)
$ write sys$output "UPDATEDB: indexing''args'"
$!
$! The master directory lists itself (000000.DIR): never descend into it.
$ define/user sys$output 'names'
$ define/user sys$error 'errors'
$ u_find 'args' -name "000000" -prune -o -print
$ if f$search(errors) .nes. ""
$ then
$   if f$file_attributes(errors, "EOF") .gt. 0 then -
        write sys$output "UPDATEDB: some directories could not be read (see ''errors')"
$ endif
$ if f$search(names) .eqs. ""
$ then
$   write sys$error "UPDATEDB: find produced no list"
$   goto cleanup
$ endif
$ sort 'names' 'sorted'
$ if .not. $status then goto cleanup
$ define/user sys$input 'sorted'
$ u_frcode "''new'"
$ if .not. $status then goto cleanup
$ rename 'new' 'db'
$ if .not. $status then goto cleanup
$ purge/nolog/keep=1 'db'
$ write sys$output "UPDATEDB: wrote ''f$search(db)'"
$ status = 1
$ cleanup:
$ if f$search(names) .nes. "" then delete/nolog 'names';*
$ if f$search(sorted) .nes. "" then delete/nolog 'sorted';*
$ if status .and. f$search(errors) .nes. "" then -
     if f$file_attributes(errors, "EOF") .eq. 0 then delete/nolog 'errors';*
$ if f$search(new) .nes. "" then delete/nolog 'new';*
$ done:
$ set process/parse_style='saved_parse'
$ exit status
