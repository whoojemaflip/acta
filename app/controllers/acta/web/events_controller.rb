# frozen_string_literal: true

module Acta
  module Web
    class EventsController < ApplicationController
      PER_PAGE = 40

      def index
        @base_count = Acta::Record.count

        @facet_event_type = Acta::Record.group(:event_type).count.sort_by { |_, n| -n }.to_h
        @facet_stream_type = Acta::Record.group(:stream_type).count.sort_by { |_, n| -n }.to_h
        @facet_actor_id = Acta::Record.group(:actor_id).count.sort_by { |_, n| -n }.to_h

        @events_scope = filtered_scope
        @filtered_count = @events_scope.count

        @page = [params[:page].to_i, 0].max
        @total_pages = [(@filtered_count / PER_PAGE.to_f).ceil, 1].max
        @page = [@page, @total_pages - 1].min

        @events = @events_scope.order(id: :desc).offset(@page * PER_PAGE).limit(PER_PAGE)

        @selected_event = Acta::Record.find_by(uuid: params[:selected]) if params[:selected].present?

        @active_filters = {
          event_type: params[:event_type],
          stream_type: params[:stream_type],
          actor_id: params[:actor_id],
          stream_key: params[:stream_key],
          q: params[:q],
        }.compact_blank
      end

      def show
        @event = Acta::Record.find_by!(uuid: params[:id])
      end

      private

      def filtered_scope
        scope = Acta::Record.all

        scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
        scope = scope.where(stream_type: params[:stream_type]) if params[:stream_type].present?
        scope = scope.where(actor_id: params[:actor_id]) if params[:actor_id].present?

        if params[:stream_key].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:stream_key])
          scope = scope.where("stream_key LIKE ?", "%#{sanitized}%")
        end

        if params[:q].present?
          sanitized = ActiveRecord::Base.sanitize_sql_like(params[:q])
          q = "%#{sanitized}%"
          scope = scope.where(
            "event_type LIKE :q OR stream_type LIKE :q OR stream_key LIKE :q OR actor_id LIKE :q OR source LIKE :q",
            q: q
          )
        end

        scope
      end
    end
  end
end
