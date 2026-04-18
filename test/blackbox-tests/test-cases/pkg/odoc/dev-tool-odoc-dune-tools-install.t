Test that `dune tools install odoc` lets `dune build @doc` pick up the locked
odoc binary without requiring DUNE_CONFIG__LOCK_DEV_TOOL=enabled, mirroring
the behaviour of `dune tools install ocamlformat` + `dune fmt`.

  $ mkrepo
  $ make_mock_odoc_package
  $ mk_ocaml 5.2.0
  $ setup_odoc_workspace

  $ cat > dune-project <<EOF
  > (lang dune 3.16)
  > (package
  >  (name foo)
  >  (depends
  >    (ocaml (= 5.2.0))))
  > EOF

  $ cat > dune <<EOF
  > (library
  >  (public_name foo))
  > EOF

  $ cat > foo.ml <<EOF
  > let hello () = print_endline "hi"
  > EOF

  $ cat > foo.mli <<EOF
  > (** A greeting. *)
  > val hello : unit -> unit
  > EOF

  $ dune build

Install odoc via `dune tools install`, which populates the dev-tool lockdir
at _build/.dev-tools.locks/odoc:

  $ dune tools install odoc
  Solution for _build/.dev-tools.locks/odoc:
  - ocaml-base-compiler.5.2.0
  - ocaml-compiler.5.2.0
  - odoc.0.0.1

With DUNE_CONFIG__LOCK_DEV_TOOL=enabled, `dune build @doc` consults the
lockdir and invokes the mock odoc (which prints "hello from fake odoc"):

  $ DUNE_CONFIG__LOCK_DEV_TOOL=enabled dune build @doc
  hello from fake odoc
  hello from fake odoc
  File "_doc/_html/_unknown_", line 1, characters 0-0:
  Error: Rule failed to produce directory "_doc/_html/odoc.support"
  File "_doc/_odoc/pkg/foo/_unknown_", line 1, characters 0-0:
  Error: Rule failed to generate the following targets:
  - _doc/_odoc/pkg/foo/page-index.odoc
  [1]

Without the feature flag, `dune build @doc` should also pick up the locked
odoc (as `dune fmt` does with ocamlformat):

  $ dune build @doc
  hello from fake odoc
  hello from fake odoc
  File "_doc/_html/_unknown_", line 1, characters 0-0:
  Error: Rule failed to produce directory "_doc/_html/odoc.support"
  File "_doc/_odoc/pkg/foo/_unknown_", line 1, characters 0-0:
  Error: Rule failed to generate the following targets:
  - _doc/_odoc/pkg/foo/page-index.odoc
  [1]

After removing the lockdir, `dune build @doc` falls back to a PATH lookup
and fails (no odoc is installed in the test environment):

  $ rm -r "${dev_tool_lock_dir}"
  $ dune build @doc
  File "_doc/_html/_unknown_", line 1, characters 0-0:
  Error: Program odoc not found in the tree or in PATH
   (context: default)
  Hint: opam install odoc
  File "_doc/_odoc/pkg/foo/_unknown_", line 1, characters 0-0:
  Error: Program odoc not found in the tree or in PATH
   (context: default)
  Hint: opam install odoc
  [1]
