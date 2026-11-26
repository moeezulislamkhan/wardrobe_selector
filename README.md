# Wardrobe

A personal wardrobe and outfit stylist built with Flutter and Material 3.
Guest mode is the default; signing in remains optional.

## Foundation architecture

- `lib/app/` owns app composition, GoRouter navigation, and the persistent
  bottom-navigation shell.
- `lib/core/` contains shared theme, preference, and error-handling
  infrastructure.
- `lib/features/<feature>/presentation/` keeps each feature's UI grouped
  together as domain and data layers are added.
- Riverpod is the dependency-injection and application-state layer.
- Theme preference is stored locally; the app supports system, light, and dark
  appearance.
- First-run onboarding introduces the digital wardrobe, outfit suggestions, and
  weekly planner. Completion is stored locally, and guest mode never requires
  authentication.
- Widget tests use mocked preferences and verify onboarding, guest navigation,
  and theme selection.

## Wardrobe

The gallery reads only locally saved items and cached photos; it shows an
explicit empty state rather than sample inventory. Items can be added from the
camera or photo library, resized and compressed to a 3 MB JPEG, then saved with
their metadata in app-private storage (browser-local storage on web). Cloud
uploads start only after local persistence and remain queued with retry actions
when signed out, offline, or when an upload fails.

## Outfits

Rule-based suggestions and manual outfits use only the user's locally saved,
active wardrobe items. Manual creation requires a top, bottom, and shoes, with
optional layer and accessory slots; compatibility hints use saved item details.
Manual outfits can be edited or duplicated and are saved locally with a pending
sync flag. Cloud sync for manual outfit records is not yet available. No account
is required for guest mode, and AI image recognition is not used.

## Future AI boundary

`WardrobeAiGateway` defines typed boundaries for clothing-image analysis,
stylist conversations, and personalized advice. Its Riverpod provider defaults
to unavailable, and no AI SDK, provider, or network implementation is included.
Current recommendations continue to use the local rule-based engine and work
without internet or an AI service. Any future network implementation must call
a trusted backend such as a Supabase Edge Function; provider API secrets must
remain server-side and must never be embedded in Flutter.

## Week planner

The planner opens to the next complete Monday–Sunday week (so planning on
Sunday starts the following Monday). Each date is saved independently to local SQLite as soon as an outfit is
selected; older weeks are retained for history and duplication. Date history
can be filtered by planned, worn, skipped, and modified status. Status changes
and edits append immutable item snapshots, so wardrobe edits or deletion do not
rewrite past records. Deleting a plan and its history requires explicit
confirmation. Plans and snapshots remain available offline after the app has
cached the wardrobe. SQLite uses the native database on mobile and
WASM/IndexedDB on web. Plan sync runs asynchronously for signed-in users, and
each plan shows its own sync state. Wardrobe and plan sync currently pushes
local changes only; it does not pull remote changes to another device or
resolve concurrent edits. Two-device sync and conflict resolution are not yet
supported.

## Optional Supabase setup

The app supports optional Supabase authentication, wardrobe-image sync, and
week-plan sync.
Follow the [Supabase setup guide](supabase/README.md) to create a project, apply
the schema and Storage policies, configure client-safe Flutter values, and
verify owner isolation. Never put a service-role or secret key in the app or
commit credentials.

## Run and validate

```shell
flutter pub get
flutter analyze
flutter test
flutter run
```
