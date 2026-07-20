Show a defect in the dune package solver. opam_solver adds dune to the pinned
packages. It also adds the restriction "= <version>" to the dune role. As a
result the solver cannot select a dune version that an opam repository
publishes. opam solves the same repository and installs that version.

The defect is not specific to an or-dependency. A plain dependency on a dune
version from the repository fails in the same way. An or-formula only removes
the alternative arm that can make the solve succeed. This test keeps the
or-formula case, because that is the shape of a real opam repository.

The OxCaml opam repository holds the guard packages oxcaml-dune.guard and
oxcaml-dune-patches.enabled. dune cannot lock an OxCaml project, and the user
must satisfy the or-dependency with a dummy local pin. See ocaml/dune#15509.

  $ mkrepo
  $ add_mock_repo_if_needed

The dune version in use changes between builds. Mask it, but keep the fork
version that the repository publishes:

  $ mask_dune_version() {
  >   dune_cmd subst 'requested = 3\.[0-9.]+' 'requested = 3.XX' \
  >   | dune_cmd subst 'dune\.3\.[0-9.]+:' 'dune.3.XX:'
  > }

The repository publishes a fork of dune:

  $ mkpkg dune 3.22.2+fork

First, test a plain dependency on that fork. No or-formula is present. The
solve fails, because the solver keeps only the dune version in use:

  $ mkpkg needs-fork <<EOF
  > depends: [ "dune" {= "3.22.2+fork"} ]
  > EOF
  $ solve needs-fork 2>&1 | mask_dune_version
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: needs-fork.0.0.1 x.dev
  - dune -> (problem)
      User requested = 3.XX
      needs-fork 0.0.1 requires = 3.22.2+fork
      Rejected candidates:
        dune.3.XX: Incompatible with restriction: = 3.22.2+fork
  [1]


The OxCaml repository has a pair of guard packages. oxcaml-dune conflicts
with dune. oxcaml-dune-patches needs the repository's dune fork:

  $ mkpkg oxcaml-dune guard <<EOF
  > conflicts: [ "oxcaml-dune-patches" "dune" ]
  > EOF
  $ mkpkg oxcaml-dune-patches enabled <<EOF
  > conflicts: "oxcaml-dune"
  > depends: [ "dune" {= "3.22.2+fork"} ]
  > EOF

A library that has the or-dependency:

  $ mkpkg guarded-lib <<EOF
  > depends: [ ("oxcaml-dune" | "oxcaml-dune-patches") ]
  > EOF

State the precondition. The or-formula alone solves. The solver takes the
oxcaml-dune arm. That arm conflicts with dune, but no other package in this
solve needs dune. The failure needs a second package that depends on dune:

  $ solve guarded-lib
  Solution for dune.lock:
  - guarded-lib.0.0.1
  - oxcaml-dune.guard

Every package that dune builds depends on dune. Add such a package:

  $ mkpkg lib <<EOF
  > depends: [ "dune" ]
  > EOF

Now both arms are unusable. The oxcaml-dune-patches arm needs the fork, and
the solver cannot select the fork. The oxcaml-dune arm conflicts with dune,
and lib needs dune. opam solves the same repository: opam takes the
oxcaml-dune-patches arm and installs dune.3.22.2+fork.

The message below names the dune role as the problem. It does not report that
the solver removed the repository's dune.3.22.2+fork. That removal is the
real cause:

  $ solve guarded-lib lib 2>&1 | mask_dune_version
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: guarded-lib.0.0.1 lib.0.0.1 oxcaml-dune.guard x.dev
                       oxcaml-dune
  - dune -> (problem)
      User requested = 3.XX
      oxcaml-dune guard requires conflict with all versions
      Rejected candidates:
        dune.3.XX: Incompatible with restriction: conflict with all versions
  [1]


The "Selected candidates" line also holds the name oxcaml-dune with no
version. Do not read that as part of this defect. A virtual implementation
prints its roles with no version, and a failure with no relation to dune
prints the same form. This behavior of the output format exists already.

Control A. Build the same shape, but replace the name dune with the name
notdune. Every other part stays the same: the same or-formula, the same
conflict, the same fork version, and the same second package. The solve
succeeds. As a result the name dune is the only cause of the failure above:

  $ mkpkg notdune 3.22.2+fork
  $ mkpkg oxcaml-notdune guard <<EOF
  > conflicts: [ "oxcaml-notdune-patches" "notdune" ]
  > EOF
  $ mkpkg oxcaml-notdune-patches enabled <<EOF
  > conflicts: "oxcaml-notdune"
  > depends: [ "notdune" {= "3.22.2+fork"} ]
  > EOF
  $ mkpkg guarded-lib-notdune <<EOF
  > depends: [ ("oxcaml-notdune" | "oxcaml-notdune-patches") ]
  > EOF
  $ mkpkg lib-notdune <<EOF
  > depends: [ "notdune" ]
  > EOF
  $ solve guarded-lib-notdune lib-notdune
  Solution for dune.lock:
  - guarded-lib-notdune.0.0.1
  - lib-notdune.0.0.1
  - notdune.3.22.2+fork
  - oxcaml-notdune-patches.enabled

Control B. Swap the order of the two arms. The solve still fails, but the
solver now reports the other arm first. The report names the fork version
that oxcaml-dune-patches needs. It lists only the dune version in use as a
candidate.

dune.3.22.2+fork never appears as a candidate. The repository publishes that
version, but the solver removed it. This control matters, because the failure
block above looks the same as a failure against a repository that holds no
such version:

  $ mkpkg swapped-lib <<EOF
  > depends: [ ("oxcaml-dune-patches" | "oxcaml-dune") ]
  > EOF
  $ solve swapped-lib lib 2>&1 | mask_dune_version
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  Couldn't solve the package dependency formula.
  Selected candidates: lib.0.0.1 oxcaml-dune-patches.enabled swapped-lib.0.0.1
                       x.dev oxcaml-dune-patches
  - dune -> (problem)
      User requested = 3.XX
      oxcaml-dune-patches enabled requires = 3.22.2+fork
      Rejected candidates:
        dune.3.XX: Incompatible with restriction: = 3.22.2+fork
  [1]


Control C. dune handles an unusable arm of an or-dependency correctly in
general. This shape copies the compiler disjunction of the ocaml meta-package.
fake-base-compiler shares a conflict-class with fake-variants, and the
project needs fake-variants directly. fake-system does not exist. The solver
still takes the fake-variants arm.

This control differs from the case that fails in more than one way. As a
result it does not isolate the name dune. Control A above does that:

  $ mkpkg fake-base-compiler <<EOF
  > conflict-class: "fake-compiler"
  > EOF
  $ mkpkg fake-variants <<EOF
  > conflict-class: "fake-compiler"
  > EOF
  $ mkpkg fake-ocaml <<EOF
  > depends: [ "fake-base-compiler" | "fake-variants" | "fake-system" ]
  > EOF
  $ solve fake-ocaml fake-variants
  Solution for dune.lock:
  - fake-ocaml.0.0.1
  - fake-variants.0.0.1

Apply the workaround from ocaml/dune#15509. Give the unusable arm a dummy
candidate with a local pin. The pin replaces the guard package, because a pin
replaces the repository candidates. The pin removes the conflict with dune,
and the solve succeeds. This shows that the or-dependency above was the only
cause of the failure:

  $ mkdir _oxcaml-dune
  $ cat > _oxcaml-dune/dune-project <<EOF
  > (lang dune 3.20)
  > (package (name oxcaml-dune) (allow_empty))
  > EOF
  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (repository
  >  (name mock)
  >  (url "file://$PWD/mock-opam-repository"))
  > (pin
  >  (name oxcaml-dune)
  >  (url "file://$PWD/_oxcaml-dune")
  >  (package (name oxcaml-dune) (version guard)))
  > (lock_dir
  >  (repositories mock)
  >  (pins oxcaml-dune))
  > EOF
  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name x) (allow_empty) (depends guarded-lib lib))
  > EOF
  $ dune_pkg_lock_normalized
  Solution for dune.lock:
  - guarded-lib.0.0.1
  - lib.0.0.1
  - oxcaml-dune.guard
