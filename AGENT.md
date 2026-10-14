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

- Never persist raw student IDs.
- Never persist real names unless a later explicit product decision requires them.
- Never persist school passwords or school tokens. Do not persist school cookies/session state durably.
- Exception explicitly approved by the user for *staging experiment only*: a CAS password+captcha flow may briefly retain the CAS cookie/execution state encrypted with AES-GCM in D1, with a five-minute TTL, one-time challenge, strict rate limits, and immediate ciphertext clearing on completion/failure. Never enable this in production. The encryption key must be a Wrangler secret, never a file or Git value.
- Student IDs are represented using an HMAC with a secret pepper.
- Application passwords use PBKDF2 credentials.
- Do not log passwords, access tokens, peppers, credentials, or complete authentication payloads.
- Do not weaken TLS validation or bypass certificate checks.
- Never commit `.env`, `.dev.vars`, D1 secrets, signing keys, keystores, `key.properties`, or passwords.
- Production registration remains disabled. Do not deploy or enable any student registration in production.
- Local development uses `DevelopmentStudentVerifier`; its fixed school test password is `dev-password`.
- Production `AUTH_MODE` defaults to `disabled`.
- Student identities expire 365 days after verification (ADR-018). Expired identities cannot log in, their sessions stop working, and they are excluded from discovery and friend/availability flows until re-verified through a fresh school verification.
- Friend schedule visibility has four levels (ADR-019). Plan notes are never returned to other users.

The user does not plan to obtain BUPT authorization. The public `byrdocs/bupt-auth` project is third-party code, not an official BUPT API. Its `cas: true` mode validates against CAS but still takes the user's password in the calling process; its default mode additionally exchanges UCloud tokens and roles and must not be used. Do not describe either mode as password-blind OAuth.

The user explicitly approved an experimental **staging-only direct CAS password + manual captcha** option. It forwards the submitted school password from the staging Worker to `auth.bupt.edu.cn` over HTTPS, does not log/store the password, and must disclose this to testers. It temporarily stores only encrypted CAS session cookie/execution state as described above. Captcha OCR, bypass, retry loops, and automated solving are prohibited. Production remains closed. A browser-redirect CAS flow was attempted but BUPT replied: `未认证授权的服务，不允许使用CAS来认证此目标应用。`; the staging Worker redirect feature flag remains false. Do not attempt to bypass BUPT service registration.

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

Before deployment:

1. Create the D1 database.
2. Replace `REPLACE_WITH_D1_DATABASE_ID` in `apps/api/wrangler.jsonc`.
3. Store `STUDENT_ID_PEPPER` with Wrangler secrets.
4. Apply remote migrations.
5. Implement and review a safe production student verifier.
6. Explicitly choose the production `AUTH_MODE`.
7. Configure Web SPA route fallback to `index.html`.

Never deploy with the development pepper or development student verifier.

## Handoff: staging, identity, notifications (2026-10-14)

Read this section before continuing the current unfinished work.

### Staging environment (Cloudflare)

- Cloudflare account used by Wrangler is the user's personal account. Do not print secrets or paste them into chat.
- Student Pages: `https://fstudy-student-staging.pages.dev`
- API Worker: `https://fstudy-api-staging.a07450865.workers.dev`
- D1 database: `fstudy-staging`, ID is in `apps/api/wrangler.staging.jsonc`.
- Production config `apps/api/wrangler.jsonc` remains untouched, `AUTH_MODE=disabled`, with placeholder D1 ID/origin. Never deploy production config.
- Staging config `apps/api/wrangler.staging.jsonc` currently has `AUTH_MODE=bupt-cas`, `SCHOOL_PASSWORD_REGISTRATION_ENABLED=false`, `CAS_LOGIN_ENABLED=false`. This is intentionally closed because captcha-image retrieval is not working reliably. Keep it closed until the captcha display path is proved with a mock and then a user-approved staging test.
- `STUDENT_ID_PEPPER` and `CAS_STATE_ENCRYPTION_KEY` have been uploaded as Wrangler secrets. Secret values are not in the repo; never list/output secret contents.
- D1 remote migration history has reached `0013_cas_challenge_attempts.sql` (verified 2026-10-14 via `d1_migrations`). The remote `cas_password_challenges` table already contains `attempt_count` (created by `0012`), and `0013` only adds the `cas_password_challenges_attempts_idx` index. Remote schema matches the repository files. Never reset the D1; inspect remote history/schema before any further changes.
- A prior staging request for a fictional student ID returned `school_auth_captcha_required`; no real credentials were sent and no student was created from that request.

### Current uncommitted work

All current changes are uncommitted; preserve them. They include:

- `0010_notifications.sql`, `0011_cas_browser_login.sql`, `0012_cas_password_challenges.sql`, `0013_cas_challenge_attempts.sql` and notification service/API/UI.
- CAS verifier, browser CAS start/callback/complete endpoints, encrypted password-challenge state, rate limiting, UI wiring.
- Profile changes: dark mode, safer logout; notifications bell/inbox.
- `apps/api/wrangler.staging.jsonc` has per-staging settings. Do not accidentally commit secrets (it contains only resource IDs/URLs/config flags).

Latest complete local verification before handoff: API `pnpm check`, 30 API tests, `pnpm build`; Flutter analyze and 31 widget tests; Web Release build. Recent test runs have exposed migration-fixture mismatches (`no such column: student_id_hash`, duplicate `attempt_count`); these are being corrected. Re-run the full suites before claiming green.

### CAS captcha implementation is NOT ready for users

- `BuptCasStudentVerifier.beginPasswordChallenge()` currently tries to extract the dynamic captcha ID by scraping CAS HTML / `login-normal.html` script. This failed: staging challenge returned a valid challenge ID but `captchaImage: null`.
- Public CAS shell HTML has hidden `#captcha` and iframe `https://auth.bupt.edu.cn/authserver/cas/login-normal.html`; `login-normal.html` loads `lib/index-normal.css` plus obfuscated anti-bot JS; the browser performs dynamic calls to populate `config.captcha`. BrowserAct headless got HTTP 400 on the iframe and no XHR. Raw public fetch showed the captcha is initialized dynamically; current parser does not reproduce that endpoint yet.
- Do NOT enable staging registration while `captchaImage` is null. Don't ask the user for real credentials to diagnose this. User authorized one staging challenge test using a fictional student ID with no password submission; that returned null image. Keep real submissions user-initiated and don't submit a password until a captcha is visibly rendered in FStudy.
- CAS auth explicitly rejected FStudy's callback `service` as unauthorized. Keep browser redirect CAS disabled; only BUPT registration of a service URL could change this.
- Staging registration is currently disabled. A `CAS_STATE_ENCRYPTION_KEY` Wrangler secret exists (never reveal it); latest staging config has `SCHOOL_PASSWORD_REGISTRATION_ENABLED=false`. The new manual-captcha challenge code is local and has not been deployed. User requested a product test, but never ask for/submit a password unless a real captcha is visibly rendered. Before enabling: finish local tests, verify remote 0012/0013, confirm key, deploy staging only, request challenge with fictional ID and require non-null image. If image is null, immediately leave/restore the flag as false. Production always remains disabled.

### User decision on identity strategy

- User said they do not intend to obtain school authorization and requested email/invite alternatives. They later asked for password input, and explicitly approved temporary **encrypted staging-only** CAS session storage to handle manual captcha. This does not mean production approval, service authorization, or approval to bypass captcha.
- Explain accurately: open source does not remove server trust; direct password submission means the Worker receives the school password in memory before forwarding it to CAS. Never claim the app cannot see it. Do not store/log it.
- If CAS captcha workflow remains infeasible, keep it disabled and recommend invite-code pilot; email verification only proves inbox access, not BUPT student status.

### Brevo/email clarification

- Brevo sender-domain authentication verifies the user's owned email sending domain (DNS SPF/DKIM/DMARC); it does not require the Worker request's hostname to be a custom domain.
- Brevo SMTP can additionally reject unknown outbound IPs; Cloudflare Worker egress IP is not fixed/under user's control. Prefer Brevo HTTPS transactional email API (`fetch https://api.brevo.com/v3/smtp/email`) over SMTP if/when adding mail.
- A sender domain and Brevo sender still need verification; likely requires the user's domain. API key belongs in Wrangler secret. Do not implement/send emails until user supplies a sender domain/config and approves.

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
