# frozen_string_literal: true

require "active_support"
require "active_support/current_attributes"

module Acta
  class Current < ActiveSupport::CurrentAttributes
    attribute :actor
  end
end
