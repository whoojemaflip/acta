# frozen_string_literal: true

module Acta
  class Projection < Handler
    def self.inherited(subclass)
      super
      Acta.register_projection(subclass)
    end

    # Declare the AR classes whose rows this projection owns. Acta uses these
    # declarations both as the default `truncate!` target list and as input to
    # `Acta.rebuild!`'s cross-projection ordering — projections whose tables
    # are FK-referenced by another projection's tables run first, so children
    # are deleted before their parents.
    #
    #   class CatalogProjection < Acta::Projection
    #     truncates Trail, Zone   # within-projection: child first, parent second
    #
    #     on ZoneRegistered { |e| Zone.create!(...) }
    #     on TrailRegistered { |e| Trail.create!(...) }
    #   end
    #
    # Pass classes in safe within-projection order (children before parents);
    # Acta only orders projections relative to each other via the global FK
    # graph, not the within-projection list.
    def self.truncates(*ar_classes)
      @truncated_classes = ar_classes
    end

    def self.truncated_classes
      @truncated_classes ||= []
    end

    # Default implementation deletes every row in each declared class. Apps
    # override `truncate!` directly if they need custom teardown logic; in
    # that case `truncates` still drives FK-based ordering and the override
    # provides the actual deletion.
    def self.truncate!
      truncated_classes.each(&:delete_all)
    end
  end
end
