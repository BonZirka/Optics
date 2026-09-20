# 01 — consumer publishing: tests as dependency

## Symptom
- cjpm auto-discovers `src/tests` as sub-package `lucida.tests` and compiles
  it for every consumer; under some flag sets it fails with
  `N errors generated, 0 error printed`.

## Fix
1. Verify whether `cjpm.toml`'s `package-configuration` (or moving the suite
   to a workspace member outside `src/`) stops the consumer from compiling
   `lucida.tests`. The consumer-facing compile commands are visible via
   `cjpm build --verbose`; the failing unit prints
   `Compiling package lucida.tests ... 2 errors generated, 0 error printed`.

## Verification
`rm -rf target` in a fresh consumer (see
~/projects/showcase-optics/cjpm.toml for the reference layout), then
`cjpm run` — must succeed with no `Compiling package lucida.tests` line in
the verbose output.

## Already resolved

The LTO half of this plan is gone, and the new arrangement is strictly
better than what it replaced. Consumers used to have to pass
`--lto=thin` themselves, because `compile-option` is per-package and so
applied to lucida even when lucida was built as a dependency — the archives
came out as LLVM bitcode and an unflagged link died with
`liblucida.stdlib.a: file not recognized`. That was the hidden
requirement: a flag with no natural place to live, whose absence broke the
link.

Moving LTO to `[profile.build.lto]` fixes it in both directions, and the
asymmetry is what makes it work:

- A consumer who sets nothing gets native archives and a link that just
  works. The old `--lto=thin` is no longer needed by anyone.
- A consumer who wants LTO adds `[profile.build.lto] level = "thin"` to
  their own `cjpm.toml`, and it applies to the whole build including
  lucida's archives. `buildConfig.isLto` is read from the top-level
  manifest and then stamped onto every `CompileTask`
  (`cjpm/src/implement/lto_combine_mode.cj`), where `fullName` gates only
  `isProjectCombined` and not `isLto`.

So the opt-in is explicit and uses the same mechanism we use for our own
builds, and cjpm keeps the link step consistent with it. Our own
top-level builds keep thin LTO the same way.
