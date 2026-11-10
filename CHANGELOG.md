# Changelog

All notable changes to FStudy are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.2] - 2026-11-10

### Fixed

- Android Release APK 显式启用 v2 + v3 签名，发布流程校验两种签名方案，改善新系统上的安装兼容性。
- README 补充“packageInfo is null”安装排查说明：校验下载完整性、选择正确 ABI、先卸载旧签名版本。

## [1.0.1] - 2026-11-05

### Added

- 客户端本地缓存：启动、课表和课程等页面先显示上次数据，再在后台与云端同步并自动更新。

### Changed

- 登录会话恢复改为先使用本地快照进入应用，再在后台校验令牌；令牌失效时自动退出。

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
