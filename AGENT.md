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

1. BUPT-only registration and unique student identity
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

This is a pnpm monorepo. Backend business logic must remain shared between Node/SQLite and Workers/D1; do not fork separate product logic per runtime.

## Architecture Boundaries

### API

- Keep HTTP routing in `apps/api/src/http`.
- Keep domain behavior in `apps/api/src/modules`.
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
- Current routes are:
  - `/login`
  - `/`
  - `/schedule`
  - `/assignments`
- Preserve direct URL loading, browser back/forward behavior, and auth redirects.
- Web uses path URL strategy. Production static hosting must rewrite unknown application paths to `index.html`.
- API base URL is configured with `--dart-define=API_BASE_URL=...`.
- Default local API URLs are `http://127.0.0.1:8787` on Web and `http://10.0.2.2:8787` on an Android emulator. A physical Android device needs a reachable LAN URL or `adb reverse`.
- After a successful mutation, update/reload page state immediately. Never return a `Future` from a `setState` callback.

## Security and Identity

These constraints are mandatory:

- Never persist raw student IDs.
- Never persist real names unless a later explicit product decision requires them.
- Never persist school passwords, school cookies, or school tokens.
- Student IDs are represented using an HMAC with a secret pepper.
- Application passwords use PBKDF2 credentials.
- Do not log passwords, access tokens, peppers, credentials, or complete authentication payloads.
- Do not weaken TLS validation or bypass certificate checks.
- Never commit `.env`, `.dev.vars`, D1 secrets, signing keys, keystores, `key.properties`, or passwords.
- Production registration remains disabled until a safe real BUPT verifier is implemented and reviewed.
- Local development uses `DevelopmentStudentVerifier`; its fixed school test password is `dev-password`.
- Production `AUTH_MODE` defaults to `disabled`.

The application currently cannot access an official BUPT CAS service. Do not improvise a credential proxy or request real school passwords without an explicit security design and user approval.

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

Before deployment:

1. Create the D1 database.
2. Replace `REPLACE_WITH_D1_DATABASE_ID` in `apps/api/wrangler.jsonc`.
3. Store `STUDENT_ID_PEPPER` with Wrangler secrets.
4. Apply remote migrations.
5. Implement and review a safe production student verifier.
6. Explicitly choose the production `AUTH_MODE`.
7. Configure Web SPA route fallback to `index.html`.

Never deploy with the development pepper or development student verifier.

## Known Environment Notes

- The local Android SDK is under `$HOME/Android/Sdk`.
- Flutter is configured to use JDK 17 while the system may use a newer default Java.
- Campus networking has previously served an unrelated TLS certificate for Gradle domains. The project wrapper uses Gradle's official GitHub release asset with a SHA-256 checksum, and a user-level Gradle plugin mirror may be configured locally.
- Large GitHub release downloads may be interrupted. Retry or use a trusted mirrored source with integrity verification; do not disable certificate checks.
- `sqlite3` is currently pinned to `3.5.2` because newer native asset downloads were unreliable on the development network. Reassess intentionally before upgrading.

## Documentation Hygiene

- Keep root `README.md` aligned with the actual state of the Flutter client; remove obsolete statements when touched.
- Update this file when architecture, routes, security assumptions, or implementation order changes.
- Prefer concise Chinese user-facing copy and clear English code identifiers.
