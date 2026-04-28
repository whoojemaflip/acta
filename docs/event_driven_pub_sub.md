# Event-driven pub/sub

The simplest useful shape for an Acta app: one domain event, multiple
independent subscribers, no event sourcing. The event is the
publication; reactors are the subscribers; the events table is your
audit log for free.

## The scenario

A user signs up. As a result, several independent things should
happen:

- A welcome email is sent.
- An analytics service is pinged.
- The signup is recorded in an audit log.

These concerns have different owners, change at different rates, and
fail in different ways. Coupling them in the controller (or worse, in
an `after_create_commit` callback on the `User` model) means every
new concern requires editing the same file, and a flaky third-party
analytics call can roll back the user creation.

With Acta:

```ruby
# app/events/user_signed_up.rb
class UserSignedUp < Acta::Event
  stream :user, key: :user_id

  attribute :user_id, :string
  attribute :email, :string
  attribute :referral_code, :string

  validates :user_id, :email, presence: true
end
```

The signup path creates the AR record and emits the event in the
same transaction:

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  def create
    ApplicationRecord.transaction do
      user = User.create!(user_params)

      Acta.emit(UserSignedUp.new(
        user_id:       user.id,
        email:         user.email,
        referral_code: params[:referral_code]
      ))
    end

    redirect_to dashboard_path
  end
end
```

The explicit `transaction` block is the load-bearing detail. `Acta.emit`
opens its own inner transaction (with `requires_new: true`), which
becomes a savepoint inside the outer one — so either the user row
*and* the event row commit together, or neither does. Without the
outer transaction these would be two independent commits, and a
process crash or event validation error between them would leave
you with a user who has no audit trail, no welcome email, and no
analytics ping.

That's it for the publisher. Each subscriber lives in its own file,
declares what it cares about, and ignores everything else.

## Subscribers

```ruby
# app/reactors/welcome_email_reactor.rb
class WelcomeEmailReactor < Acta::Reactor
  on UserSignedUp do |event|
    UserMailer.welcome(event.user_id).deliver_later
  end
end
```

```ruby
# app/reactors/analytics_reactor.rb
class AnalyticsReactor < Acta::Reactor
  on UserSignedUp do |event|
    AnalyticsClient.track(
      user_id: event.user_id,
      event:   "signup",
      props:   { referral_code: event.referral_code }
    )
  end
end
```

The audit log subscriber doesn't exist as code — Acta writes every
emitted event to the `events` table by default. Browse it at `/acta`
(see the [Acta::Web engine][acta-web]) or query directly via
`Acta.events`.

[acta-web]: ../README.md#acta-web

## What just happened

Each reactor runs **after** the database commit that wrote the event,
**asynchronously** by default (via ActiveJob). So:

- Because the controller wraps both writes in
  `ApplicationRecord.transaction`, the user row and the event row
  commit together. If either raises, neither is persisted — no
  welcome email to a user that doesn't exist.
- Each reactor enqueues its own job. The welcome email and the
  analytics ping run in parallel, isolated from each other.
- A failing analytics call doesn't roll back the signup, doesn't
  block the email, doesn't surface to the user. ActiveJob's retry
  semantics apply per-reactor.
- New subscribers are additive. To send a referral credit when a
  signup uses a code, write a third reactor — no change to the
  controller, the event, or the existing reactors.

### A subtle caveat about reactor enqueue timing

Reactors are dispatched after Acta's inner savepoint releases but
*before* the outer transaction commits. Whether that opens a
"reactor fired but the user write rolled back" window depends on
your ActiveJob queue adapter:

- **DB-backed queues** (Solid Queue, GoodJob, Que) — the enqueue is
  a row insert that participates in the outer transaction. A
  rollback un-enqueues the job. Atomic.
- **Redis-backed queues** (Sidekiq) — the enqueue hits Redis
  immediately and survives a rollback. Small window where the email
  goes out but the user doesn't exist. Rails 7.2+ exposes
  `enqueue_after_transaction_commit` to opt into deferred enqueue,
  which closes the window.
- **Sync reactors** (`sync!`) — run inline during dispatch. Side
  effects (email sent, third-party API called) happen before the
  outer commits and can't be undone by a rollback. Reach for
  `sync!` only when the side effect is itself a DB write inside the
  same transaction, or when "fired but rolled back" is acceptable.

On the Rails 8.x + Solid Queue default stack, the right behaviour
falls out without extra configuration.

## Synchronous when you need it

For tests and the rare side effect that must happen inside the same
request, opt a reactor into sync mode:

```ruby
class CreateBillingAccountReactor < Acta::Reactor
  sync!

  on UserSignedUp do |event|
    BillingAccount.create!(user_id: event.user_id, plan: "free")
  end
end
```

Sync reactors run **after-commit but in the caller's thread**. They
still don't block the DB transaction (so they can't roll the signup
back), but they do block the response. Reach for this when the
follow-up state must exist before the next user action — and only
then.

## Testing

Reactor tests usually just want to assert that a side effect was
triggered. Use the matchers:

```ruby
require "acta/testing"
require "acta/testing/matchers"

RSpec.describe RegistrationsController do
  it "publishes UserSignedUp on successful signup" do
    expect {
      post :create, params: { user: { email: "alice@example.com" } }
    }.to emit(UserSignedUp).with(email: "alice@example.com")
  end
end
```

For the reactor itself, run it inline so the side effect actually
fires:

```ruby
RSpec.describe WelcomeEmailReactor do
  it "sends the welcome email" do
    Acta::Testing.test_mode do
      Acta.emit(UserSignedUp.new(user_id: "u_1", email: "alice@example.com"))
    end

    expect(UserMailer.deliveries.last.to).to eq([ "alice@example.com" ])
  end
end
```

`Acta::Testing.test_mode` runs reactors inline for the duration of
the block, regardless of the `sync!` declaration on the class. It
keeps reactor tests synchronous without committing the whole reactor
to sync mode in production.

## When this isn't the right shape

This pattern works when the AR records (`User`, `BillingAccount`) are
the source of truth and the events are notifications about state
changes happening elsewhere. It does **not** make the event log the
authoritative source of state — `User.create!` happens before any
event is emitted, and dropping the events table doesn't recreate
users on the next `Acta.rebuild!`.

When you want the events to *be* the source of truth — when
`Acta.rebuild!` should reproduce the projected state from the log
alone — reach for projections instead. See the [event sourcing][es]
pattern.

[es]: ../README.md#4-project-state-event-sourced

## Compared to the alternatives

| | AR callbacks | `ActiveSupport::Notifications` | [Wisper][wisper] | Acta event-driven |
|---|---|---|---|---|
| Persistence | None | None | None | Yes — full payload, actor, timestamps |
| Async by default | No (in tx) | No (in caller) | No (in caller); async via wisper-sidekiq | Yes (ActiveJob) |
| Failure isolation | No (rolls back tx) | Sometimes | Subscriber errors propagate to publisher | Yes (per-reactor jobs) |
| Replay-able | No | No | No | Yes (the events are still there) |
| Payload typing | AR attributes | Untyped hash | Untyped args | ActiveModel-typed attributes with validations |
| Subscriber discovery | Reading the model file | Grep the codebase for `subscribe` | Subscriber registration code | `app/reactors/` directory |
| Test ergonomics | Stubs all the way down | Subscribe a block in spec | wisper-rspec matchers | Built-in matchers + `test_mode` |

[wisper]: https://github.com/krisleech/wisper

`ActiveSupport::Notifications` is the in-process, ephemeral cousin —
fire-and-forget, no persistence, ideal for instrumentation (metrics,
traces, logs) but a poor fit for domain events that other parts of
the system need to react to.

**Wisper** is the long-standing prior art for Rails domain pub/sub —
publish a symbol-named event, subscribers register interest, the
gem dispatches. It's at v3.0.0 (May 2024) with light ongoing
maintenance; not abandoned, not actively developed either. Reach for
Wisper when you want to decouple callbacks without buying into
event sourcing or a persistent log: subscriptions are dynamic,
events are untyped (any args you want), and the runtime is
process-local. Acta differs in three load-bearing ways: events are
**typed classes** with validated payload schemas (so a typo in a
field name is a class-load error, not a runtime nil); subscribers
are **after-commit + async** by default (so a flaky external API
call doesn't roll back the publisher's transaction); and every
publication is **persisted** in the events table (so you have an
audit log, can replay history, and can survive a process restart
mid-flight on a notification).

The honest summary: AS::Notifications for instrumentation, Wisper
for lightweight in-process pub/sub without persistence, Acta when
the publication itself needs to be durable and the subscribers are
fan-out side effects you want isolated from the request path.
