# Changelog

All notable changes to FStudy are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-23

### Added

- Invite-only username accounts with optional display names.
- Timetable, assignments, custom plans, campus map, student discovery, forum, project recruitment, and notifications.
- Admin console for invites, users, content moderation, reports, tags, and audit logs.
- About page and Chinese project documentation.
- GitHub Actions Android release pipeline with per-ABI and universal APKs.

### Changed

- Production, staging, API, admin, and student Web endpoints now use `usfese.cc` custom domains.
- Android release builds require the project signing key; debug signing is no longer used for release builds.

### Security

- Android signing material is stored in GitHub Actions Secrets and is never committed.
