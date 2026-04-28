# Changelog

All notable changes to Acta are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Public API stability begins at v1.0.0. Versions prior to that may make
breaking changes as the API settles through real-world consumer integration.

## [Unreleased]

### Changed

- Custom AM type classes consolidated under `Acta::Types::*`.
  `Acta::ModelType` → `Acta::Types::Model`,
  `Acta::ArrayType` → `Acta::Types::Array`. The `:encrypted_string`
  type was already there as `Acta::Types::EncryptedString`. The
  user-facing API (`attribute :foo, Class`, `attribute :foo,
  array_of: ...`, `attribute :foo, :encrypted_string`) is unchanged
  — these classes are internal and never appeared in user code,
  README, or specs. Breaking only for someone constructing them
  directly via `Acta::ModelType.new(...)`.

## [0.2.0] — 2026-04-27

### Added

- `Acta::Projection.truncates(*ar_classes)` — class macro for declaring
  the AR classes a projection owns. Used both as the default `truncate!`
  target list (`delete_all` on each in declared order) and as input to
  `Acta.rebuild!`'s cross-projection ordering: projections whose tables
  are FK-referenced by another projection's tables now run first, so
  children are deleted before their parents — independent of registration
  order. Cycles raise `Acta::TruncateOrderError`. Projections without
  `truncates` declarations keep their existing registration-order
  behavior. The truncate phase runs inside `Projection.applying!`, so
  `acta_managed!` models truncate cleanly. Closes #3.

- `acta_managed!` AR class macro — opt-in safety net for projection-owned
  models. Once an AR model becomes a projection, writes from anywhere
  other than the projection bypass the event log and break
  `Acta.rebuild!` determinism. `acta_managed!` gates every AR write path
  (save / update / destroy / update_columns / update_all / delete_all /
  insert_all / upsert_all) on `Acta::Projection.applying?` and raises
  `Acta::ProjectionWriteError` (or warns, with `on_violation: :warn`)
  when violated. `Acta::Projection.applying! { … }` is the public escape
  hatch for fixtures, migrations, and intentional backfills. Closes #6.

- `Acta::Testing.default_actor!(config, **attrs)` — RSpec configuration
  helper that sets `Acta::Current.actor` before every example and resets
  it after, eliminating the per-spec boilerplate and the easy-to-forget
  `Acta::MissingActor` errors that come with it. Defaults to a
  `system / rspec / test` actor; override any attribute. Closes #8.
- `Acta::Testing::DSL#with_actor(**attrs) { … }` — block-scoped actor
  override for individual examples that need to attribute emissions to
  a specific user. Restores the previous actor when the block returns
  (or raises).

- `Acta::Railtie` — auto-loads projection / handler / reactor classes at boot
  so they self-register before the first emit, even in Rails dev mode where
  Zeitwerk would otherwise lazy-load them on first reference. Without this,
  a projection that nothing has touched yet stays unsubscribed: the emit
  succeeds, the event row is written, and the projection silently never runs.
  Configurable via `config.acta.{projection,handler,reactor}_paths`; defaults
  to `app/projections`, `app/handlers`, `app/reactors`. Set a path list to
  `[]` to opt out. Closes #7.

### Changed

- **Breaking: command DSL collapses around streams, concurrency, and
  emit declarations.**
  - Removed `Acta::Command.stream` macro. Commands no longer declare or
    inherit stream identity — events are the only thing that carries
    stream config.
  - Removed `Acta::Command.on_concurrent_write` macro and the
    capture-at-instantiation / assert-at-emit machinery on Command
    instances.
  - Removed `Acta::Command.emits` macro and `emitted_event_class(es)`.
    The framework no longer asks commands to declare what they emit;
    `def call` is the only source of truth. The "primary event" concept
    that came with single-arg `emits` was a fiction once commands could
    legitimately emit zero, one, or many events.
  - `Acta::Command.call` now returns the command instance (was: the
    return value of the user's `#call` method). Read events back via
    `cmd.emitted_events` — an array of every event emitted during the
    invocation, in order. Idempotent commands return an instance with
    an empty array.
  - Renamed `Acta.emit(event, expected_sequence: N)` keyword to
    `if_version: N`.
  - Renamed `Acta::ConcurrencyConflict` → `Acta::VersionConflict`. Its
    `expected_sequence` / `actual_sequence` readers are now
    `expected_version` / `actual_version`.

  `Acta::Command` now has four moving parts: `param`, `validates`,
  `call`, `emit`. Apps that need optimistic locking write it explicitly
  using the new public primitive:
  ```ruby
  version = Acta.version_of(stream_type: :order, stream_key: order_id)
  emit OrderRenamed.new(...), if_version: version
  ```
  Two lines, fully visible, no macro magic. Most commands need none of
  this and lose nothing.

- `Acta.register_projection` is now idempotent — registering the same
  projection class twice is a no-op instead of double-dispatching events.

### Added

- `Acta.version_of(stream_type:, stream_key:)` — public class method
  returning the current high-water mark for a stream (0 for fresh
  streams). Pair with `Acta.emit(..., if_version:)` for optimistic
  locking.

- Per-attribute payload encryption via `attribute :token, :encrypted_string`.
  Backed by `ActiveRecord::Encryption` — same primary/deterministic/derivation
  keys as Rails AR-encrypted columns, same key-rotation model (append a new
  primary, keep old keys for decryption). In-memory event values stay
  plaintext (`event.token` returns the secret); only the serialized payload
  written to `events.payload` is ciphertext. Resolves the issue where events
  carrying OAuth tokens / API keys would defeat AR encryption on the
  projection's columns by leaving cleartext copies in the audit log. Closes #1.
- `Acta::Event.from_acta_record(envelope:, payload:)` — internal hydration
  hook that routes payload values through `type.deserialize` before
  construction. Used by `EventsQuery` to decrypt `:encrypted_string`
  attributes on read; existing types are unaffected.
- Acta::Web masks encrypted payload leaves as `********` in both the
  row preview and the pretty-JSON detail block. Detection is
  envelope-based (`ActiveRecord::Encryption.encryptor.encrypted?`), so
  any AR-encrypted ciphertext in the payload is masked regardless of
  whether the event class declares `:encrypted_string` — including
  historical events written before the attribute was opted in.

## [0.1.1]

### Added

- `Acta::Command` — new `emits EventClass` class-method DSL. The command
  inherits `stream_type` and `stream_key_attribute` from the declared
  event class, eliminating the duplicate `stream :order, key: :order_id`
  declaration in the common case where a command emits a single event
  for its aggregate. Explicit `stream` on the command still works and
  takes precedence when both are given (useful when the command operates
  on a different aggregate than its emitted event, or doesn't emit an
  Acta event at all).

## [0.1.0]

Feature-complete per the initial implementation plan (M0–M10). Next step
is real-world consumer integration to validate the API before cutting
v1.0.0.

### Core primitives

- `Acta::Event` — ActiveModel-backed event classes with typed payloads,
  validate-on-init, uuid / occurred_at / recorded_at / actor envelope.
- `Acta::Handler` — base primitive with the `on EventClass` DSL and
  auto-registration via Rails eager loading.
- `Acta::Projection < Acta::Handler` — sync + transactional + replayable.
  Raises `ProjectionError` on failure, rolling back the emit. Tracks
  subclasses for `Acta.rebuild!`.
- `Acta::Reactor < Acta::Handler` — after-commit + async via ActiveJob
  (default) or `sync!` opt-in. Skipped during replay.
- `Acta::Command < Acta::Model` — param validation, `stream` declaration,
  `on_concurrent_write :raise` / `:ignore` optimistic-concurrency DSL.
  Raises `InvalidCommand` on param validation failure.
- `Acta::Actor` value object — type, id, source, metadata.
- `Acta::Current` — `ActiveSupport::CurrentAttributes` with an `actor`
  attribute, propagates through ActiveJob.

### Payload shape

- `Acta::Model` base class — `ActiveModel::Attributes` + `ActiveModel::Model`
  + JSON round-trip with schema-drift tolerance.
- Class-typed attributes: `attribute :location, GeoPoint` wraps the class
  in `Acta::ModelType` automatically.
- Array attributes: `attribute :tags, array_of: Tag` wraps the element
  type in `Acta::ArrayType`.
- `Acta::Serializable` concern — opt-in for AR classes to participate as
  payload types with `acta_serialize only:` / `except:` control.
- Nested models and AR classes compose; arrays of either work.

### Storage

- Single events table with identity, stream, payload (JSON/jsonb), actor,
  source, metadata, and dual time columns (`occurred_at` + `recorded_at`).
- Indexes: uuid unique, stream-identity partial unique, event_type,
  actor, source, occurred_at.
- `rails g acta:install` generator for the migration.
- Adapter seam: `Acta::Adapters::SQLite` (default) and
  `Acta::Adapters::Postgres`.
- SQLite: single-writer sequencing with unique-constraint backstop.
- Postgres: `pg_advisory_xact_lock(hashtext(...))` per stream; `uuid` and
  `jsonb` native column types.

### Testing

- `Acta::Testing.test_mode { }` — inline reactors for the block.
- RSpec matchers: `emit(EventClass).with(attrs)`, `emit_events([...])`,
  `emit_any_events`.
- `Acta::Testing::DSL` — given_events / when_command / when_event /
  then_emitted / then_emitted_nothing_else.
- `ensure_replay_deterministic { snapshot }` — catches Time.current,
  rand, and other non-deterministic projection patterns.

### Observability

- ActiveSupport::Notifications:
  - `acta.event_emitted` — `{ event, event_type }`
  - `acta.projection_applied` — `{ event, projection_class }`
  - `acta.reactor_invoked` — `{ event, reactor_class, sync: true }`
  - `acta.reactor_enqueued` — `{ event, reactor_class }`

### Errors

- `Acta::Error` (StandardError)
  - `InvalidEvent` (carries event)
  - `InvalidCommand < CommandError` (carries command)
  - `ConcurrencyConflict` (stream identity, expected/actual sequence)
  - `ProjectionError` (event, projection_class, original)
  - `MissingActor`, `ConfigurationError`, `AdapterError`
  - `UnknownEventType`, `ReplayError`
