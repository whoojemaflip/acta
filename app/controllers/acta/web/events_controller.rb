# frozen_string_literal: true

require "acta/web/events_query"

module Acta
  module Web
    class EventsController < ApplicationController
      PER_PAGE = 40

      def index
        @base_count = Acta::Record.count

        @facet_event_type = Acta::Record.group(:event_type).count.sort_by { |_, n| -n }.to_h
        @facet_stream_type = Acta::Record.group(:stream_type).count.sort_by { |_, n| -n }.to_h
        @facet_actor_id = Acta::Record.group(:actor_id).count.sort_by { |_, n| -n }.to_h

        query = Acta::Web::EventsQuery.new(params)
        @events_scope = query.scope
        @filtered_count = @events_scope.count

        @page = [params[:page].to_i, 0].max
        @total_pages = [(@filtered_count / PER_PAGE.to_f).ceil, 1].max
        @page = [@page, @total_pages - 1].min

        @events = @events_scope.order(id: :desc).offset(@page * PER_PAGE).limit(PER_PAGE)

        @selected_event = Acta::Record.find_by(uuid: params[:selected]) if params[:selected].present?

        @active_filters = query.active_filters
      end

      def show
        @event = Acta::Record.find_by!(uuid: params[:id])
      end
    end
  end
end
