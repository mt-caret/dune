A workspace pin with a relative "file://" url locks correctly. A build after
that lock stops with an internal error. This defect appeared during work on the
opam repository of OxCaml with dune package management.

The cause is a difference between two sibling functions. Both apply the same
test for a local source, but each handles a relative path in a different way.
Source.kind calls Path.External.of_string. That function raises a Code_error
for a relative path. Lock_dir.source_kind calls
Path.of_string_allow_outside_workspace. That function accepts a relative path.

The build rules of the pinned package use the tolerant function in lock_dir, so
a build of the pinned package alone does not fail.
Fetch_rules.extract_checksums_and_urls uses the strict function in source, and
it scans every source in the lock directory. That scan calls Source.kind before
it reads the checksum. Every source of kind "Fetch" starts the scan, so a
checksum on the other package is not necessary. As a result one relative
file:// pin stops the build of an unrelated package.

OpamUrl keeps a "file://<relative>" path unchanged, so the lock directory
records a relative source url.

The correct behavior is one of two things. Dune must reject or resolve the
relative file:// url at lock time, and print a normal user error. Or dune must
handle a relative file:// url in the same way as a plain relative path. See the
contrast at the end of this test. An internal error at build time is wrong in
both cases.

  $ mkrepo

A package with an http source. The url points at port 1 on the local machine,
so no process can accept the connection. This test needs no network.

  $ mkpkg foo <<EOF
  > url {
  >  src: "http://localhost:1/foo.tar"
  >  checksum: ["md5=00000000000000000000000000000000"]
  > }
  > EOF

CONTROL A: the same package foo, and no pin in the workspace. Dune prints a
normal user error about curl, and no internal error. This control proves that
the pin below causes the internal error, and that the http source does not
cause it.

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (lock_dir
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name main)
  >  (allow_empty)
  >  (depends foo))
  > EOF

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1

  $ build_pkg foo
  File "dune.lock/foo.0.0.1.pkg", line 5, characters 7-33:
  5 |   (url http://localhost:1/foo.tar)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: 'curl' returned an invalid error code 7
         
         
  [1]


A local directory for the pin:

  $ mkdir _relative
  $ cat >_relative/dune-project <<EOF
  > (lang dune 3.13)
  > (package (name pinned) (allow_empty))
  > EOF

The workspace pins the local package with a relative file:// url:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (pin
  >  (name pinned)
  >  (url "file://_relative/")
  >  (package (name pinned)))
  > (lock_dir
  >  (pins pinned)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

  $ cat >dune-project <<EOF
  > (lang dune 3.13)
  > (package
  >  (name main)
  >  (allow_empty)
  >  (depends pinned foo))
  > EOF

  $ dune clean

The lock command succeeds:

  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1
  - pinned.dev

DEFECT 1: the lock file records the relative url without a change:

  $ print_source "pinned.dev"
  (source (fetch (url file://_relative/)))

DEFECT 2: a build of the package foo now stops with an internal error. The
checksum scan calls Source.kind on the relative pin url. Compare this output
with CONTROL A above. The package foo and its source url are the same in both
places. Only the pin is different.

The test cuts the output at the first "Raised at" line. The frames below that
line hold dune source line numbers that change with every edit.

  $ build_pkg foo 2>&1 | awk '/Internal error/,/Raised/'
  Internal error! Please report to https://github.com/ocaml/dune/issues,
  providing the file _build/trace.csexp, if possible. This includes build
  commands, message logs, and file paths.
  Description:
    ("Path.External.of_string: relative path given", { t = "_relative/" })
  Raised at Stdune__Code_error.raise in file
  [1]

CONTROL B: a pin with an absolute file:// url. The scheme stays the same and
only the path changes, from relative to absolute. The package foo stays in the
workspace. This control proves that the relative path causes the internal
error, and that the file:// scheme does not cause it.

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (pin
  >  (name pinned)
  >  (url "file://$(pwd)/_relative/")
  >  (package (name pinned)))
  > (lock_dir
  >  (pins pinned)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

  $ dune clean
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1
  - pinned.dev

  $ print_source "pinned.dev" | dune_cmd subst "$PWD" PWD
  (source (fetch (url file://PWD/_relative/)))

The build of foo gives the same normal user error as CONTROL A. There is no
internal error:

  $ build_pkg foo
  File "dune.lock/foo.0.0.1.pkg", line 5, characters 7-33:
  5 |   (url http://localhost:1/foo.tar)
             ^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: 'curl' returned an invalid error code 7
         
         
  [1]


Contrast: a plain relative path without a "file://" scheme. OpamUrl resolves it
to an absolute path at lock time, so the build does not stop. This test changes
only the pin url and locks again:

  $ cat >dune-workspace <<EOF
  > (lang dune 3.20)
  > (pin
  >  (name pinned)
  >  (url "_relative/")
  >  (package (name pinned)))
  > (lock_dir
  >  (pins pinned)
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

  $ dune clean
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - foo.0.0.1
  - pinned.dev

The plain relative path became an absolute file:/// url. As a result
Source.kind accepts it:

  $ print_source "pinned.dev" | dune_cmd subst "$PWD" PWD
  (source (fetch (url file://PWD/_relative)))
