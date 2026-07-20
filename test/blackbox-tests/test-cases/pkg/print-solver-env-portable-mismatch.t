'dune pkg print-solver-env' prints the default environment merged with the
platform variables that dune polls from the host. The polled variables are
arch, os, os-distribution, os-family, os-version and sys-ocaml-version. dune
uses portable lock directories by default. In that mode the solver drops the
polled values of all platform-specific variables and solves once for each entry
in the platform list. print-solver-env does not report that per-platform
environment.

This test came from work that drove the OxCaml opam repository through dune
package management. The DUNE_CONFIG__ variables that helpers.sh exports pin the
"polled" values. The output is deterministic as a result.

  $ mkrepo
  $ add_mock_repo_if_needed

The next package is available only when the system OCaml compiler version is a
known value. The version in the filter is exactly the value of
DUNE_CONFIG__SYS_OCAML_VERSION that the test harness exports.

  $ mkpkg foo <<EOF
  > available: sys-ocaml-version = "5.4.0+fake"
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name x) (depends foo))
  > EOF

The reported solver environment holds the polled variables. It includes
sys-ocaml-version = 5.4.0+fake, and that value satisfies the 'available:'
filter of foo:

  $ dune pkg print-solver-env
  Solver environment for lock directory dune.lock:
  - arch = x86_64
  - opam-version = 2.2.0
  - os = linux
  - os-distribution = ubuntu
  - os-family = debian
  - os-version = 24.11
  - post = true
  - sys-ocaml-version = 5.4.0+fake
  - with-dev-setup = false
  - with-doc = false

The solve fails. The portable solver never gets the polled value of
sys-ocaml-version.

  $ dune pkg lock
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  The dependency solver failed to find a solution for the following platforms:
  - arch = x86_64; os = linux
  - arch = arm64; os = linux
  - arch = x86_64; os = macos
  - arch = arm64; os = macos
  ...with this error:
  Couldn't solve the package dependency formula.
  Selected candidates: x.dev
  - foo -> (problem)
      No usable implementations:
        foo.0.0.1: Availability condition not satisfied
  [1]


The platform list in the error message above is not the environment that dune
gives to the solver. lock.ml prints the keys of the solve_for_platforms
entries. The per-platform environment holds more variables than the two that
each line shows.

CONTROL A. The per-platform environment keeps every variable that is not
platform-specific. This package is available only when opam-version, with-doc
and post all hold the values that print-solver-env reports. The solve succeeds.
As a result, the portable solver does not reduce the environment to arch and
os:

  $ mkpkg non-platform-vars-kept <<EOF
  > available: opam-version = "2.2.0" & with-doc = false & post
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name x) (depends non-platform-vars-kept))
  > EOF

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - non-platform-vars-kept.0.0.1
  $ rm -rf dune.lock

CONTROL B. dune does not simply delete the platform-specific variables. lock.ml
calls Solver_env.unset_multi on Package_variable_name.platform_specific to
remove the polled values. opam_solver then calls
Solver_env.add_sentinel_values_for_unset_platform_vars. That function puts a
sentinel string in each variable that stays unset. The sentinel for
sys-ocaml-version is the literal text __SYS_OCAML_VERSION.

The next package is available only when sys-ocaml-version equals that sentinel.
The solve succeeds. As a result, the variable holds the sentinel value:

  $ mkpkg sentinel-probe <<EOF
  > available: sys-ocaml-version = "__SYS_OCAML_VERSION"
  > EOF

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name x) (depends sentinel-probe))
  > EOF

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - sentinel-probe.0.0.1
  $ rm -rf dune.lock

The solver strips the polled platform values on purpose, because a portable
lock directory must not hold host-specific values. CONTROL C below shows the
supported workaround. The defect is narrow: the command misleads the user at
the exact moment that the user debugs a solve.

  $ cat > dune-project <<EOF
  > (lang dune 3.20)
  > (package (name x) (depends foo))
  > EOF

The same project locks without an error when dune does not use portable lock
directories:

  $ DUNE_CONFIG__PORTABLE_LOCK_DIR=disabled dune pkg lock
  Solution for dune.lock:
  - foo.0.0.1
  $ rm -rf dune.lock

CONTROL D. print-solver-env prints the same text when dune does not use
portable lock directories. The command output does not name the solver that dune
runs:

  $ DUNE_CONFIG__PORTABLE_LOCK_DIR=disabled dune pkg print-solver-env
  Solver environment for lock directory dune.lock:
  - arch = x86_64
  - opam-version = 2.2.0
  - os = linux
  - os-distribution = ubuntu
  - os-family = debian
  - os-version = 24.11
  - post = true
  - sys-ocaml-version = 5.4.0+fake
  - with-dev-setup = false
  - with-doc = false

A list of the current platform in (solve_for_platforms ...) does not restore
the polled variables. The per-platform environment keeps the sentinel value
even when the requested platform is exactly the platform that dune polled from
the simulated host.

  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (lock_dir
  >  (repositories mock)
  >  (solve_for_platforms
  >   ((arch x86_64)
  >    (os linux))))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

print-solver-env does not change. It still reports that sys-ocaml-version is
set to the polled value:

  $ dune pkg print-solver-env
  Solver environment for lock directory dune.lock:
  - arch = x86_64
  - opam-version = 2.2.0
  - os = linux
  - os-distribution = ubuntu
  - os-family = debian
  - os-version = 24.11
  - post = true
  - sys-ocaml-version = 5.4.0+fake
  - with-dev-setup = false
  - with-doc = false

The solve still fails:

  $ dune pkg lock
  Error:
  Unable to solve dependencies while generating lock directory: dune.lock
  
  The dependency solver failed to find a solution for the following platforms:
  - arch = x86_64; os = linux
  ...with this error:
  Couldn't solve the package dependency formula.
  Selected candidates: x.dev
  - foo -> (problem)
      No usable implementations:
        foo.0.0.1: Availability condition not satisfied
  [1]


CONTROL C. This is the supported workaround, and it is also the strongest
evidence for the defect. The (solver_env ...) field of the lock_dir stanza sets
sys-ocaml-version for every platform. dune adds this field to each
solve_for_platforms entry after it strips the polled values:

  $ cat > dune-workspace <<EOF
  > (lang dune 3.20)
  > (lock_dir
  >  (repositories mock)
  >  (solver_env
  >   (sys-ocaml-version 5.4.0+fake)))
  > (repository
  >  (name mock)
  >  (url "file://$(pwd)/mock-opam-repository"))
  > EOF

The same project now locks without an error:

  $ dune pkg lock
  Solution for dune.lock
  
  Dependencies common to all supported platforms:
  - foo.0.0.1
  $ rm -rf dune.lock

print-solver-env prints exactly the same text as it printed for the
configuration that failed. The output cannot tell the user why one
configuration locks and the other configuration fails:

  $ dune pkg print-solver-env
  Solver environment for lock directory dune.lock:
  - arch = x86_64
  - opam-version = 2.2.0
  - os = linux
  - os-distribution = ubuntu
  - os-family = debian
  - os-version = 24.11
  - post = true
  - sys-ocaml-version = 5.4.0+fake
  - with-dev-setup = false
  - with-doc = false

The correct behavior is one of two things. 'dune pkg print-solver-env' must
print the per-platform environments that dune gives to the solver when dune
uses portable lock directories. Or the command must state that the portable
solver replaces the polled platform variables with sentinel values.
