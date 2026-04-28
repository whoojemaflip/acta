# Acta cookbook

Concrete walkthroughs for the shapes Acta apps actually take. The
main [README](../README.md) documents primitives in isolation; this
folder shows how they compose for specific scenarios, with
end-to-end code and the trade-offs that come with each choice.

## Patterns

- [**Event-driven pub/sub**](event_driven_pub_sub.md) — the simplest
  useful Acta shape. One domain event, multiple independent
  subscribers, no event sourcing. AR records remain the source of
  truth; the events table is a free audit log. Compares against AR
  callbacks and `ActiveSupport::Notifications`.

## Patterns coming later

Recipes will land here when these are written or implemented:

- **Event-sourced aggregates** — projections as the AR view of the
  log; `Acta.rebuild!` as the source-of-truth recovery path. The
  primitive is already documented in the README, but a worked
  example of a full aggregate (command + event + projection +
  replay determinism spec) earns its own page.
- **Process managers (saga)** — coordinating multi-step workflows
  where one event triggers a wait-then-act sequence. Primitive
  tracked in [#27](https://github.com/whoojemaflip/acta/issues/27).
- **Schema evolution with upcasters** — adding, renaming, or
  retiring event attributes without leaving stale rows
  un-deserializable. Primitive tracked in
  [#25](https://github.com/whoojemaflip/acta/issues/25).
