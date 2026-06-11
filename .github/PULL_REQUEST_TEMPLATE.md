<!--
Thanks for the PR. Keep this short — three sentences each is plenty.
For trivial changes (typos, dependency bumps, copy edits) you can just
delete the template entirely and write a one-liner.
-->

## What

<!-- One sentence: what the user / operator / contributor sees that's different. -->

## Why

<!-- One or two sentences: the bug, the missing capability, the constraint
     that motivated this. Link to the issue if there is one (Fixes #N). -->

## How

<!-- Brief: the approach. Call out anything non-obvious — surprising file
     touched, a tradeoff you considered, a follow-up you're deferring. -->

## Test plan

<!-- Concrete commands or steps. Document anything a human would do to verify
     (e.g. manual CLI run, spec fidelity check). -->

- [ ] `bash -n cli/bin/opensop && bash cli/test/test.sh` passes (CLI changes)
- [ ] Spec-fidelity check: change is consistent with `SPEC.md` semantics (or `SPEC.md` updated in this PR)
- [ ] Public-repo hygiene: no secrets, no PII, no internal identifiers in the diff
- [ ] Updated `cli/CHANGELOG.md` if the change is user-visible (or n/a)
