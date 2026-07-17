# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.rebuild! with upcasters", :active_record do
  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
    Acta::Current.actor = Acta::Actor.new(type: "system", id: "rspec", source: "test")

    item_added = Class.new(Acta::Event) do
      attribute :item_id, :string
      attribute :title, :string
      validates :item_id, :title, presence: true
    end
    stub_const("ItemAdded", item_added)

    workspace_created = Class.new(Acta::Event) do
      attribute :workspace_id, :string
      attribute :title, :string
      validates :workspace_id, :title, presence: true
    end
    stub_const("WorkspaceCreated", workspace_created)
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta.reset_upcasters!
  end

  it "routes a renamed event through the new type's projection on rebuild" do
    items = []
    workspaces = []

    stub_const("ItemProjection", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { items.clear }
      on(ItemAdded) { |e| items << e.item_id }
    end)
    stub_const("WorkspaceProjection", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { workspaces.clear }
      on(WorkspaceCreated) { |e| workspaces << e.workspace_id }
    end)

    Acta.emit(ItemAdded.new(item_id: "g_1", title: "Goal one"))
    Acta.emit(ItemAdded.new(item_id: "i_2", title: "Item two"))

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |event, _ctx|
        if event.payload["item_id"].start_with?("g_")
          event.upcast_to(
            type: "WorkspaceCreated",
            payload: { "workspace_id" => event.payload["item_id"], "title" => event.payload["title"] },
            schema_version: 2
          )
        else
          event.upcast_to(schema_version: 2)
        end
      end
    end)

    Acta.rebuild!

    expect(items).to eq([ "i_2" ])
    expect(workspaces).to eq([ "g_1" ])
  end

  it "carries upcaster context across the whole replay pass" do
    workspace_parents = {}

    stub_const("WorkspaceTrackingProjection", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { workspace_parents.clear }
      on ItemAdded do |e|
        workspace_parents[e.item_id] = e.title  # title carries the resolved workspace
      end
    end)

    Acta.emit(ItemAdded.new(item_id: "g_root", title: "root"))
    Acta.emit(ItemAdded.new(item_id: "child_a", title: "unresolved"))
    Acta.emit(ItemAdded.new(item_id: "child_b", title: "unresolved"))

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |event, ctx|
        payload = event.payload
        if payload["item_id"].start_with?("g_")
          ctx[:goals][payload["item_id"]] = payload["item_id"]
          event.upcast_to(schema_version: 2)
        else
          resolved = ctx[:goals].keys.first
          event.upcast_to(payload: payload.merge("title" => "under:#{resolved}"), schema_version: 2)
        end
      end
    end)

    Acta.rebuild!

    expect(workspace_parents).to eq(
      "g_root" => "root",
      "child_a" => "under:g_root",
      "child_b" => "under:g_root"
    )
  end

  it "drops events when the upcaster returns nil" do
    seen = []
    stub_const("DropProjection", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { seen.clear }
      on(ItemAdded) { |e| seen << e.item_id }
    end)

    Acta.emit(ItemAdded.new(item_id: "keep_1", title: "k"))
    Acta.emit(ItemAdded.new(item_id: "drop_1", title: "d"))
    Acta.emit(ItemAdded.new(item_id: "keep_2", title: "k"))

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |event, _ctx|
        if event.payload["item_id"].start_with?("drop_")
          nil
        else
          event.upcast_to(schema_version: 2)
        end
      end
    end)

    Acta.rebuild!
    expect(seen).to eq([ "keep_1", "keep_2" ])
  end

  it "propagates ReplayHaltedByUpcaster up through rebuild! (not wrapped in ReplayError)" do
    Acta.emit(ItemAdded.new(item_id: "x", title: "x"))

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |_event, ctx|
        ctx.fail_replay!("intentional halt")
      end
    end)

    expect { Acta.rebuild! }.to raise_error(Acta::ReplayHaltedByUpcaster, /intentional halt/)
  end

  it "stays deterministic — two rebuild! passes produce the same projection state" do
    items = []
    workspaces = []
    stub_const("ItemDetProj", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { items.clear }
      on(ItemAdded) { |e| items << e.item_id }
    end)
    stub_const("WorkspaceDetProj", Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { workspaces.clear }
      on(WorkspaceCreated) { |e| workspaces << e.workspace_id }
    end)

    Acta.emit(ItemAdded.new(item_id: "g_1", title: "G"))
    Acta.emit(ItemAdded.new(item_id: "i_2", title: "I"))

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |event, _|
        if event.payload["item_id"].start_with?("g_")
          event.upcast_to(
            type: "WorkspaceCreated",
            payload: { "workspace_id" => event.payload["item_id"], "title" => event.payload["title"] },
            schema_version: 2
          )
        else
          event.upcast_to(schema_version: 2)
        end
      end
    end)

    Acta.rebuild!
    first_items = items.dup
    first_workspaces = workspaces.dup

    Acta.rebuild!

    expect(items).to eq(first_items)
    expect(workspaces).to eq(first_workspaces)
  end

  describe "EventsQuery context semantics" do
    let(:stateful_upcaster) do
      Module.new do
        include Acta::Upcaster

        upcasts "ItemAdded", from: 1, to: 2 do |event, ctx|
          payload = event.payload
          if payload["item_id"].start_with?("g_")
            ctx[:roots][payload["item_id"]] = payload["item_id"]
            event.upcast_to(schema_version: 2)
          else
            resolved = ctx[:roots].keys.first
            event.upcast_to(
              payload: payload.merge("title" => "under:#{resolved || 'unknown'}"),
              schema_version: 2
            )
          end
        end
      end
    end

    before do
      stub_const("StatefulUpcaster", stateful_upcaster)
      Acta.register_upcaster(StatefulUpcaster)

      Acta.emit(ItemAdded.new(item_id: "g_root", title: "root"))
      Acta.emit(ItemAdded.new(item_id: "child_a", title: "raw"))
      Acta.emit(ItemAdded.new(item_id: "child_b", title: "raw"))
    end

    it "shares one context across EventsQuery#all so stateful upcasters resolve correctly" do
      titles = Acta.events.all.map(&:title)
      expect(titles).to eq([ "root", "under:g_root", "under:g_root" ])
    end

    it "shares one context across EventsQuery#each (via #all)" do
      collected = []
      Acta.events.each { |e| collected << e.title }
      expect(collected).to eq([ "root", "under:g_root", "under:g_root" ])
    end

    it "uses a fresh context for single-record reads — stateful resolution is intentionally incomplete" do
      # find_by_uuid on a descendant in isolation cannot see the root's
      # context, so the upcaster's stateful lookup misses. Documented as
      # the expected single-record semantic, not a bug.
      uuid = Acta::Record.where(event_type: "ItemAdded").offset(1).limit(1).pluck(:uuid).first
      event = Acta.events.find_by_uuid(uuid)

      expect(event.title).to eq("under:unknown")
    end
  end

  it "leaves base handlers and reactors out of replay (existing contract holds)" do
    handler_hits = 0
    reactor_hits = 0

    stub_const("MyHandler", Class.new(Acta::Handler) do
      on(ItemAdded) { |_e| handler_hits += 1 }
    end)
    stub_const("MyReactor", Class.new(Acta::Reactor) do
      sync!
      on(ItemAdded) { |_e| reactor_hits += 1 }
    end)

    Acta.emit(ItemAdded.new(item_id: "a", title: "a"))
    expect(handler_hits).to eq(1)
    expect(reactor_hits).to eq(1)

    Acta.register_upcaster(Module.new do
      include Acta::Upcaster
      upcasts "ItemAdded", from: 1, to: 2 do |e, _|
        e.upcast_to(schema_version: 2)
      end
    end)

    Acta.rebuild!

    # No additional hits during replay.
    expect(handler_hits).to eq(1)
    expect(reactor_hits).to eq(1)
  end
end
