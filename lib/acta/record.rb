# frozen_string_literal: true

require "active_record"

module Acta
  class Record < ActiveRecord::Base
    self.table_name = "events"
    self.inheritance_column = nil
  end
end
