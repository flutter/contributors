# Code Review Workflow

This document describes code review policies, approval requirements, and pull request landing procedures for Flutter repositories. For detailed guidance on preparing pull requests and conducting code reviews, see [Tree hygiene (Getting a code review)](https://github.com/flutter/flutter/blob/main/docs/contributing/Tree-hygiene.md#getting-a-code-review) and the [Flutter style guide](https://github.com/flutter/flutter/blob/main/docs/contributing/Style-guide-for-Flutter-repo.md) in `flutter/flutter`.

## Approval requirements

The number and tier of approvals required for a pull request depend on the author's ladder role:

| Author role | Approvals required | Approval eligibility | Notes |
| :--- | :--- | :--- | :--- |
| **Contributor** | 2 approvals | At least 1 approval from a Committer (or Maintainer); 2nd approval may be from a Reviewer (or higher). | Reviewers provide first-pass review. A Committer provides the second approval and initiates the merge. |
| **Reviewer** | 2 approvals | At least 1 approval from a Committer (or Maintainer); 2nd approval may be from a Reviewer (or higher). | Encourages peer review between Reviewers while ensuring Committer review. |
| **Dasher Emeritus** | 2 approvals | At least 1 approval from a Committer (or Maintainer); 2nd approval may be from a Reviewer (or higher). | Follows standard community review requirements. |
| **Committer** | 1 approval | 1 approval from a Reviewer (or higher). | Committers may land PRs with one approval. |
| **Maintainer** | 1 approval | 1 approval from a Reviewer (or higher). | Maintainers may land PRs with one approval. |

## Review stages

### First-pass review (Reviewers)
When a pull request is submitted by a Contributor or Reviewer, a Reviewer conducts the initial review to check code style and Flutter conventions (`analysis_options.yaml`, naming, formatting), public API documentation coverage, test coverage for new functionality or bug fixes, and reproduction checks when applicable. Once satisfied, the Reviewer approves the PR on GitHub to signal that it is ready for Committer review.

### Final sign-off and landing (Committers and Maintainers)
A Committer or Maintainer then reviews the change for architecture, performance, platform fidelity, backward compatibility, breaking change policies, and automated test coverage (or adherence to the [Test Exemption Process RFC](https://github.com/flutter/rfc/blob/main/rfc/010.0001-test-exemption-process.md)). When ready, the Committer approves the PR and adds it to the merge queue (or applies the `autosubmit` label).

## Early feedback on large changes

For large, architectural, or multi-package changes, open a draft PR or submit a proposal in [`flutter/rfc`](https://github.com/flutter/rfc) before writing extensive code. Tag relevant Maintainers or Committers in the description (or discuss the proposal in the appropriate Discord channel) and add the `status: conceptual review` label if available.

## Review checklist

Before approving or requesting final sign-off, verify the [Tree hygiene review checklist](https://github.com/flutter/flutter/blob/main/docs/contributing/Tree-hygiene.md#how-to-review-code):
- [ ] Every bug fix has a regression test, and every new feature has automated tests (see the [Test Exemption Process RFC](https://github.com/flutter/rfc/blob/main/rfc/010.0001-test-exemption-process.md) when an exemption is needed).
- [ ] Public members, parameters, and return types have complete doc comments.
- [ ] All CI checks pass cleanly.
- [ ] Any breaking change has completed the [Flutter breaking change process](https://github.com/flutter/flutter/blob/main/docs/contributing/Tree-hygiene.md#handling-breaking-changes).
- [ ] Changes to cross-platform widgets or components follow target platform conventions.

## Merging

Only members with GitHub Write access (Committers and Maintainers) have permissions to merge pull requests or submit them to the merge queue. Once all required approvals and CI checks pass, a Committer or Maintainer lands the change.
