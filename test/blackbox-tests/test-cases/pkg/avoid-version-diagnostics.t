This test checks how the solver handles a package when all of its candidates
carry the avoid-version flag. Opam treats avoid-version as a soft preference:
the solver gives a flagged version a lower priority, but can still install that
version if no other version works. Some packages in OxCaml's opam repository
use this flag. For example oxcaml-compiler.5.4.0-ox1 carries it, but
oxcaml-compiler.5.2.0minus39 does not.

  $ mkrepo

Every version of package "a" carries the avoid-version flag:

  $ mkpkg a 1.0 <<EOF
  > flags: avoid-version
  > EOF
  $ mkpkg a 2.0 <<EOF
  > flags: avoid-version
  > EOF

The solve succeeds. The solver picks a flagged version because no other version
works. This matches the behavior of opam.

  $ solve a
  Solution for dune.lock:
  - a.2.0 (this version should be avoided)

The solver does the same when the workspace limits the solve to one platform:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (lock_dir
  >  (solve_for_platforms
  >   ((arch x86_64)
  >    (os linux)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - a.2.0 (this version should be avoided)

  $ rm dune-workspace dune-project

Package "b" has a version 1.0 with no flag and a flagged version 2.0:

  $ mkpkg b 1.0
  $ mkpkg b 2.0 <<EOF
  > flags: avoid-version
  > EOF

Control A. With no constraint on "b", the solver picks b.1.0, the version with
no flag. This control shows that the flag gives a lower priority to b.2.0. It
is the only control that shows the lower priority, because the solves with
package "a" have no alternative without the flag.

  $ solve b
  Solution for dune.lock:
  - b.1.0

A version constraint can force a flagged version, even when a version without
the flag exists:

  $ solve "(b (>= 2.0))"
  Solution for dune.lock:
  - b.2.0 (this version should be avoided)

The error diagnostics handle avoid-version incorrectly. To show this, make the
solve fail for a reason that is not related to "a". Add a dependency on "c"
with a constraint that no version of "c" satisfies.

  $ mkpkg c 1.0

  $ solve a "(c (>= 2.0))"
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: x.dev
  - a -> (problem)
      Rejected candidates:
        a.2.0:
          Reason for rejection unknown:
          x.dev=true && a.2.0=false && a.1.0=false => (no solution found)=true
        a.1.0:
          Reason for rejection unknown:
          x.dev=true && a.2.0=false && a.1.0=false => (no solution found)=true
  - c -> (problem)
      No usable implementations:
        c.1.0: Package does not satisfy constraints of local package x
  [1]


One cause produces two symptoms in this error message. The first symptom is
that dune reports "a" as a problem and rejects every candidate of "a". Package
"a" is solvable, because the solves above picked a.2.0. The only real problem
is "c". The second symptom is the raw SAT text "x.dev=true && ..." in the
reason for each rejection. This text does not help a user.

The cause is that the diagnostic pass selects the dummy implementation for the
role of "a". Dune then prints "(problem)" for "a" and lists the real candidates
of "a" as rejected. Dune has no explainer for the cardinality clause that
rejects those candidates, so dune prints the raw SAT literals instead.

The correct behavior is an error that names only "c" and resolves "a" to a.2.0.
A patch of the one cause removes both symptoms.

The mechanism is in src/dune_pkg/opam_solver.ml. do_solve first tries the solve
with max_avoids = Some 0, and relaxes max_avoids to None only if that pass
returns None. The diagnostic pass sets closest_match = true, and that flag adds
Input.Dummy to every role.

Input.avoid returns false for Dummy, so the dummy does not count as an avoid.
The first pass always finds a solution, and the relaxation never runs. The doc
comment on do_solve already records this precondition.

Control B. Package "d" has the same two versions as "a", but with no
avoid-version flag:

  $ mkpkg d 1.0
  $ mkpkg d 2.0

The next solve has the same shape of failure as the solve above, and it fails
for the same reason. Dune reports only the true problem, "c", and dune prints
no raw SAT text. Dune also resolves "d" to d.2.0 and shows it in the list of
selected candidates. This control proves that the defect belongs to the
avoid-version path and is not a general defect of the diagnostics.

  $ solve d "(c (>= 2.0))"
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: d.2.0 x.dev
  - c -> (problem)
      No usable implementations:
        c.1.0: Package does not satisfy constraints of local package x
  [1]


Control C. Here the flagged package is the true problem, because no version of
"a" satisfies the constraint (>= 3.0). Dune prints the correct message. This
control shows that the diagnostics work for a flagged package when that
package is really unsolvable.

  $ solve "(a (>= 3.0))"
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: x.dev
  - a -> (problem)
      No usable implementations:
        a.2.0: Package does not satisfy constraints of local package x
        a.1.0: Package does not satisfy constraints of local package x
  [1]


Dune prints the same wrong error when the workspace limits the solve to one
platform. This shows that the defect is not specific to a portable solve or to
a multi-platform solve.

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  >  (package
  >   (name x)
  >   (allow_empty)
  >   (depends a (c (>= 2.0))))
  > EOF
  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (lock_dir
  >  (solve_for_platforms
  >   ((arch x86_64)
  >    (os linux)))
  >  (repositories mock))
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > EOF
  $ dune_pkg_lock_normalized
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: x.dev
  - a -> (problem)
      Rejected candidates:
        a.2.0:
          Reason for rejection unknown:
          x.dev=true && a.2.0=false && a.1.0=false => (no solution found)=true
        a.1.0:
          Reason for rejection unknown:
          x.dev=true && a.2.0=false && a.1.0=false => (no solution found)=true
  - c -> (problem)
      No usable implementations:
        c.1.0: Package does not satisfy constraints of local package x
  [1]

