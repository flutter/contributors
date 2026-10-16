# Quarterly Audit Reports Archive

This directory stores the permanent, version-controlled record of all quarterly contributor audits conducted for the Flutter Contributor Ladder.

## Structure & File Naming
For each calendar quarter, two official audit reports (`YYYY-QX-community-ladder-audit.md` for the community ladder review and `YYYY-QX-partner-verification-audit.md` for verifying active `@flutter/partners` members) are generated locally via `tool/quarterly_audit.dart --prepare`, checked in alongside the proposed roster updates in a single PR, and published as tracking issues.

## Generating Reports
To prepare and save the current quarter's reports (and update the roster for the quarterly review PR):
```bash
dart run tool/quarterly_audit.dart --prepare
```
