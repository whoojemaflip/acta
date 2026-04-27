# frozen_string_literal: true

require "rails/engine"
require "action_dispatch" # isolate_namespace references ActionDispatch::Routing

module Acta
  module Web
    class Engine < ::Rails::Engine
      engine_name "acta_web"
      isolate_namespace Acta::Web
    end
  end
end
