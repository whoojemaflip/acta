# Acta Implementation Plan

Companion to the design doc (private, at `~/Sites/Journal/ideas/event_source_rails.md`).
This file is version-controlled alongside the code and tracks the milestone
breakdown for reaching v1.0.

## Conventions

- **Ruby hash shorthand** (Ruby 3.1+): `{ name:, age: }` when variables in
  scope match keys. Applied everywhere.
- **RSpec** exclusively for v1. Minitest matcher support considered post-v1.
- **TDD**: every milestone is a sequence of small red → green → refactor
  cycles. One behaviour per commit where practical.
- **Rubocop**: `rubocop-rails-omakase` style. Clean before each commit.
- **Commits**: atomic, imperative mood, one logical change each.
- **Semver** from v0.1. Public API stability begins at v1.0.

## Environment

- Ruby: 3.4+
- Rails floor: 8.1+
- Local: `~/Sites/acta`
- Remote: `git@github.com:whoojemaflip/acta.git`

## Milestone breakdown

Each milestone is independently shippable.

### M0 — Scaffolding ✅

Gem skeleton, RSpec, rubocop-rails-omakase, CI, README, LICENSE, CHANGELOG,
`PLAN.md` in repo. Baseline green build.

### M1 — First emit (the round-trip milestone) ✅

**Goal:** `Acta.emit(event)` persists a row; `Acta.events.last` reads it back.

1. Adapter seam — spec `Acta::Adapters::Base` interface; SQLite adapter stub.
2. Migration generator — `rails g acta:install` creates the events table.
3. `Acta::Model` — AM::Attributes + AM::Model + `to_acta_hash` / `from_acta_hash`
   + `validate!` in initialize raising `Acta::InvalidEvent`.
4. `Acta::Event < Acta::Model` — adds `uuid`, `event_type`, `event_version`,
   `occurred_at`, `recorded_at`, `actor`.
5. `Acta::Actor` value object — `type`, `id`, `source`, `metadata`.
6. `Acta::Current` — CurrentAttributes with `actor`.
7. `Acta.configure` — connection + single-store `:default` registration
   (latent store concept).
8. `Acta.emit(event)` — strict on missing actor (`Acta::MissingActor`);
   persists via adapter; returns the persisted event.
9. `Acta.events` — query API returning `Acta::Event` instances from the log.
10. Error leaves so far: `Error`, `InvalidEvent`, `MissingActor`,
    `ConfigurationError`, `AdapterError`.

**Checkpoint:** end-to-end spec that configures, emits, queries, asserts.

### M2 — Streams & concurrency ✅

1. Stream DSL — `stream :order, key: :order_id` on event classes.
2. Sequence calculation in SQLite adapter (BEGIN IMMEDIATE + SELECT MAX).
3. `ConcurrencyConflict` on unique-index violation.
4. Stream-scoped query — `Acta.events.for_stream(type:, key:)`.
5. `expected_sequence :loaded` machinery (wires into M6 commands).

### M3 — Handlers & dispatch ✅

1. `Acta::Handler` base class + `on EventClass do |event| ... end` DSL.
2. Auto-registration via inheritance + Rails `eager_load_paths`.
3. Dispatch on emit (sync base handlers).
4. Registry isolation for specs — `Acta.reset_handlers!`.

### M4 — Projections ✅

1. `Acta::Projection < Acta::Handler` with sync+transactional contract.
2. Projections run inside emit transaction.
3. `ProjectionError` wraps underlying exception + projection class.
4. `Acta.rebuild!` — truncate projections, replay log, re-run projections.
5. Replay skips reactors (prep for M5).

### M5 — Reactors ✅

1. `Acta::Reactor < Acta::Handler` with after-commit + ActiveJob default.
2. `Acta::ReactorJob` — loads event by uuid, dispatches to reactor class.
3. `sync true` opt-in.
4. Skip on replay.
5. Actor propagation via `Acta::Current` serialized into ActiveJob.

### M6 — Commands ✅

1. `Acta::Command < Acta::Model` — param validation via AM::Attributes.
2. `stream :order, key: :order_id` on command — declares aggregate identity.
3. `expected_sequence :loaded` — captures stream sequence at load.
4. `.call(**params)` entry; `emit event` as instance method;
   `InvalidCommand` on validation failure.
5. Auto-loading from `app/commands/`.

### M7 — Testing DSL (`Acta::Testing`) ✅

1. RSpec matchers: `emit(EventClass).with(...)`, `emit_events([...])`,
   `not_to emit_any_events`.
2. `given_events { ... }` — seeds the log directly without running reactors.
3. `when_command(cmd)` — runs command, captures emitted events.
4. `then_emitted(EventClass, **attrs)` / `then_emitted_nothing_else`.
5. `Acta.test_mode { ... }` — inline reactors for the block.
6. Replay determinism helper —
   `expect_projections_deterministic { ... }`.

### M8 — `Acta::Serializable` (AR piggyback) ✅

1. Concern adding `to_acta_hash` / `self.from_acta_hash(hash)` on AR classes.
2. `acta_serialize only: / except:` configuration.
3. Type dispatch for AR classes in event attributes.
4. Arrays of AR (`array_of:`) support.
5. Nested AR-in-AR round-trip.
6. STI support via `type` column capture.
7. Schema-drift tolerance — filter unknown keys on deserialize.

### M9 — Postgres adapter ✅

1. `Acta::Adapters::Postgres` implementation.
2. Advisory locks (`pg_advisory_xact_lock(hashtext(...))`) per stream.
3. `jsonb` column type + `uuid` column type + `gen_random_uuid()`.
4. Shared behaviour specs — `it_behaves_like "an Acta adapter"`.
5. CI matrix with both SQLite and Postgres.
6. Concurrency-specific specs exercising genuine concurrent writers.

### M10 — v1.0 polish ✅

1. Observability via `ActiveSupport::Notifications` —
   `acta.event_emitted`, `acta.projection_applied`, `acta.reactor_enqueued`.
2. Remaining error leaves — `UnknownEventType`, `ReplayError`, gaps.
3. README rewrite with full worked examples.
4. Tag v1.0.0.

## Milestone dependencies

```
M0 → M1 → M2 → M3 → M4 ─┐
                   └──→ M5 ─┐
                   M6 ──────┴─→ M7 → M8 → M9 → M10
```

M4 and M5 are independent after M3. M6 can start after M2. M8 benefits from
M7. M9 can start anytime after M1 but is most valuable after M8.

## Out of scope for v1

- Upcasters (column reserved)
- Multi-store (latent concept, not exposed)
- MySQL adapter
- `Acta::Saga` / process managers
- LISTEN/NOTIFY or other pub/sub transport
- Snapshots

## Quality gates per commit

- `bundle exec rspec` green
- `bundle exec rubocop` clean
- Change has a spec unless it's pure refactoring
