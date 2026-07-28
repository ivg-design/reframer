# Archived runner handoff

> Historical summary only. This file is not a current setup guide or product
> contract.

The original handoff described a machine-specific SSH runner used during an
early Reframer experiment. Its host address, account name, absolute paths, and
copy-paste commands were removed from the public tree because they are not
portable and exposed private workstation details.

The useful historical conclusion was that AppKit UI automation needs an active,
interactive macOS desktop. Current automation must use the repository's
[`ui_test_preflight.sh`](../../../scripts/ui_test_preflight.sh) and the evidence
rules in [Feature Verification](../../FEATURE_TESTS.md). It must not alter TCC
databases, restart privacy services, weaken screen-lock policy, strip
provenance, or re-sign test products.

The original report remains available in Git history when historical forensics
are necessary.
