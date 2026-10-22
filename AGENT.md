# FStudy Agent Guide

This file is the working agreement for coding agents in this repository. Read it before making changes. Keep changes within the user's requested scope and preserve uncommitted user work.

## Product

FStudy is a cross-platform coursework and light-social application for BUPT students.

Current priority platforms:

- Flutter Web/PWA for desktop browsers
- Flutter Android
- iOS project structure is retained for future support, but iOS is not currently built

### Current iteration constraint

Web is the active rapid-iteration target. Until the user explicitly re-enables Android work:

- Do not run Android APK/AAB builds.
- Do not spend iteration time on Android-only notification setup or device testing.
- Keep shared Flutter code portable to Android, but validate product flows on Web first.
- Use `flutter analyze`, `flutter test`, and Web builds as the client verification gate.
- Continue storing reminder settings, but defer operating-system notification delivery.

The first usable release focuses on:

1. Invite-only registration and a unique username
2. Manual timetable entry, including odd/even weeks
3. Assignments and completion state
4. Schedule visibility, custom plans, reminders, and shared-free-time invitations
5. Friends and recommendations by department, interests, and fields
6. Forum and project sharing

Do not introduce private messaging in the first release. Do not scrape timetables automatically. Desktop remains a PWA; do not add Electron unless explicitly requested.

## Implementation Order

Follow this order unless the user explicitly changes it:

1. Stabilize authentication and session restoration
2. Complete manual course and weekly timetable workflows
3. Complete assignment workflows and course association
4. Introduce shared responsive navigation for Web and Android
5. Add custom plans and persist reminder settings
6. Complete Web-first coursework and collaboration flows
7. Resume Android local notifications only when the user explicitly requests Android work
8. Add friends, privacy, and shared-free-time invitations
9. Add controlled-tag recommendations
10. Add forum and project sharing
11. Add CI for Web first; add Android CI when Android work resumes

Do not skip core coursework reliability to begin social features early.

## Repository Layout

- `apps/api`: Hono + TypeScript API
- `apps/api/src/entrypoints/node.ts`: local Node/SQLite entrypoint
- `apps/api/src/entrypoints/worker.ts`: Cloudflare Workers/D1 entrypoint
- `apps/api/migrations`: shared SQL migrations
- `apps/mobile`: Flutter Android/Web/iOS client
- `apps/mobile/lib/features/auth`: authentication client and UI
- `apps/mobile/lib/features/academic`: courses and assignments
- `apps/mobile/lib/features/home`: signed-in home UI
- `apps/api/src/modules/identity/cas-login-service.ts`: CAS browser login and staging password-challenge flow
- `apps/admin`: static admin console (no build step)
- `docs/knowledge`: per-folder knowledge base and architecture decisions (see Knowledge Base Protocol)
- `scripts/knowledge-check.mjs`: validates the knowledge base

This is a pnpm monorepo. Backend business logic must remain shared between Node/SQLite and Workers/D1; do not fork separate product logic per runtime.

## Knowledge Base Protocol

The knowledge base in `docs/knowledge/` mirrors the folder structure. Use it to avoid re-reading source code and to respect past decisions. Read only what the current task needs.

Before editing a path, read the nearest `README.md` in `docs/knowledge/` that matches the path (the file's directory, then its parents):

| Working on | Read first |
| --- | --- |
| `apps/api/src/http/**` | `docs/knowledge/apps/api/src/http/README.md` (endpoint contracts) |
| `apps/api/src/modules/**` | `docs/knowledge/apps/api/src/modules/README.md` |
| `apps/api/src/adapters/**`, `student-verifier` | `docs/knowledge/apps/api/src/adapters/README.md` |
| `apps/api/src/core/**` | `docs/knowledge/apps/api/src/core/README.md` |
| `apps/api/src/entrypoints/**`, env vars, `wrangler*` | `docs/knowledge/apps/api/src/entrypoints/README.md`, `docs/knowledge/apps/api/README.md` |
| `apps/api/migrations/**` | `docs/knowledge/apps/api/migrations/README.md` (includes the remote-migration risk) |
| `apps/api/test/**` | `docs/knowledge/apps/api/test/README.md` |
| `apps/admin/**` | `docs/knowledge/apps/admin/README.md` |
| `apps/mobile/lib/app.dart`, navigation | `docs/knowledge/apps/mobile/lib/README.md` |
| `apps/mobile/lib/features/**` | `docs/knowledge/apps/mobile/lib/features/README.md` |
| `.github/**` | `docs/knowledge/.github/workflows/README.md` |

For any architecture change, security-sensitive change, or design proposal:

1. Read the index table in `docs/knowledge/decisions.md` (it is short) and check whether an ADR already covers the topic. Grep the matching `## ADR-0xx` section for details.
2. If the requested change contradicts an ADR, say so and ask before proceeding. Do not silently override it.
3. A new decision gets a new ADR with the next number, added to both the index table and the body. To replace a decision, mark the old one `已替代` and link the new one; never delete ADRs.

After a change, update the affected knowledge doc in the same change, and record any new decision as an ADR. `pnpm knowledge:check` must pass. It fails on broken links, ADR index mismatches, and API routes missing from the OpenAPI document.

## Architecture Boundaries

### API

- Keep HTTP routing in `apps/api/src/http`.
- Keep domain behavior in `apps/api/src/modules`; route handlers only validate input, call a service, and map results to status codes.
- Keep runtime and storage differences behind adapters.
- All authenticated endpoints use `Authorization: Bearer <token>`.
- Return stable JSON errors shaped as `{ "error": { "code": "...", "message": "..." } }`.
- Validate request bodies at the HTTP boundary.
- Update OpenAPI route summaries when adding endpoints.
- Add forward-only migrations; do not edit an already deployed migration after production begins.

### Flutter

- UI depends on repository interfaces, not directly on Dio.
- Construct production Dio repositories at the app composition boundary.
- Inject fake repositories in widget tests; tests must not make real network requests.
- Use `go_router` for top-level navigation and browser URLs.
- Current top-level routes are `/login`, `/notifications`, and a shell with branches `/`, `/schedule`, `/map`, `/assignments`, `/plans`, `/discover` (`friends`, `availability`), `/community`, `/profile` (`tags`). `/projects` redirects to `/community?tab=teams`. Details: `docs/knowledge/apps/mobile/lib/README.md`.
- Preserve direct URL loading, browser back/forward behavior, and auth redirects.
- Web uses path URL strategy. Production static hosting must rewrite unknown application paths to `index.html`.
- API base URL is configured with `--dart-define=API_BASE_URL=...`.
- Default local API URLs are `http://127.0.0.1:8787` on Web and `http://10.0.2.2:8787` on an Android emulator. A physical Android device needs a reachable LAN URL or `adb reverse`.
- After a successful mutation, update/reload page state immediately. Never return a `Future` from a `setState` callback.

## Security and Identity

These constraints are mandatory:

- Never persist raw student IDs for new accounts. `student_identities.student_id_hash` is a legacy/reserved column only (ADR-023).
- Never persist real names unless a later explicit product decision requires them.
- Never persist school passwords or school tokens. Do not persist school cookies/session state durably.
- The staging-only CAS password + captcha exception (2026-10-14 approval) is **disabled**. Its code is commented out and must not be re-enabled without a new explicit approval (ADR-021).
- Legacy student IDs are represented using an HMAC with a secret pepper. New accounts use `users.username` (lowercase, unique) and never write to `student_identities`.
- Application passwords use PBKDF2 credentials.
- Do not log passwords, access tokens, peppers, credentials, or complete authentication payloads.
- Do not weaken TLS validation or bypass certificate checks.
- Never commit `.env`, `.dev.vars`, D1 secrets, signing keys, keystores, `key.properties`, or passwords.
- Registration requires an invite code and an email (ADR-021). Production registration stays disabled (`INVITE_REGISTRATION_ENABLED` is not set in `wrangler.jsonc`). Do not enable it in production without explicit approval.
- Student identity is self-declared and not verified against the school (ADR-021). School password, captcha, and CAS registration code is commented out.
- Emails are recorded in `user_emails` (ADR-021). Do not return another user's email, and do not publish emails.
- Student identities expire 365 days after verification (ADR-018). Renewal currently has no path after ADR-021; this is an open decision.
- Friend schedule visibility has four levels (ADR-019). Plan notes are never returned to other users.

School identity verification (CAS, captcha, school password) is disabled as of 2026-10-14. The reasoning and the open questions are in ADR-006, ADR-007, and ADR-021. The public `byrdocs/bupt-auth` project is third-party code and is not an official BUPT API. Do not use its UCloud token or role flows.

The earlier staging-only captcha experiment (ADR-007) is superseded. Do not revive it. Do not ask for or submit real school credentials.

## Local Development

Requirements:

- Node.js 22+
- pnpm
- Flutter stable
- Android command-line SDK and JDK 17 for Android builds

Install dependencies and run the API:

```bash
pnpm install
pnpm dev
```

The local API listens on `http://127.0.0.1:8787` and automatically applies the initial SQLite migration when needed.

Run Flutter Web:

```bash
cd apps/mobile
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080
```

The developer machine may use these Flutter mirrors because the campus network intermittently breaks large upstream downloads:

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

Do not assume those variables exist in CI; configure CI explicitly. Do not disable TLS if a repository is unreachable.

## Build Commands

From `apps/mobile`:

```bash
flutter build web --release
flutter build apk --debug
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

Artifacts:

- Web: `apps/mobile/build/web`
- Debug APK: `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`
- Release APKs: `apps/mobile/build/app/outputs/flutter-apk`
- Release AAB: `apps/mobile/build/app/outputs/bundle/release/app-release.aab`

Release Android builds need a project-owned signing key before external distribution. Never commit the key or its passwords.

## Required Verification

Run checks appropriate to every changed area before reporting completion.

Backend:

```bash
pnpm check
pnpm test
pnpm build
```

Flutter:

```bash
cd apps/mobile
dart format lib test
flutter analyze
flutter test
```

Documentation:

```bash
pnpm knowledge:check
```

For Web changes, also run:

```bash
flutter build web --debug
```

For Android or plugin/configuration changes, also run at least:

```bash
flutter build apk --debug
```

Tests should verify user-observable behavior at public seams. Important Flutter flows include:

- signed-out launch shows authentication
- session restoration and logout
- auth-protected route redirects
- creating a course displays it without refreshing
- creating an assignment displays it without refreshing
- assignment completion changes immediately
- direct navigation to `/schedule` and `/assignments`

When a test or build fails, identify the actual root cause before changing code. Do not label network, JDK, Gradle, or application errors interchangeably.

## Data and Destructive Operations

- Local development data is stored in `apps/api/fstudy.sqlite` and its WAL/SHM files.
- Do not delete or reset it unless the user explicitly authorizes clearing local data.
- Never reset, revert, or discard uncommitted changes you did not create.
- Do not use destructive Git commands such as `git reset --hard`, `git clean -fd`, or forced checkout.
- The repository may begin with all files uncommitted; inspect `git status` before editing and do not assume untracked files are disposable.

## Production

The intended production backend is Cloudflare Workers + D1 using the same backend business code.

Production was deployed on 2026-10-22:

- API: `https://fstudy-api.a07450865.workers.dev` (Worker `fstudy-api`, D1 `fstudy`).
- Student Web: `https://fstudy-web.a07450865.workers.dev` (Workers static assets, SPA fallback).
- Admin console: `https://fstudy-admin.pages.dev` (Pages, `config.js` points to the production API).
- Migrations `0001`–`0015` applied to both staging and production.
- `INVITE_REGISTRATION_ENABLED=true`; every registration still needs an invite code.
- Production admin credentials are stored outside the repository at `~/.fstudy/production-admin.txt` (mode 0600). Change the bootstrap password after first login.
- The `fstudy-student` Pages project exists but is unused: direct Pages uploads repeatedly failed at `upsert-hashes`. Deploy the student Web with `apps/mobile/wrangler.jsonc` instead.

Rebuild/redeploy steps (use Node 22 for Wrangler; Node 26 hangs on some Cloudflare API calls):

```bash
cd apps/api
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy
cd ../mobile
flutter build web --release --dart-define=API_BASE_URL=https://fstudy-api.a07450865.workers.dev
cd ../api
pnpm dlx node@22 node_modules/wrangler/bin/wrangler.js deploy --config ../mobile/wrangler.jsonc
```

Never deploy with the development pepper, placeholder D1 ID, debug Android signing, or without `ALLOWED_ORIGINS` covering the deployed Web origin.

## Handoff: username accounts and release prep (2026-10-22)

Read this section before continuing. It supersedes earlier handoff text about captcha, school-password registration, and student-ID accounts.

### Repository state

- Migration `0015_usernames.sql` adds `users.username`, backfills legacy accounts, and creates a unique index. `student_identities` remains as a reserved table. It has **not** been applied to remote staging or production.
- Android release signing is configured from `apps/mobile/android/key.properties` with a debug fallback; `key.properties` and keystores are git-ignored.
- Production config `apps/api/wrangler.jsonc` is still a template (placeholder D1 ID and origin). No production deploy has been performed.
- Verification after the username change: API `pnpm check`, `pnpm test` (32 tests), `pnpm build`, `pnpm knowledge:check`; Flutter `dart format`, `flutter analyze`, `flutter test` (32 tests), `flutter build web --release`.

### Identity model (ADR-021, ADR-023)

- Registration: username (3–20 letters/digits/underscore, lowercase, unique), email (recorded in `user_emails`, unverified), app password, optional display name (defaults to username), and an invite code. No student ID and no school verification.
- Login uses username (case-insensitive) + app password. `student_identities` is not written for new accounts.
- Invite codes: each user may generate 5 per Asia/Shanghai calendar month (`/v1/me/invites`). Operators generate codes with `/v1/admin/invites`, which do not count against any user.
- Invite codes: each user may generate 5 per Asia/Shanghai calendar month (`/v1/me/invites`). Operators generate codes with `/v1/admin/invites`, which do not count against any user.
- `INVITE_REGISTRATION_ENABLED`: `true` in `wrangler.staging.jsonc`. Not set in `wrangler.jsonc` (production), so production registration is closed.
- School verification code (captcha, school-password challenge, `verify`) is commented out with a `[2026-10-14 已停用]` marker. Browser CAS login code remains and stays disabled (`CAS_LOGIN_ENABLED=false`).
- Identity expiry is no longer relevant: new accounts have no `student_identities` row (ADR-022, ADR-023). Usernames are self-declared and unverified; reassess identity trust before public launch.

### Staging environment (Cloudflare)

- The Wrangler account is the user's personal account. Do not print secrets or paste them into chat.
- Student Pages: `https://fstudy-student-staging.pages.dev`
- API Worker: `https://fstudy-api-staging.a07450865.workers.dev`
- D1 database: `fstudy-staging`; its ID is in `apps/api/wrangler.staging.jsonc`.
- Production config `apps/api/wrangler.jsonc` stays unchanged, with placeholder D1 ID and origin. Never deploy it without approval.
- `STUDENT_ID_PEPPER` is a Wrangler secret. `CAS_STATE_ENCRYPTION_KEY` is no longer read by the code. Never list or output secret contents.
- D1 remote migration history reached `0014` on staging; `0015` is pending. Always check remote history and schema before any further migration.

### Brevo / email

- Email is recorded only. No verification emails are sent.
- If email delivery is added later, prefer the Brevo HTTPS transactional API (`https://api.brevo.com/v3/smtp/email`) over SMTP. The sender domain must be verified with DNS SPF/DKIM/DMARC. Do not send any email until the user supplies the domain and approves.

## Known Environment Notes

- The local Android SDK is under `$HOME/Android/Sdk`.
- Flutter is configured to use JDK 17 while the system may use a newer default Java.
- Campus networking has previously served an unrelated TLS certificate for Gradle domains. The project wrapper uses Gradle's official GitHub release asset with a SHA-256 checksum, and a user-level Gradle plugin mirror may be configured locally.
- Large GitHub release downloads may be interrupted. Retry or use a trusted mirrored source with integrity verification; do not disable certificate checks.
- `sqlite3` is currently pinned to `3.5.2` because newer native asset downloads were unreliable on the development network. Reassess intentionally before upgrading.

## Documentation Hygiene

- Keep root `README.md` aligned with the actual state of the Flutter client; remove obsolete statements when touched.
- Keep `docs/knowledge` aligned with code using the Knowledge Base Protocol above.
- Update this file when architecture, routes, security assumptions, or implementation order changes.
- Prefer concise Chinese user-facing copy and clear English code identifiers.
