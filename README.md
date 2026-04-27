# Acta

Lightweight event-driven and event-sourced primitives for Rails.

## What it is

A small, opinionated set of primitives for Rails applications that want an
audit log, an event-driven architecture, or event sourcing — without taking
on a heavyweight framework. Apps compose the primitives à la carte:

- Plain event-driven with a persistent audit log
- Event-sourced aggregates with readonly projections
- Hybrid — some aggregates event-sourced, others conventional

What the library ships:

| Primitive | Role |
|---|---|
| `Acta::Event` | ActiveModel-backed event classes with typed payloads |
| `Acta::Handler` | Base primitive — "on event X, run this" |
| `Acta::Projection` | Sync + transactional + replayable (for ES aggregates) |
| `Acta::Reactor` | After-commit + async via ActiveJob (for side effects) |
| `Acta::Command` | Recommended write path with param validation & optimistic concurrency |
| `Acta::Testing` | RSpec matchers, given-when-then DSL, replay-determinism assertions |

Adapters: SQLite and Postgres, both first-class.

## Installation

Not published to RubyGems. Install from git:

```ruby
# Gemfile
gem "acta", git: "https://github.com/whoojemaflip/acta.git"
```

Requires Rails 8.1+ and Ruby 3.4+.

Generate the events table migration:

```bash
bin/rails generate acta:install
bin/rails db:migrate
```

## Usage

### 1. Define an event

```ruby
# app/events/order_placed.rb
class OrderPlaced < Acta::Event
  stream :order, key: :order_id

  attribute :order_id, :string
  attribute :customer_id, :string
  attribute :total_cents, :integer

  validates :order_id, :customer_id, :total_cents, presence: true
end
```

### 2. Emit it

Set the actor once at the request boundary:

```ruby
# ApplicationController
before_action do
  Acta::Current.actor = Acta::Actor.new(
    type: "user",
    id: current_user.id,
    source: "web"
  )
end

# somewhere in your code
Acta.emit(OrderPlaced.new(order_id: "o_1", customer_id: "c_1", total_cents: 4200))
```

That's the minimum viable Acta app — you now have an append-only audit log
keyed by actor (who) and source (through what surface). Actor types and
sources are open strings; pick the vocabulary that fits your app.

### 3. React to events (event-driven)

For side effects that should happen after each event is durably written:

```ruby
# app/reactors/confirmation_email_reactor.rb
class ConfirmationEmailReactor < Acta::Reactor
  on OrderPlaced do |event|
    OrderMailer.confirmation(event.order_id).deliver_later
  end
end
```

Reactors run after-commit and default to async via ActiveJob. Use `sync!`
to run in the caller's thread (mostly useful for tests).

### 4. Project state (event-sourced)

For aggregates where the event log is the source of truth and AR tables
are a derived view:

```ruby
# app/projections/order_projection.rb
class OrderProjection < Acta::Projection
  def self.truncate!
    Order.delete_all
  end

  on OrderPlaced do |event|
    Order.create!(
      id: event.order_id,
      customer_id: event.customer_id,
      total_cents: event.total_cents,
      status: "placed"
    )
  end

  on OrderShipped do |event|
    Order.find(event.order_id).update!(status: "shipped", shipped_at: event.occurred_at)
  end
end
```

Projections run synchronously inside the emit transaction. If they raise,
the entire emit rolls back — the event row isn't written, reactors don't
fire, base handlers don't fire.

Projections register themselves with Acta the first time their class is
loaded (via `Class.inherited`). Acta's Railtie eagerly loads everything
under `app/projections`, `app/handlers`, and `app/reactors` on each
`config.to_prepare`, so subscribers are wired up before the first request
— including in dev mode where Zeitwerk would otherwise wait until
something explicitly references the constant. If your subscribers live
elsewhere, point Acta at them:

```ruby
# config/application.rb
config.acta.projection_paths = %w[app/projections app/read_models]
config.acta.handler_paths    = %w[app/handlers]
config.acta.reactor_paths    = %w[app/reactors]
```

Set a path list to `[]` to disable auto-loading and manage subscriber
lifecycle yourself.

Replay at any time:

```ruby
Acta.rebuild!
```

Each projection's `truncate!` runs, then the log is replayed through
projections. Reactors are skipped during replay (replay is a state
operation, not a notification one).

#### Guarding projection-owned tables

Once a model is maintained by a projection, *every* other write path
(controllers, console one-offs, rake tasks, callbacks on other models)
silently breaks the event log as the source of truth. Opt into a runtime
guard with `acta_managed!`:

```ruby
class Order < ApplicationRecord
  acta_managed!   # writes outside an Acta::Projection raise ProjectionWriteError
end
```

Inside an `Acta::Projection` `on EventClass do |e| ... end` block (and
during `Acta.rebuild!`'s truncate phase), `Acta::Projection.applying?`
is true and writes pass through. From a controller, console, or
unrelated callback, they raise:

```ruby
Order.update_all(status: "cancelled")
# raise: Acta::ProjectionWriteError — Order is acta_managed!
#        Emit an event so the projection can update the row, or wrap
#        intentional out-of-band writes in
#        `Acta::Projection.applying! { ... }` (fixtures, migrations,
#        backfills).
```

For incremental migration, demote violations to warnings:

```ruby
acta_managed! on_violation: :warn
```

Test fixtures, data migrations, and one-off backfills can wrap
intentional out-of-band writes in `Acta::Projection.applying! { ... }`
to bypass the safety net explicitly.

### 5. Commands for validated writes

```ruby
# app/commands/place_order.rb
class PlaceOrder < Acta::Command
  param :customer_id, :string
  param :total_cents, :integer

  validates :customer_id, :total_cents, presence: true
  validates :total_cents, numericality: { greater_than: 0 }

  def call
    order_id = "order_#{SecureRandom.uuid}"
    emit OrderPlaced.new(order_id:, customer_id:, total_cents:)
  end
end

cmd = PlaceOrder.call(customer_id: "c_1", total_cents: 4200)
cmd.emitted_events.first.order_id   # => "order_…"
```

`Acta::Command.call` returns the command instance. The instance carries
the params, the `emitted_events` array (every event emitted during
`#call`, in order), and any state the command exposed via
`attr_reader`. Callers that don't care about the events ignore the
return value:

```ruby
PlaceOrder.call(customer_id: "c_1", total_cents: 4200)
```

Commands can emit zero, one, or many events. The framework does not
invent a "primary" event — when a command emits more than one, the
caller (who knows the domain) picks what matters from
`cmd.emitted_events`.

### Optimistic locking (high-water mark)

Every stream has a high-water mark — the `stream_sequence` of its most
recent event. `Acta.version_of` reads it; `Acta.emit(..., if_version: N)`
asserts it. Use the pair when you need optimistic locking against
concurrent writers to the same aggregate:

```ruby
class RenameOrder < Acta::Command
  param :order_id, :string
  param :new_name, :string

  def call
    version = Acta.version_of(stream_type: :order, stream_key: order_id)
    # ... do work that depends on the current state ...
    emit OrderRenamed.new(order_id:, new_name:), if_version: version
  end
end
```

If another writer has appended to the stream between `version_of` and
`emit`, the emit raises `Acta::VersionConflict` — callers retry with
fresh state or surface the collision instead of silently clobbering it.
`if_version: 0` asserts a fresh stream (no events yet). Most commands
don't need this; reach for it when concurrent writes to the same
aggregate are realistic and lost-update would be a bug.

## Identity: generate IDs in commands, never in projections

For event-sourced aggregates, aggregate IDs (typically UUIDs) must be
stable across `Acta.rebuild!` and must not drift if the projected tables
are truncated. The rule: **the command generates the ID once, the event
carries it in its payload, and the projection reads it back out**.

```ruby
class CreateOrder < Acta::Command
  param :customer_id, :string
  param :total_cents, :integer

  def call
    order_id = "order_#{SecureRandom.uuid}"    # generated here, once, forever
    emit OrderCreated.new(order_id:, customer_id:, total_cents:)
  end
end

class OrderCreated < Acta::Event
  stream :order, key: :order_id
  attribute :order_id, :string
  attribute :customer_id, :string
  attribute :total_cents, :integer
end

class OrderProjection < Acta::Projection
  on OrderCreated do |event|
    Order.insert!(id: event.order_id, customer_id: event.customer_id, ...)
  end
end
```

When `Acta.rebuild!` runs, it calls `OrderProjection.truncate!` (wiping
the `orders` table) and replays every event. The projection reads
`event.order_id` — which was written at the original command call — and
re-inserts the row with the same ID. **Rebuild never regenerates IDs.**

### What to avoid

- **Generating IDs in projection code.** Non-deterministic — every
  rebuild produces new IDs, orphaning any foreign references.
  `SecureRandom` / `Time.current` / anything stateful has no place in a
  projection.
- **Generating IDs in the event class's `initialize`.** Same problem:
  if the event assigns a default ID when reconstructed from a row, old
  events would decode with fresh IDs. Events should take an explicit
  `order_id:` attribute and require it in the payload.
- **Dropping the events table.** The event log is the primary source
  of IDs. Purging it regenerates all IDs on next write. Back it up and
  treat it as production-critical — even more so if other systems (a
  separate user DB, external services) reference your aggregates' IDs.

### Why this matters

If anything outside the event-sourced aggregate references an ID —
`ratings.wine_id` in a separate user database, a webhook payload sent to
a third party, a URL that users have bookmarked — that reference must
stay valid across rebuilds. Keeping IDs in the event payload guarantees
it without any special deterministic-UUID schemes.

## Event payloads with nested models

Payloads can carry arbitrary nested structures — either payload-only
`Acta::Model` classes or ActiveRecord classes that include
`Acta::Serializable`.

```ruby
# payload-only class
class LineItem < Acta::Model
  attribute :sku, :string
  attribute :quantity, :integer
  attribute :price_cents, :integer
end

# existing AR class — opt in as a payload type
class Address < ApplicationRecord
  include Acta::Serializable
  acta_serialize except: [:created_at, :updated_at]
end

class OrderSubmitted < Acta::Event
  stream :order, key: :order_id

  attribute :order_id, :string
  attribute :shipping_address, Address       # AR + Serializable
  attribute :items, array_of: LineItem       # Array<Acta::Model>
  attribute :tags, array_of: String
end
```

When embedded, AR instances are **snapshots**: `event.shipping_address.street`
returns the value at emit time, regardless of later changes. For the
current row, call `Address.find(event.shipping_address.id)`.

## Testing

```ruby
# spec_helper.rb (or equivalent)
require "acta/testing"
require "acta/testing/matchers"

RSpec.configure do |config|
  Acta::Testing.default_actor!(config)
  config.include Acta::Testing::DSL

  config.around(:each, :active_record) do |example|
    Acta::Testing.test_mode { example.run }
  end
end
```

### Default actor

`Acta.emit` requires `Acta::Current.actor` to be set — every event needs
a known author. `Acta::Testing.default_actor!(config)` adds a
`before(:each)` that sets a default `system / rspec / test` actor and an
`after(:each)` that resets it, so specs (and the commands they call)
don't trip `Acta::MissingActor`. Override any attribute to match your
project's vocabulary:

```ruby
Acta::Testing.default_actor!(config, type: "user", id: "test-user-1", source: "spec")
```

For an individual example that needs to attribute emissions to a
specific actor, scope an override with `with_actor`:

```ruby
include Acta::Testing::DSL

it "records the user as the actor" do
  with_actor(type: "user", id: user.id, source: "web") do
    PlaceOrder.call(...)
  end

  expect(Acta::Record.last.actor_id).to eq(user.id)
end
```

`with_actor` restores the surrounding actor when the block returns or
raises.

### RSpec matchers

```ruby
expect { PlaceOrder.call(order_id: "o_1", customer_id: "c_1", total_cents: 4200) }
  .to emit(OrderPlaced).with(total_cents: 4200)

expect { some_noop }.not_to emit_any_events

expect { batched_import }
  .to emit_events([OrderPlaced, OrderPlaced, OrderPlaced])
```

### Given/when/then DSL

```ruby
include Acta::Testing::DSL

it "ships an order" do
  given_events do
    Acta.emit(OrderPlaced.new(order_id: "o_1", customer_id: "c_1", total_cents: 4200))
  end

  when_command ShipOrder.new(order_id: "o_1", tracking: "TRK123")

  then_emitted OrderShipped, order_id: "o_1"
  then_emitted_nothing_else
end
```

Fixtures become narratives — prior state is declared as events, which
mirrors how state actually accumulates in an event-sourced system.

### Replay determinism check

```ruby
it "projects deterministically" do
  # ... emit some events ...
  ensure_replay_deterministic { Order.all.pluck(:id, :status) }
end
```

Catches the common projection bugs (Time.current, rand, external API
calls) better than code review ever will.

## Observability

Hook into `ActiveSupport::Notifications` for metrics, tracing, and
request correlation:

- `acta.event_emitted` — `{ event, event_type }`
- `acta.projection_applied` — `{ event, projection_class }`
- `acta.reactor_invoked` — `{ event, reactor_class, sync: true }`
- `acta.reactor_enqueued` — `{ event, reactor_class }`

## Development

```bash
bin/setup                  # install dependencies
bundle exec rspec          # run the test suite (SQLite + Postgres if available)
bundle exec rake           # tests + rubocop
```

The Postgres adapter tests run if a local Postgres instance is reachable.
Configure via environment variables:

```
ACTA_PG_DATABASE=acta_test
ACTA_PG_HOST=localhost
ACTA_PG_PORT=5432
ACTA_PG_USER=$USER
ACTA_PG_PASSWORD=
```

## License

MIT. See [LICENSE](LICENSE).
