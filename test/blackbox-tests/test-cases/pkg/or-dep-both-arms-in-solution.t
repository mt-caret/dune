This test shows a bug in how dune records an or-dependency ("a" | "b") in a
lock file. The bug appears when the solution holds both arms of the
disjunction.

Two sites in src/dune_pkg/resolve_opam_formula.ml decide the result, so a patch
to formula_to_package_names alone changes nothing. The second site,
formula_to_package_names_allow_missing, uses List.find_map over the CNF clauses
and keeps only the first arm that the solution holds.

Its result becomes regular_set in filtered_formula_to_package_names, and the
other arm becomes a post dependency. src/dune_pkg/lock_pkg.ml drops the post
dependencies.

The most serious effect of this bug is a silent wrong result. The build action
finds a program with the same name on the ambient PATH. The build then
succeeds with the wrong program, and dune reports no error. The block near the
end of this test shows that effect.

A reviewer can dispute two weaker points. First, package x declares
'depends: [ "a" | "b" ]', but the build of x needs a file that only b
installs. The metadata of x can be at fault. Second, a lock file that holds
every satisfiable arm makes the dependency closure larger than necessary.

The formula alone does not name the arm that provides the files, so dune
cannot select the one arm that the build needs. The achievable correct
behavior is this: dune must record every arm that the solution holds. A patch
to both sites gives '(depends (all_platforms (a b)))'.

The upstream "ocaml" package has the formula
"ocaml-base-compiler" | "ocaml-variants", but it does not show this bug with
real opam metadata. Both compiler packages carry
'conflict-class: "ocaml-core-compiler"', so they cannot both be in one
solution and dune records the correct arm. A test with the helper mk_ocaml
gives '(depends (all_platforms (ocaml-variants)))'.

The failure needs a different repository shape. The arm that wins must be an
empty package without that conflict class. This shape happens when a user adds
an empty local pin to satisfy one arm of a formula. The workaround in
ocaml/dune#15509 is an example of such a pin.

  $ mkrepo

Package "a" is an empty package. It installs no files.

  $ mkpkg a <<EOF
  > EOF

Package "b" installs a program with the name "btool".

  $ mkpkg b <<EOF
  > install: [
  >   [ "sh" "-c" "echo '#!/bin/sh' > %{bin}%/btool" ]
  >   [ "sh" "-c" "echo 'echo btool from package b' >> %{bin}%/btool" ]
  >   [ "sh" "-c" "chmod a+x %{bin}%/btool" ]
  > ]
  > EOF

Package "x" depends on "a" or "b". The build of "x" runs the program from "b".
As a result, dune must put the "b" arm into the dependencies of "x".

  $ mkpkg x <<EOF
  > depends: [ "a" | "b" ]
  > build: [ "btool" ]
  > EOF

The project depends on "x" and also on "b". The solver satisfies the
disjunction in "x" with the first arm "a". The direct dependency forces "b"
into the solution. As a result, the solution holds both arms:

  $ solve_project <<EOF
  > (lang dune 3.11)
  > (package
  >  (name proj)
  >  (depends x b))
  > EOF
  Solution for dune.lock:
  - a.0.0.1
  - b.0.0.1
  - x.0.0.1

The lock file for "x" records only the first arm "a". The solution also holds
"b", but the lock file omits "b":

  $ cat dune.lock/x.0.0.1.pkg
  (version 0.0.1)
  
  (build
   (all_platforms ((action (run btool)))))
  
  (depends
   (all_platforms (a)))



This control shows that the lock directory holds package "b". The error text
in the block below also appears when "b" is absent from the lock directory.
That error text alone does not prove the condition that this test claims:

  $ ls dune.lock
  a.0.0.1.pkg
  b.0.0.1.pkg
  lock.dune
  x.0.0.1.pkg

This control shows the content of the locked "b". It proves that the arm that
the lock file of "x" omits is the arm that installs "btool":

  $ cat dune.lock/b.0.0.1.pkg
  (version 0.0.1)
  
  (install
   (all_platforms
    (progn
     (run sh -c "echo '#!/bin/sh' > %{bin}/btool")
     (run sh -c "echo 'echo btool from package b' >> %{bin}/btool")
     (run sh -c "chmod a+x %{bin}/btool"))))


The build of "x" fails. Package "b" is absent from the dependency closure of
"x", so "btool" is absent from the PATH of the build action of "x":

  $ build_pkg x
  File "dune.lock/x.0.0.1.pkg", line 4, characters 30-35:
  4 |  (all_platforms ((action (run btool)))))
                                    ^^^^^
  Error: Program btool not found in the tree or in PATH
   (context: default)
  [1]

The next block runs the build action of "x" a second time. This second run
happens only because the build above it failed. dune caches a successful
build, so a repeat of a successful build runs no action.

The next block puts a program with the name "btool" on the ambient PATH. The
build of "x" then uses the program from the host. dune reports no error. This
is the silent wrong result:

  $ mkdir host-bin
  $ cat > host-bin/btool <<EOF
  > #!/bin/sh
  > echo btool from the HOST, not from package b
  > EOF
  $ chmod +x host-bin/btool
  $ PATH="$PWD/host-bin:$PATH" build_pkg x
  btool from the HOST, not from package b

The next control swaps the two arms of the formula of "x" to [ "b" | "a" ] and
changes nothing else. It proves that the order of the arms alone decides what
dune records. It also proves that the build of "x" succeeds when dune records
the "b" arm.

  $ mkdir swapped
  $ cd swapped
  $ mkrepo
  $ mkpkg a <<EOF
  > EOF
  $ mkpkg b <<EOF
  > install: [
  >   [ "sh" "-c" "echo '#!/bin/sh' > %{bin}%/btool" ]
  >   [ "sh" "-c" "echo 'echo btool from package b' >> %{bin}%/btool" ]
  >   [ "sh" "-c" "chmod a+x %{bin}%/btool" ]
  > ]
  > EOF
  $ mkpkg x <<EOF
  > depends: [ "b" | "a" ]
  > build: [ "btool" ]
  > EOF

The solver prefers the first arm here too. The first arm is now "b", so the
solver never needs "a". As a result, "a" is absent from the solution:

  $ solve_project <<EOF
  > (lang dune 3.11)
  > (package
  >  (name proj)
  >  (depends x b))
  > EOF
  Solution for dune.lock:
  - b.0.0.1
  - x.0.0.1

dune records the "b" arm:

  $ cat dune.lock/x.0.0.1.pkg
  (version 0.0.1)
  
  (build
   (all_platforms ((action (run btool)))))
  
  (depends
   (all_platforms (b)))



The build of "x" now succeeds. It runs the program from package "b":

  $ build_pkg x
  btool from package b
