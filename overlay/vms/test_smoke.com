$! TEST_SMOKE.COM - quick functional check of built or installed FIND.EXE and XARGS.EXE
$!
$! Usage:  @[.VMS]TEST_SMOKE [find-image]
$!         The default image is [.BIN_<arch>]FIND.EXE in this tree; XARGS.EXE
$!         is taken from the same directory.
$! Exits with SS$_NORMAL if every test passes, otherwise reports failures.
$! Every test runs with SYS$OUTPUT and SYS$ERROR redirected to files, the
$! case vms_spawn.c must handle for -exec and xargs (DECISIONS D1).
$!
$ set noon
$ on control_y then goto finish
$ saved_default = f$environment("DEFAULT")
$ saved_parse = f$getjpi("", "PARSE_STYLE_PERM")
$ set process/parse_style=extended
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ image = p1
$ if image .eqs. "" then image = f$parse("[.BIN_''arch']FIND.EXE")
$ ximage = f$parse("XARGS.EXE;", image)
$ if f$search(image) .eqs. "" .or. f$search(ximage) .eqs. ""
$ then
$   write sys$error "SMOKE: no image ''image' or ''ximage'"
$   exit 44
$ endif
$! Global, so the subprocesses that -exec and xargs create see them too.
$ find :== $'image'
$ xargs :== $'ximage'
$ pass == 0
$ fail == 0
$ skip == 0
$! Start from an empty work directory each run.
$ if f$search("SMOKE_TMP.DIR") .eqs. "" then create/directory [.SMOKE_TMP]
$ set default [.SMOKE_TMP]
$ call emptydir
$!
$! --- fixtures -------------------------------------------------------------
$ create ref.txt
the first line
$ create/directory [.tree.sub]
$ create/directory [.tree.empty]
$ copy/nolog ref.txt [.tree]one.txt
$ copy/nolog ref.txt [.tree.sub]two.txt
$! ECHO: a DCL procedure that writes its parameters, separated by spaces.
$! DECK/EOD: CREATE alone would stop at the first line starting with $.
$ create echo.com
$ deck
$ s = p1
$ if p2 .nes. "" then s = s + " " + p2
$ if p3 .nes. "" then s = s + " " + p3
$ if p4 .nes. "" then s = s + " " + p4
$ if p5 .nes. "" then s = s + " " + p5
$ if p6 .nes. "" then s = s + " " + p6
$ if p7 .nes. "" then s = s + " " + p7
$ if p8 .nes. "" then s = s + " " + p8
$ write sys$output s
$ exit 1
$ eod
$ create fail.com
$ deck
$ exit 44
$ eod
$ echo :== @'f$environment("DEFAULT")'ECHO.COM
$ failcmd :== @'f$environment("DEFAULT")'FAIL.COM
$ create names.txt
a b
c
$ treelist = "tree|tree/empty|tree/one.txt|tree/sub|tree/sub/two.txt"
$!
$! --- find ---------------------------------------------------------------
$ call t version   0 ""                      "find --version"
$ call t list      0 "''treelist'"           "find tree"
$ call t list-vms  0 "''treelist'"           "find [.tree]"
$ call t name      0 "tree/one.txt|tree/sub/two.txt" "find tree -name ""*.txt"""
$ call t type-d    0 "tree|tree/empty|tree/sub"      "find tree -type d"
$ call t empty     0 "tree/empty"            "find tree -empty"
$ call t missing   1 "find: 'nosuch': No such file or directory" "find nosuch"
$!
$! --- find -exec (DCL through LIB$SPAWN) --------------------------------
$ call t exec-verb 0 "tree/one.txt"          "find tree -name one.txt -exec write sys$output {} ;"
$ call t exec-proc 0 "tree/one.txt|tree/sub/two.txt" "find tree -name ""*.txt"" -exec echo {} ;"
$ call t exec-plus 0 "tree/one.txt tree/sub/two.txt" "find tree -name ""*.txt"" -exec echo {} +"
$ call t exec-case 0 "MiXed tree/one.txt"    "find tree -name one.txt -exec echo MiXed {} ;"
$ call t exec-false 0 ""                     "find tree -name one.txt -exec failcmd ; -print"
$ call t execdir   0 "./two.txt"             "find tree -name two.txt -execdir echo {} ;"
$!
$! --- xargs --------------------------------------------------------------
$ call t xargs     0 "a b c"                 "xargs echo"       names.txt
$ call t xargs-n   0 "a|b|c"                 "xargs -n 1 echo"  names.txt
$ call t xargs-123 123 ""                    "xargs failcmd"    names.txt
$ call t xargs-127 127 "*"                   "xargs nosuchverb" names.txt
$!
$! find piped into xargs, as on Unix.
$ if f$search("pipe.txt") .nes. "" then delete/nolog pipe.txt;*
$ pipe find tree -name "*.txt" | xargs echo > pipe.txt
$ open/read f pipe.txt
$ read/end=pipe_eof f line
$pipe_eof:
$ close f
$ call check pipe "line .eqs. ""tree/one.txt tree/sub/two.txt"""
$!
$! Under DCL a failure must have error severity, so ON ERROR and
$! IF .NOT. $STATUS see it.
$ define/user sys$output nl:
$ define/user sys$error nl:
$ find nosuch
$ call check severity "$severity .eq. 2"
$!
$! No temporary files left in SYS$SCRATCH.
$ call check scratch "f$search(""SYS$SCRATCH:FIND_*.*"") .eqs. """" .and. f$search(""SYS$SCRATCH:XARGS_*.*"") .eqs. """""
$!
$finish:
$ set default 'vmsdir'
$ set default [-]
$ set process/parse_style='saved_parse'
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed, ''skip' skipped (''image')"
$ set default 'saved_default'
$ delete/symbol/global find
$ delete/symbol/global xargs
$ delete/symbol/global echo
$ delete/symbol/global failcmd
$ if fail .eq. 0 .and. pass .gt. 0 then exit 1
$ exit 44
$!
$! --- T name expected-exit expected-output command [input-file] -----------
$! An expected output of "*" is not compared.
$t: subroutine
$ set noon
$ if f$search("out.txt") .nes. "" then delete/nolog out.txt;*
$ if f$search("err.txt") .nes. "" then delete/nolog err.txt;*
$! Separate files: two streams on one name would make two versions.
$ define/user sys$output out.txt
$ define/user sys$error err.txt
$ if p5 .nes. "" then define/user sys$input 'p5'
$ 'p4'
$ st = $status
$! _POSIX_EXIT: the C exit code is in bits 3..10 of the VMS status.
$ code = (st .and. %X7F8) / 8
$ got = ""
$ do = "out.txt"
$readfile:
$ if f$search(do) .eqs. "" then goto nextfile
$ open/read f 'do'
$readloop:
$ read/end=readdone f line
$ if got .nes. "" then got = got + "|"
$ got = got + f$edit(line, "TRIM,COMPRESS")
$ if f$length(got) .gt. 300 then goto readdone
$ goto readloop
$readdone:
$ close f
$nextfile:
$ if do .eqs. "err.txt" then goto compare
$ do = "err.txt"
$ goto readfile
$compare:
$ ok = code .eq. f$integer(p2)
$! (DCL upper-cases the unquoted test name.)
$ if p1 .eqs. "VERSION"
$ then
$   ok = ok .and. (f$locate("find (GNU findutils) 4.", got) .eq. 0)
$ else
$   if p3 .nes. "*" then ok = ok .and. (got .eqs. f$edit(p3, "TRIM,COMPRESS"))
$ endif
$ if ok
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": exit ", code, " (want ", p2, "), output [", got, "] (want [", p3, "])"
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- CHECK name dcl-expression ----------------------------------------
$check: subroutine
$ if 'p2'
$ then
$   write sys$output "PASS ", p1
$   pass == pass + 1
$ else
$   write sys$output "FAIL ", p1, ": ", p2
$   fail == fail + 1
$ endif
$ exit 1
$ endsubroutine
$!
$! --- EMPTYDIR: delete everything under the current directory -------------
$! Directory files must be writable and empty to go, so repeat the delete
$! until nothing is left (the tests nest three levels below [.SMOKE_TMP]).
$emptydir: subroutine
$ set noon
$ if f$search("[...]*.*;*") .eqs. "" then exit 1
$ define/user sys$output nl:
$ define/user sys$error nl:
$ set protection=(s:rwed,o:rwed) [...]*.*;*
$ n = 0
$emptyloop:
$ define/user sys$output nl:
$ define/user sys$error nl:
$ delete/nolog [...]*.*;*
$ n = n + 1
$ if f$search("[...]*.*;*") .nes. "" .and. n .lt. 6 then goto emptyloop
$ exit 1
$ endsubroutine
