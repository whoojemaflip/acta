# frozen_string_literal: true

require "rails/engine"

module Acta
  module Web
    class Engine < ::Rails::Engine
      engine_name "acta_web"
      isolate_namespace Acta::Web
    end
  end
end
