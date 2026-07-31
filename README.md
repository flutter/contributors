<a href="https://flutter.dev/">
  <h1 align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://docs.flutter.dev/logo_dark.png">
      <img alt="Flutter" src="https://docs.flutter.dev/logo.png">
    </picture>
  </h1>
</a>

# Flutter contributors

This repository tracks contributor ladder roles, project governance, and the contributor roster for the Flutter project.

## Current state

The automated pipeline in this repository collects a rolling 12-month record of contributions across all public repositories in the `flutter` GitHub organization.

- Merged pull requests, code reviews on merged PRs, and opened issues are tracked daily.
- Weekly snapshots are stored in `data/activity/`, with rolling 12-month totals aggregated in `data/activity_summary.json`.
- A scheduled workflow (`.github/workflows/sync_activity.yml`) runs daily at 02:17 UTC to sync activity and prune snapshots older than 52 weeks.
- See [docs/DATA_PIPELINE.md](docs/DATA_PIPELINE.md) for details on query design, rate limits, and bot filtering.

## What is coming

The repository will expand to host the complete contributor governance model and roster upon launch:

- Contributor ladder tiers (Contributor, Reviewer, Committer, Maintainer, and Dasher Emeritus).
- Public contributor roster and GitHub team synchronization.
- Code review workflows, landing requirements, and test exemption policies.
- Quarterly review audits, 30-day grace period tracking, and nomination workflows.
- Archival of repository `AUTHORS` files and contributor migration guides.