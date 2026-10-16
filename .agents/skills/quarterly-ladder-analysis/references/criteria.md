# Contributor Ladder Metric Criteria Reference

## 12-Month Rolling Criteria Rubric

| Role | GitHub Role | Criteria (Rolling 12 Months) |
| :--- | :--- | :--- |
| **Contributor** | `Read` (External) | Any material contribution (code, docs, issue triage, QA). |
| **Reviewer** | `Triage` (Org Member) | $\ge 10$ qualifying contributions (merged PRs, valid issues, reviews on merged PRs, reproducible issue triage). |
| **Committer** | `Write` (Org Member) | $\ge 30$ qualifying contributions and $\ge 10$ merged PRs, demonstrating depth, code quality, and technical judgment. |
| **Maintainer** | `Write` + Org Mod (Org Member) | All members of `@flutter/googlers` and `@flutter/partners` (there are no Maintainers outside of Googlers and Partners). |
| **Dasher Emeritus** | `Read` (External Alumni) | Inactive community role-holder ($< 10$ contributions in past 12 months after 30-day grace period). Removed from the GitHub org and listed in `EMERITUS.md`. |

## Special Policies

Contributors who have previously been banned for Code of Conduct violations remain welcome to contribute as external Contributors after a temporary ban expires, but are not eligible for ladder membership (`Reviewer`, `Committer`, `Maintainer`). When running `tool/quarterly_audit.dart --prepare` locally, the person running the audit checks the nominated usernames against the internal Code of Conduct / ban history list and excludes any ineligible candidates before any report or roster files are generated, ensuring no one is singled out.

Community members who joined `flutter-hackers` within the 12 months prior to ladder launch receive a one-time 12-month Reviewer transition grace period (`grace_until` in `data/contributors.yaml`). Once that initial year expires, no further recent-joiner carve-outs apply.

Googlers and Partners are automatically classified as Maintainers (while their 12-month contribution history is still recorded in `data/activity_summary.json`), and contributions that cannot be quantified automatically—such as issue triage, reproduction verifications, [RFC](https://github.com/flutter/rfc) feedback, design docs, and mentoring—count toward Reviewer and Committer qualifications when shared during the 30-day review period.
