# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Acta.rebuild! truncate ordering", :active_record do
  before(:all) do
    conn = ActiveRecord::Base.connection
    conn.execute("PRAGMA foreign_keys = ON")
    conn.create_table(:zones, force: true) do |t|
      t.string :name
    end
    conn.create_table(:trails, force: true) do |t|
      t.string :name
      t.references :zone, foreign_key: true
    end
    conn.create_table(:ride_efforts, force: true) do |t|
      t.string :name
      t.references :trail, foreign_key: true
    end
    conn.create_table(:trail_aliases, force: true) do |t|
      t.string :alias_name
      t.references :trail, foreign_key: true
    end
  end

  before do
    Acta.reset_adapter!
    Acta.reset_handlers!
    Acta::Current.actor = Acta::Actor.new(type: "system")

    zone_class = Class.new(ActiveRecord::Base) do
      self.table_name = "zones"
    end
    stub_const("Zone", zone_class)

    trail_class = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
      belongs_to :zone
    end
    stub_const("Trail", trail_class)

    ride_effort_class = Class.new(ActiveRecord::Base) do
      self.table_name = "ride_efforts"
      belongs_to :trail
    end
    stub_const("RideEffort", ride_effort_class)

    trail_alias_class = Class.new(ActiveRecord::Base) do
      self.table_name = "trail_aliases"
      belongs_to :trail
    end
    stub_const("TrailAlias", trail_alias_class)
  end

  after do
    Acta::Current.reset
    Acta.reset_adapter!
    Acta.reset_handlers!
    [ TrailAlias, RideEffort, Trail, Zone ].each(&:delete_all) if defined?(Zone)
  end

  it "truncates child-owning projections before parent-owning ones, regardless of registration order" do
    truncated_in_order = []

    catalog = Class.new(Acta::Projection) do
      truncates Trail, Zone
      define_singleton_method(:truncate!) do
        truncated_in_order << :catalog
        Trail.delete_all
        Zone.delete_all
      end
    end
    stub_const("CatalogProjection", catalog)

    ride_effort_proj = Class.new(Acta::Projection) do
      truncates RideEffort
      define_singleton_method(:truncate!) do
        truncated_in_order << :ride_effort
        RideEffort.delete_all
      end
    end
    stub_const("RideEffortProjection", ride_effort_proj)

    trail_alias_proj = Class.new(Acta::Projection) do
      truncates TrailAlias
      define_singleton_method(:truncate!) do
        truncated_in_order << :trail_alias
        TrailAlias.delete_all
      end
    end
    stub_const("TrailAliasProjection", trail_alias_proj)

    Acta.rebuild!

    expect(truncated_in_order.last).to eq(:catalog)
    expect(truncated_in_order).to contain_exactly(:catalog, :ride_effort, :trail_alias)
  end

  it "actually deletes rows that would FK-fail under registration order" do
    Class.new(Acta::Projection) do
      truncates Trail, Zone
    end.tap { |k| stub_const("CatalogP", k) }

    Class.new(Acta::Projection) do
      truncates RideEffort
    end.tap { |k| stub_const("RideEffortP", k) }

    zone = Zone.create!(name: "Cheakamus")
    trail = Trail.create!(name: "AM/PM", zone_id: zone.id)
    RideEffort.create!(name: "ride-1", trail_id: trail.id)

    expect { Acta.rebuild! }.not_to raise_error

    expect(RideEffort.count).to eq(0)
    expect(Trail.count).to eq(0)
    expect(Zone.count).to eq(0)
  end

  it "uses default truncate! (delete_all on each declared class) when no custom override" do
    catalog = Class.new(Acta::Projection) { truncates Trail, Zone }
    stub_const("CatalogDefault", catalog)

    Zone.create!(name: "Cheakamus")
    Trail.create!(name: "AM/PM", zone_id: Zone.first.id)

    catalog.truncate!

    expect(Trail.count).to eq(0)
    expect(Zone.count).to eq(0)
  end

  it "preserves registration order for projections that don't declare `truncates`" do
    invoked = []

    p1 = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { invoked << :one }
    end
    stub_const("LegacyOne", p1)

    p2 = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { invoked << :two }
    end
    stub_const("LegacyTwo", p2)

    Acta.rebuild!

    expect(invoked).to eq([ :one, :two ])
  end

  it "runs legacy projections (no `truncates`) before declared ones" do
    invoked = []

    declared = Class.new(Acta::Projection) do
      truncates Zone
      define_singleton_method(:truncate!) { invoked << :declared }
    end
    stub_const("DeclaredP", declared)

    legacy = Class.new(Acta::Projection) do
      define_singleton_method(:truncate!) { invoked << :legacy }
    end
    stub_const("LegacyP", legacy)

    Acta.rebuild!

    expect(invoked).to eq([ :legacy, :declared ])
  end

  it "ignores belongs_to to a class no projection owns (e.g. an external table)" do
    catalog = Class.new(Acta::Projection) { truncates Trail, Zone }
    stub_const("CatalogExt", catalog)

    expect { Acta.rebuild! }.not_to raise_error
  end

  it "ignores polymorphic belongs_to associations" do
    poly_class = Class.new(ActiveRecord::Base) do
      self.table_name = "trail_aliases"
      belongs_to :commentable, polymorphic: true
    end
    stub_const("PolyTrailAlias", poly_class)

    p1 = Class.new(Acta::Projection) { truncates PolyTrailAlias }
    stub_const("PolyP1", p1)

    expect { Acta.rebuild! }.not_to raise_error
  end

  it "ignores self-referential belongs_to (within-projection ordering is the user's job)" do
    self_ref_trail = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
      belongs_to :parent_trail, class_name: "SelfRefTrail", foreign_key: :zone_id, optional: true
    end
    stub_const("SelfRefTrail", self_ref_trail)

    p1 = Class.new(Acta::Projection) { truncates SelfRefTrail }
    stub_const("SelfRefP", p1)

    expect { Acta.rebuild! }.not_to raise_error
  end

  it "truncates `acta_managed!` AR models without tripping the safety net" do
    # Models marked `acta_managed!` raise ProjectionWriteError on direct
    # delete_all unless wrapped in Projection.applying!. Acta.rebuild!'s
    # truncate phase runs inside that wrapper so the default
    # `truncate!` (which calls delete_all per declared class) works on
    # managed models without further ceremony.
    managed_zone = Class.new(ActiveRecord::Base) do
      self.table_name = "zones"
    end
    stub_const("ManagedZone", managed_zone)
    managed_zone.acta_managed!

    managed_trail = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
      belongs_to :zone, class_name: "ManagedZone"
    end
    stub_const("ManagedTrail", managed_trail)
    managed_trail.acta_managed!

    Class.new(Acta::Projection) { truncates ManagedTrail, ManagedZone }
      .tap { |k| stub_const("ManagedCatalogP", k) }

    ManagedZone.connection.execute("PRAGMA foreign_keys = ON")
    Acta::Projection.applying! do
      zone = ManagedZone.create!(name: "Whistler North")
      ManagedTrail.create!(name: "Lord of the Squirrels", zone_id: zone.id)
    end

    expect { Acta.rebuild! }.not_to raise_error
    expect(ManagedTrail.count).to eq(0)
    expect(ManagedZone.count).to eq(0)
  end

  it "raises Acta::TruncateOrderError when the FK graph has a cycle across projections" do
    cycle_b = Class.new(ActiveRecord::Base) do
      self.table_name = "ride_efforts"
    end
    stub_const("CycleB", cycle_b)

    cycle_a = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
      belongs_to :other, class_name: "CycleB", foreign_key: :zone_id, optional: true
    end
    stub_const("CycleA", cycle_a)

    cycle_b.belongs_to :other, class_name: "CycleA", foreign_key: :trail_id, optional: true

    p_a = Class.new(Acta::Projection) { truncates CycleA }
    stub_const("CycleAP", p_a)

    p_b = Class.new(Acta::Projection) { truncates CycleB }
    stub_const("CycleBP", p_b)

    expect { Acta.rebuild! }.to raise_error(Acta::TruncateOrderError, /CycleAP.+CycleBP|CycleBP.+CycleAP/)
  end
end
