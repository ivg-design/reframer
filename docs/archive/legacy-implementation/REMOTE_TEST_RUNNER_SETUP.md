# Archived remote-runner experiment

> Historical summary only. Do not use this file to configure a runner.

An early implementation explored driving Reframer tests over SSH from a
persistent Mac. The original document included machine-specific paths and
unsafe operational suggestions such as creating an administrative runner,
disabling normal screen-lock behavior, and broad artifact deletion. Those
instructions have been removed from the public tree.

The retained lessons are:

- UI automation requires a logged-in, unlocked desktop owned by the runner
  account.
- A self-hosted runner should be isolated, least-privileged, disposable where
  practical, and free of personal data and release credentials.
- Xcode automation must be approved through normal macOS controls.
- Test scripts must not modify privacy databases, restart privacy services,
  remove quarantine metadata, or re-sign test products.
- Artifact cleanup must target a unique run directory.

Use the current [Feature Verification](../../FEATURE_TESTS.md),
[`ui_test_preflight.sh`](../../../scripts/ui_test_preflight.sh), and GitHub
workflow as the only current authorities. The original experiment remains in
Git history for historical forensics.
