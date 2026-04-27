# frozen_string_literal: true

module Acta
  module Web
    class ApplicationController < Acta::Web.base_controller_class.constantize
      layout "acta/web/application"
      helper Acta::Web::ApplicationHelper
    end
  end
end
