---
name: quarterly-ladder-analysis
description: Instructions and operational workflow for conducting the Flutter Contributor Ladder quarterly audits (Community Audit and Partner Team Verification).
---

# Quarterly Contributor Ladder Analysis Skill

This skill guides you through executing Flutter's quarterly contributor reviews across the 30+ day review cycle.

## Step 0: Determine Current Phase in the 30+ Day Process

Before running any mutating commands, **first ask the user (if not already clear from their request) where in the 30+ day quarterly review process we are** (you can also check open `quarterly-review` / `quarterly-review-checklist` issues and open PRs via `gh issue list` and `gh pr list`):

1. **Phase 1 — Kickoff & Opening the PR / Review Issues (Day 1)**: Starting the quarterly review after the automated checklist issue is filed.
2. **Phase 2 — Mid-Review Check-In (Days 1–30)**: Auditing responses on the open review issue, checking an individual contributor (`tool/check_user.dart`), or tracking partner confirmations during the 30-day window.
3. **Phase 3 — Finalization & Merging (Day 30+)**: Incorporating 30-day responses into the open quarterly review PR, landing the PR, syncing GitHub/Discord permissions, and closing the issues.

Proceed to the matching phase below.

---

## Phase 1: Kickoff, Ban-History Vetting, Single PR & Review Issues (Day 1)

### 1.1 Preview Nominated Candidates & Ask User for Ban-History Check

1. Ensure you are on a fresh branch off the latest `main` (which is updated daily by `.github/workflows/sync_activity.yml`):

   ```bash
   git checkout -b YYYY-QX-quarterly-review
   ```

2. Run `--prepare` in dry-run, non-interactive mode first to see the nominated candidates without writing any files (`tool/quarterly_audit.dart` automatically queries live `flutter` GitHub organization and team membership so every current org member is evaluated):

   ```bash
   dart run tool/quarterly_audit.dart --prepare --dry-run --no-prompt
   ```

3. **Present the nominated usernames** (promotions to Committer, returning Dasher Emeriti, and prospective external new joiners) to the user and **ask them to check those usernames against the internal Code of Conduct / ban history list**.
   - Contributors who were previously banned for Code of Conduct violations remain welcome to contribute as external Contributors after a temporary ban expires, but are not eligible for ladder membership.
   - Wait for the user to confirm whether any usernames should be excluded before generating files on disk so no one is singled out in reports or commits.

### 1.2 Generate Reports & Update Roster for the Single PR

Once the user confirms any exclusions (or confirms none are needed), run `--prepare`:

```bash
dart run tool/quarterly_audit.dart --prepare --no-prompt --exclude user1,user2
```

*(Omit `--exclude` if no candidates are excluded.)*

This single command:

- Writes `reports/YYYY-QX-community-ladder-audit.md` and `reports/YYYY-QX-partner-verification-audit.md` (with excluded users completely omitted).
- Updates `data/contributors.yaml`, `ROSTER.md`, and `EMERITUS.md`.

### 1.3 Open the Single Quarterly Review PR

Commit the generated reports and proposed roster updates into **1 PR**:

```bash
git add reports/ data/contributors.yaml ROSTER.md EMERITUS.md
git commit -m "chore: QX YYYY quarterly contributor ladder review"
```

This PR stays open throughout the 30-day community review period and does not land until Phase 3 (Day 30+).

### 1.4 Draft & Open the Public Review Issues

Use the tool to preview or open the two public tracking issues from the vetted reports to start the 30-day review period:

```bash
# Preview drafted issues and gh CLI commands:
dart run tool/quarterly_audit.dart --draft-issues --pr <PR_URL>

# Or open both issues directly on GitHub via gh CLI:
dart run tool/quarterly_audit.dart --open-issues --pr <PR_URL>
```

---

## Phase 2: Manage the 30-Day Grace Period (Days 1–30)

- Inspect responses on the Community Audit issue (`gh issue view <ISSUE_NUMBER> --comments`):
  - Collect Discord usernames from newly invited contributors (`user=discord_handle`).
  - Summarize reported qualitative contributions that cannot be quantified automatically (issue triage comments, reproduction verification, [RFC](https://github.com/flutter/rfc) reviews, mentoring) for the user to review.
  - To inspect a specific contributor's 12-month metrics and current roster status:

    ```bash
    dart run tool/check_user.dart <username>
    ```

- Remind the user to reach out to partner teams to confirm active status for `@flutter/partners` members.
- *(During the 30-day window, `.github/workflows/check_grace_period.yml` runs once a week to post a weekly countdown update on the open review issues, and pings the assignee once 30 days have elapsed.)*

---

## Phase 3: Update the Open PR, Land It & Provision Access (Day 30+)

1. Gather 30-day adjustments:
   - Read all comments on the open Community Audit issue (`gh issue view <ISSUE_NUMBER> --comments`) and confirm with the user:
     - `--retain`: Contributors in the 30-day grace period who shared verified qualitative contributions.
     - `--exclude`: Any previously excluded usernames plus any invited contributors who declined.
     - `--discord`: `github_user=discord_handle` mappings shared by accepted new joiners, returning Emeriti, and promoted members.
2. Update the open PR branch:
   On the open `YYYY-QX-quarterly-review` PR branch, run `--finalize`:

   ```bash
   dart run tool/quarterly_audit.dart --finalize \
     --retain user1,user2 \
     --exclude excluded_or_declined_user \
     --discord user=discord_handle
   ```

3. Validate schema and roster sync:

   ```bash
   dart run tool/validate_roster.dart
   dart run tool/generate_roster.dart --check
   ```

4. Commit, push & land the PR:
   Commit the updated `data/contributors.yaml`, `ROSTER.md`, and `EMERITUS.md` to the PR branch and merge the PR.
5. Post-merge provisioning checklist:
   - Update GitHub organization teams (`@flutter/reviewers`, `@flutter/committers`, and `@flutter/maintainers` as child teams of `@flutter/flutter-hackers`, along with `@flutter/partners` child teams) to match `ROSTER.md` (`@flutter/collaborators` is automatically managed by internal tooling and should not be modified manually).
   - Remove members who transitioned to Dasher Emeritus from the `flutter` GitHub organization.
   - Grant the Discord team member role to newly added ladder members using their collected Discord handles.
   - Close the public review issues and the quarterly checklist issue.
