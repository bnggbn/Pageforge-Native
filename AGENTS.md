# Pageforge Native

Windows first. Flutter/Dart owns UI; Go owns library, document rules, VAX and persistence.

- Ordinary Store.Load/Commit return one snapshot plus history metadata. Use LoadRevision for historical content; LoadHistory/CommitHistory are explicitly aggregate-bounded compatibility/audit APIs. Do not hydrate all objects-v1 historical bodies in the reader; legacy retains its aggregate-bounded compatibility decode until migration.
- Widgets do not access files or HTTP directly. Use repository contracts and focused ViewModels.
- Keep working-copy persistence, reading position, version commands and diff lifecycle separate.
- Preserve existing library JSON and immutable original/version files. Schema changes require migration.
- Use the official github.com/bnggbn/vax-action-history/go release pinned in backend/go.mod for canonical encoding, genesis and SAI. internal/vax is a Pageforge event adapter, not a protocol fork. Never copy or reimplement SDK primitives; preserve historical fixtures and bytes when updating the dependency.
- Backend comments, diagnostics and API error messages use English. Flutter localizes known fault codes. Preserve user data, Unicode test samples and legacy persisted labels; see docs/VAX_DEPENDENCY.md.
- Use temporary/synthetic libraries in tests. Do not mutate real user books.
- Never log the sidecar token. Listen on loopback and authenticate every API request.
- New errors crossing an API boundary use internal/fault codes; HTTP returns code + error. Preserve errors.Is/errors.As causes, classify required missing storage separately from missing resources, and never branch on message text. See docs/API_ERRORS.md.
- Dart dependencies use Flutter Pub; backend dependencies use Go Modules. No Node runtime.
- Keep UI styling with its widgets; share theme tokens in ui/theme.dart.
- Update README capability table and docs/MIGRATION.md when a feature moves from planned to implemented.

Required checks for affected code: gofmt, go test ./..., go vet ./..., dart format,
flutter analyze --no-pub, flutter test --no-pub. Build Windows for platform/plugin changes.
scripts/build.ps1 -RunChecks performs tests, analysis and the release build.
