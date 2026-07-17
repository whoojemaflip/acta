# Schema evolution with upcasters

Acta records are immutable: once an event lands in the events table,
nothing edits it. That's the property the audit log relies on. But
app schemas evolve — a new attribute appears, a semantic shifts, an
event type gets renamed. The straightforward options are unappealing:

- **Mutate history** — rewrite the events table. Breaks immutability
  and any external consumer of the log.
- **Snapshot the boundary** — preserve projections at the cut and
  declare replay-from-zero unsupported. Loses event sourcing's core
  promise.
- **Accept that replay-from-zero is broken** — keep emitting new
  shapes but admit `Acta.rebuild!` can't produce the current
  projection from scratch. Corrosive over time.

**Upcasters** are the standard event-sourcing answer: at replay
time, transform old-shape records into new-shape records in memory,
before projections see them. The stored rows are never touched. The
transformation logic lives in code, where it's tested and audited.

## When to reach for an upcaster

- You renamed an event type (`ItemCreated` → `WorkspaceCreated`) and
  want old records to apply to the new projection.
- You added a required field to an event class and old records lack
  it; you can derive a default at replay time.
- You're dropping an obsolete event type and want pre-deprecation
  records to be skipped on replay.
- You're splitting one logical event into several finer-grained ones
  (a 1-to-many fan-out at replay).

If your schema change is purely additive *and* every site that reads
the field tolerates `nil`, you can probably skip upcasters: bump the
event class to add the attribute, leave `event_version` alone, and
projections cope with missing-field cases inline. Reach for an
upcaster when "tolerate missing field" turns into more conditional
logic than the transform would be.

## The shape of an upcaster

```ruby
# app/upcasters/workspace_migration_upcasters.rb
module WorkspaceMigrationUpcasters
  include Acta::Upcaster

  upcasts "ItemCreated", from: 1, to: 2 do |event, context|
    payload = event.payload

    if payload["item_type"] == "goal"
      # A v1 goal becomes a v2 workspace. Record the mapping so
      # descendant items can resolve their workspace_id below.
      context[:goal_to_workspace][payload["item_id"]] = payload["item_id"]

      event.upcast_to(
        type: "WorkspaceCreated",
        payload: {
          "workspace_id" => payload["item_id"],
          "title"        => payload["title"]
        },
        schema_version: 2
      )
    else
      workspace_id =
        context[:goal_to_workspace][payload["parent_id"]] ||
        context[:item_to_workspace][payload["parent_id"]]

      if workspace_id.nil?
        context.fail_replay!(
          "Unmappable item #{payload['item_id']}: no goal ancestor"
        )
      end

      context[:item_to_workspace][payload["item_id"]] = workspace_id

      event.upcast_to(
        payload: payload.merge("workspace_id" => workspace_id),
        schema_version: 2
      )
    end
  end
end
```

Register it once at boot:

```ruby
# config/initializers/acta_upcasters.rb
Acta.register_upcaster(WorkspaceMigrationUpcasters)
```

Then bump the new emit path so freshly emitted events carry
`event_version: 2`:

```ruby
class ItemCreated < Acta::Event
  def self.event_version = 2
  attribute :item_id,      :string
  attribute :workspace_id, :string
  # ...
end
```

That's the whole feature surface. New writes are at v2; old reads
get upcasted to v2 before they hit projections.

## What blocks can return

Inside an `upcasts` block, the return value controls what the
pipeline does next:

| Return value                          | Effect                                           |
| ------------------------------------- | ------------------------------------------------ |
| `event.upcast_to(...)`                | Continue chaining at the new (type, version)     |
| Array of `event.upcast_to(...)`       | Fan-out: each branch chains independently        |
| `nil` or `[]`                         | Drop the record from this replay                 |
| `context.fail_replay!("reason")`      | Halt with `Acta::ReplayHaltedByUpcaster`         |

If you need to leave a record alone at the current version — e.g. a
boundary-marker event that's already in its final shape — use the
NO_OP sentinel:

```ruby
upcasts "GoalPromotedToWorkspace", from: 2, to: 2, &Acta::Upcaster::NO_OP
```

## Stateless vs stateful upcasters

Upcasters come in two flavors and the distinction matters for which
read surfaces will produce correct output.

**Stateless** — the transform depends only on the record itself.
Adding a default for a new field, renaming a key in the payload,
or unconditionally bumping the event type all qualify. The
`context` argument is ignored.

```ruby
upcasts "ItemCreated", from: 1, to: 2 do |event, _ctx|
  event.upcast_to(
    payload: event.payload.merge("workspace_id" => "default"),
    schema_version: 2
  )
end
```

**Stateful** — the transform depends on context populated by an
earlier event in the same replay. Resolving a descendant's
`workspace_id` from a goal seen earlier in the stream is the
canonical example.

```ruby
upcasts "ItemCreated", from: 1, to: 2 do |event, ctx|
  payload = event.payload
  if payload["item_type"] == "goal"
    ctx[:goal_to_workspace][payload["item_id"]] = payload["item_id"]
    event.upcast_to(type: "WorkspaceCreated", ...)
  else
    workspace_id = ctx[:goal_to_workspace][payload["parent_id"]]
    event.upcast_to(payload: payload.merge("workspace_id" => workspace_id), schema_version: 2)
  end
end
```

Stateful upcasters require **global insertion order**, which is
exactly what `Acta.rebuild!` (and `Acta.events.all` / `#each`)
provides. They will silently produce incomplete output on read
surfaces that can't supply that order — see the next section.

## Context semantics across read surfaces

Different read paths give upcasters different views of the world.
Stateless upcasters are unaffected by any of this; stateful
upcasters need to know.

| Read surface                          | Context lifetime                 | Safe for stateful upcasters? |
| ------------------------------------- | -------------------------------- | ---------------------------- |
| `Acta.rebuild!`                       | One shared, full insertion order | Yes                          |
| `Acta.events.all` / `#each`           | One shared, full insertion order | Yes                          |
| `Acta.events.find_by_uuid(uuid)`      | Fresh per call                   | No — incomplete resolution   |
| `Acta.events.first` / `.last`         | Fresh per call                   | No — incomplete resolution   |
| `Acta.events.for_stream(...)#all`     | Shared, but stream-ordered       | Usually no — wrong order     |
| `Acta::ReactorJob#perform`            | Fresh, single record             | No — incomplete resolution   |
| Web admin (`Acta::Web::EventsController`) | N/A — shows raw stored rows  | N/A                          |

The pattern: any time you hand the pipeline a full ordered stream,
stateful upcasters work. Any time you hand it one record (or a
stream-reordered subset), they can't reconstruct the state they
need.

### Implication for stateful migrations

A stateful migration is fundamentally a `rebuild!`-shaped operation.
The cutover playbook is:

1. Deploy code that emits at the new `event_version` and includes
   the upcasters.
2. Drain the reactor queue. Jobs enqueued before the deploy will
   re-hydrate their events through the upcaster pipeline with a
   fresh context — fine for stateless upcasters, possibly
   incomplete for stateful ones.
3. Run `Acta.rebuild!` to regenerate projections from the full
   ordered log under the new schema.
4. Flip reads.

Apps that need stateful read-time resolution outside `rebuild!`
should consider whether the resolved field belongs in the
projection rather than in the upcaster — projections are the
durable, queryable view, and once `rebuild!` has run, projections
hold the post-upcast state without needing the pipeline at read
time.

## Chaining across N versions

Upcasters can be declared on a single event type across many
versions; the pipeline walks them in order:

```ruby
module SuccessiveBumps
  include Acta::Upcaster

  upcasts "ItemCreated", from: 1, to: 2 do |e, _|
    e.upcast_to(payload: e.payload.merge("workspace_id" => "?"), schema_version: 2)
  end

  upcasts "ItemCreated", from: 2, to: 3 do |e, _|
    e.upcast_to(payload: e.payload.except("legacy_kind"), schema_version: 3)
  end
end
```

A v1 record passes through both transforms in sequence. A v2 record
(emitted between the two migrations) picks up the second transform
only. Events emitted by current v3 code pass through identity.

## Testing upcasters

Two helpers live in `Acta::Testing::DSL`:

- `acta_seed_event(type:, payload:, event_version: 1, ...)` —
  inserts an event row directly, bypassing `Acta.emit` (which always
  stamps the *current* code's `event_version`).
- `acta_replay(events:, upcasters: [])` — registers the supplied
  upcasters, seeds events, and runs `Acta.rebuild!`.

```ruby
RSpec.describe "Workspaces migration" do
  include Acta::Testing::DSL

  it "promotes goals to workspaces and rewires descendants" do
    acta_replay(
      upcasters: [ WorkspaceMigrationUpcasters ],
      events: [
        { type: "ItemCreated", event_version: 1,
          payload: { "item_id" => "g_1", "item_type" => "goal", "title" => "Q3" } },
        { type: "ItemCreated", event_version: 1,
          payload: { "item_id" => "i_2", "parent_id" => "g_1", "title" => "Plan" } }
      ]
    )

    expect(Workspace.pluck(:id)).to eq([ "g_1" ])
    expect(Item.find("i_2").workspace_id).to eq("g_1")
  end
end
```

The existing `ensure_replay_deterministic` matcher implicitly
exercises the upcaster pipeline twice — impure upcasters (state
leaking outside the per-replay context) surface as a snapshot diff
on the second pass.

## What upcasters intentionally do *not* do

- **They don't rewrite the event store.** Stored rows are immutable;
  transforms exist only in memory during a replay pass.
- **They don't run on the live emit path.** `Acta.emit` stamps the
  current code's `event_version` and dispatches the in-memory event
  directly — no read round-trip, no upcaster pass. Live writes are
  always at the latest version.
- **They're not a migration framework.** The decision to bump
  `event_version` and write an upcaster is the schema migration. The
  upcaster's job is just replay correctness.
- **They're not cross-tenant.** Each tenant's events table replays
  independently; upcaster context is per-replay-pass, per-tenant.

## Edge cases worth knowing about

- **Future-version records.** If a replay sees an event whose stored
  `event_version` exceeds the highest `to` any registered upcaster
  knows how to reach for that type, the pipeline raises
  `Acta::FutureSchemaVersion`. Typically: an older deployment is
  replaying events emitted by a newer one. Halting is the safe call.
- **Type renames remove the need to keep old classes around.**
  Upcasters operate on raw records pre-hydration, so the original
  `ItemCreated` constant can be deleted from the codebase the moment
  its upcaster renames the type. Hydration only ever happens for
  classes the upcaster pipeline produces.
- **1-to-many composes with chaining.** Each record an upcaster
  fans out into walks the version ladder independently — including
  through more 1-to-many transforms if you have them.
- **Conflicting registrations raise at boot.** Two upcaster classes
  that claim the same `(event_type, from)` pair surface as
  `Acta::UpcasterRegistryError` the moment the second one registers.
  Pick an owner.
