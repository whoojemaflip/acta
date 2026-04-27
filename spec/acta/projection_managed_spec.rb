# frozen_string_literal: true

require "rails_helper"

RSpec.describe Acta::ProjectionManaged, :active_record do
  before(:all) do
    ActiveRecord::Base.connection.create_table(:trails, force: true) do |t|
      t.string :name
    end
    ActiveRecord::Base.connection.create_table(:zones, force: true) do |t|
      t.string :name
    end
  end

  let(:strict_model) do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
      acta_managed!
    end
    stub_const("Trail", klass)
    klass
  end

  let(:warning_model) do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "zones"
      acta_managed! on_violation: :warn
    end
    stub_const("Zone", klass)
    klass
  end

  let(:unmanaged_model) do
    klass = Class.new(ActiveRecord::Base) do
      self.table_name = "trails"
    end
    stub_const("UnmanagedTrail", klass)
    klass
  end

  before do
    Acta.reset_handlers!
    Acta::Current.reset
    ActiveRecord::Base.connection.execute("DELETE FROM trails")
    ActiveRecord::Base.connection.execute("DELETE FROM zones")
  end

  describe "Acta::Projection.applying?" do
    it "is false outside any projection-side scope" do
      expect(Acta::Projection.applying?).to be(false)
    end

    it "is true inside Acta::Projection.applying! { }" do
      flag = nil
      Acta::Projection.applying! { flag = Acta::Projection.applying? }

      expect(flag).to be(true)
    end

    it "restores the previous value after the block (supports nesting)" do
      Acta::Projection.applying! do
        expect(Acta::Projection.applying?).to be(true)
        Acta::Projection.applying! { expect(Acta::Projection.applying?).to be(true) }
        expect(Acta::Projection.applying?).to be(true)
      end

      expect(Acta::Projection.applying?).to be(false)
    end

    it "restores the previous value even when the block raises" do
      expect {
        Acta::Projection.applying! { raise "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(Acta::Projection.applying?).to be(false)
    end
  end

  describe "with on_violation: :raise (default)" do
    it "raises Acta::ProjectionWriteError on .create! outside a projection" do
      expect { strict_model.create!(name: "AM/PM") }
        .to raise_error(Acta::ProjectionWriteError, /Trail.+acta_managed/)
    end

    it "allows .create! inside Acta::Projection.applying! { }" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }

      expect(strict_model.count).to eq(1)
    end

    it "raises on instance #save" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }
      record = strict_model.first
      record.name = "Renamed"

      expect { record.save }.to raise_error(Acta::ProjectionWriteError)
    end

    it "raises on instance #update" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }

      expect { strict_model.first.update(name: "Renamed") }
        .to raise_error(Acta::ProjectionWriteError)
    end

    it "raises on instance #destroy" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }

      expect { strict_model.first.destroy }.to raise_error(Acta::ProjectionWriteError)
    end

    it "raises on instance #update_columns" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }

      expect { strict_model.first.update_columns(name: "Renamed") }
        .to raise_error(Acta::ProjectionWriteError, /update_columns/)
    end

    it "raises on class .update_all" do
      expect { strict_model.update_all(name: "Renamed") }
        .to raise_error(Acta::ProjectionWriteError, /update_all/)
    end

    it "raises on class .delete_all" do
      expect { strict_model.delete_all }
        .to raise_error(Acta::ProjectionWriteError, /delete_all/)
    end

    it "raises on class .insert_all" do
      expect { strict_model.insert_all([ { name: "X" } ]) }
        .to raise_error(Acta::ProjectionWriteError, /insert_all/)
    end

    it "raises on class .upsert_all" do
      expect { strict_model.upsert_all([ { name: "X" } ]) }
        .to raise_error(Acta::ProjectionWriteError, /upsert_all/)
    end

    it "allows reads (find, where, count, etc.) without restriction" do
      Acta::Projection.applying! { strict_model.create!(name: "AM/PM") }

      expect(strict_model.count).to eq(1)
      expect(strict_model.where(name: "AM/PM").count).to eq(1)
      expect(strict_model.first.name).to eq("AM/PM")
    end
  end

  describe "with on_violation: :warn" do
    it "writes to $stderr instead of raising on .create!" do
      expect { warning_model.create!(name: "Cheakamus") }
        .to output(/\[acta\].+Zone.+acta_managed/).to_stderr
        .and(change { warning_model.count }.by(1))
    end

    it "warns on .delete_all but still performs the write" do
      Acta::Projection.applying! { warning_model.create!(name: "Cheakamus") }

      expect { warning_model.delete_all }
        .to output(/\[acta\].+delete_all/).to_stderr
        .and(change { warning_model.count }.from(1).to(0))
    end

    it "is silent inside Acta::Projection.applying!" do
      expect {
        Acta::Projection.applying! { warning_model.create!(name: "Cheakamus") }
      }.not_to output.to_stderr
    end
  end

  describe "without acta_managed! (unmanaged AR models)" do
    it "imposes zero overhead — writes pass through unchanged" do
      expect { unmanaged_model.create!(name: "Free") }.not_to raise_error
      expect { unmanaged_model.update_all(name: "Bulk") }.not_to raise_error
      expect { unmanaged_model.delete_all }.not_to raise_error
    end

    it "acta_managed? returns false" do
      expect(unmanaged_model.acta_managed?).to be(false)
    end
  end

  describe "validation" do
    it "raises ArgumentError on invalid on_violation values" do
      expect {
        Class.new(ActiveRecord::Base) do
          self.table_name = "trails"
          acta_managed! on_violation: :explode
        end
      }.to raise_error(ArgumentError, /on_violation must be one of/)
    end
  end

  describe "integration with projection invocation" do
    let(:event_class) do
      klass = Class.new(Acta::Event) do
        attribute :name, :string
        validates :name, presence: true
      end
      stub_const("TrailRegistered", klass)
      klass
    end

    let(:projection_class) do
      managed = strict_model
      klass = Class.new(Acta::Projection) do
        define_singleton_method(:truncate!) { managed.delete_all }
        on TrailRegistered do |event|
          managed.create!(name: event.name)
        end
      end
      stub_const("TrailProjection", klass)
      klass
    end

    before do
      event_class
      projection_class
      Acta::Current.actor = Acta::Actor.new(type: "system")
    end

    it "lets a projection write to its acta_managed! AR model normally" do
      expect {
        Acta.emit(event_class.new(name: "AM/PM"))
      }.to change { strict_model.count }.from(0).to(1)
    end

    it "Acta.rebuild! truncates and replays without tripping the safety net" do
      Acta.emit(event_class.new(name: "AM/PM"))
      Acta.emit(event_class.new(name: "Microwave Peak"))

      expect { Acta.rebuild! }.not_to raise_error
      expect(strict_model.count).to eq(2)
    end

    it "doesn't allow reactors (which run after-commit) to write to managed tables" do
      reactor = Class.new(Acta::Reactor) do
        sync!
        managed = nil
        define_singleton_method(:set_managed) { |m| managed = m }
        on TrailRegistered do |_e|
          managed.create!(name: "from-reactor")
        end
      end
      reactor.set_managed(strict_model)
      stub_const("TrailReactor", reactor)

      expect {
        Acta.emit(event_class.new(name: "AM/PM"))
      }.to raise_error(Acta::ProjectionWriteError)
    end
  end
end
