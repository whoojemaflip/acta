# Changelog

All notable changes to Acta are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Public API stability begins at v1.0.0. Versions prior to that may make
breaking changes as the API settles through real-world consumer integration.

## [Unreleased]

### Added

- `Acta::Projection.truncates(*ar_classes)` — class macro for declaring
  the AR classes a projection owns. Used both as the default `truncate!`
  target list (`delete_all` on each in declared order) and as input to
  `Acta.rebuild!`'s cross-projection ordering: projections whose tables
  are FK-referenced by another projection's tables now run first, so
  children are deleted before their parents — independent of registration
  order. Cycles raise `Acta::TruncateOrderError`. Projections without
  `truncates` declarations keep their existing registration-order
  behavior. Closes #3.

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

- `Acta.register_projection` is now idempotent — registering the same
  projection class twice is a no-op instead of double-dispatching events.

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
