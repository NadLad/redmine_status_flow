module RedmineStatusHistory
  module Patches
    # Exposes the status timeline to Redmine's query engine: five native
    # filters on top of the `last_status_update` column.
    #
    # Everything is expressed as EXISTS/COUNT subqueries on
    # issue_status_histories rather than JOINs. A JOIN multiplies issue rows
    # (one per interval), which silently breaks Redmine's pagination count;
    # a subquery cannot.
    module IssueQueryPatch
      STATUS_CHANGED_TO = 'status_changed_to'.freeze
      STATUS_CHANGED_FROM = 'status_changed_from'.freeze
      STATUS_CHANGED_BETWEEN = 'status_changed_between'.freeze
      TIME_IN_CURRENT_STATUS = 'time_in_current_status'.freeze
      REOPEN_COUNT = 'reopen_count'.freeze

      def self.included(base)
        base.prepend(InstanceMethods)
      end

      module InstanceMethods
        def initialize_available_filters
          super
          add_status_flow_filters
        end

        def sql_for_field(field, operator, value, db_table, db_field, is_custom_filter = false)
          case field
          when STATUS_CHANGED_TO
            status_flow_list_clause(operator, value, 'h.status_id')
          when STATUS_CHANGED_FROM
            status_flow_list_clause(operator, value, 'h.previous_status_id')
          when STATUS_CHANGED_BETWEEN
            sql_for_status_changed_between(operator, value)
          when TIME_IN_CURRENT_STATUS
            sql_for_time_in_current_status(operator, value)
          when REOPEN_COUNT
            sql_for_reopen_count(operator, value)
          else
            super
          end
        end

        protected

        def add_status_flow_filters
          return if available_filters.key?(STATUS_CHANGED_TO)

          status_values = lambda { IssueStatus.sorted.map { |s| [s.name, s.id.to_s] } }

          add_available_filter STATUS_CHANGED_TO, type: :list_status,
                                                 label: :label_status_flow_changed_to,
                                                 values: status_values
          add_available_filter STATUS_CHANGED_FROM, type: :list_status,
                                                   label: :label_status_flow_changed_from,
                                                   values: status_values
          add_available_filter STATUS_CHANGED_BETWEEN, type: :date_past,
                                                      label: :label_status_flow_changed_between
          add_available_filter TIME_IN_CURRENT_STATUS, type: :integer,
                                                      label: :label_status_flow_time_in_current_status
          add_available_filter REOPEN_COUNT, type: :integer,
                                            label: :label_status_flow_reopen_count
          # Kept from the upstream plugin: the date of the latest status change,
          # which is also exposed as a column.
          add_available_filter 'last_status_update', type: :date
        end

        # status_changed_to / status_changed_from: the issue has at least one
        # interval matching the given statuses. The initial interval
        # (journal_id NULL) is not a change, so it never matches either filter.
        def status_flow_list_clause(operator, value, column)
          ids = Array(value).reject(&:blank?).map(&:to_i).uniq
          return operator == '!' ? '1=1' : '1=0' if ids.empty?

          condition = "#{column} IN (#{ids.join(',')})"
          condition += ' AND h.journal_id IS NOT NULL' if column == 'h.status_id'
          exists = status_flow_exists(condition)
          operator == '!' ? "NOT (#{exists})" : exists
        end

        def sql_for_status_changed_between(operator, value)
          dates = Array(value).map { |v| parse_date(v) }
          from, to =
            case operator
            when '=' then [dates[0], dates[0]]
            when '>=' then [dates[0], nil]
            when '<=' then [nil, dates[0]]
            when '><' then [dates[0], dates[1]]
            end

          condition = 'h.journal_id IS NOT NULL'
          if from || to
            bounds = status_flow_time_bounds(from, to)
            if bounds[0]
              condition += " AND h.#{quoted_from_column} >= '#{quoted_time(bounds[0], false)}'"
            end
            if bounds[1]
              condition += " AND h.#{quoted_from_column} <= '#{quoted_time(bounds[1], false)}'"
            end
          end

          exists = status_flow_exists(condition)
          operator == '!*' ? "NOT (#{exists})" : exists
        end

        # time_in_current_status, in days: the age of the interval that is
        # still open (to IS NULL). Comparing a cutoff timestamp against
        # h.from keeps the SQL portable -- no EXTRACT/EPOCH/julianday
        # difference between PostgreSQL, MySQL and SQLite.
        def sql_for_time_in_current_status(operator, value)
          open_interval = "h.#{quoted_to_column} IS NULL"
          return status_flow_exists(open_interval) if operator == '*'
          return "NOT (#{status_flow_exists(open_interval)})" if operator == '!*'

          values = Array(value).map { |v| v.to_s.to_i }
          now = Time.current
          cutoff = ->(days) { quoted_time(status_flow_utc(now - days.days), false) }
          column = "h.#{quoted_from_column}"

          conditions =
            case operator
            when '=' then ["#{column} <= '#{cutoff.call(values[0])}'",
                           "#{column} > '#{cutoff.call(values[0] + 1)}'"]
            when '>=' then ["#{column} <= '#{cutoff.call(values[0])}'"]
            when '<=' then ["#{column} >= '#{cutoff.call(values[0])}'"]
            when '><' then ["#{column} <= '#{cutoff.call(values[0])}'",
                            "#{column} >= '#{cutoff.call(values[1])}'"]
            else return '1=1'
            end

          status_flow_exists(([open_interval] + conditions).join(' AND '))
        end

        # reopen_count: how many times the issue left a closed status for an
        # open one. "Closed" is whatever IssueStatus#is_closed says right now,
        # which is the only definition the data model offers.
        def sql_for_reopen_count(operator, value)
          closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
          count_sql =
            if closed_ids.empty?
              '0'
            else
              list = closed_ids.join(',')
              "(SELECT COUNT(*) FROM #{IssueStatusHistory.table_name} h " \
                "WHERE h.issue_id = #{Issue.table_name}.id " \
                "AND h.previous_status_id IN (#{list}) AND h.status_id NOT IN (#{list}))"
            end

          values = Array(value).map { |v| v.to_s.to_i }
          case operator
          when '=' then "#{count_sql} = #{values[0]}"
          when '>=' then "#{count_sql} >= #{values[0]}"
          when '<=' then "#{count_sql} <= #{values[0]}"
          when '><' then "#{count_sql} BETWEEN #{values[0]} AND #{values[1]}"
          when '*' then "#{count_sql} > 0"
          when '!*' then "#{count_sql} = 0"
          else '1=1'
          end
        end

        def status_flow_exists(condition)
          "EXISTS (SELECT 1 FROM #{IssueStatusHistory.table_name} h " \
            "WHERE h.issue_id = #{Issue.table_name}.id AND #{condition})"
        end

        # `from` and `to` are SQL keywords, so the columns have to be quoted
        # the way the connection expects.
        def quoted_from_column
          Issue.connection.quote_column_name('from')
        end

        def quoted_to_column
          Issue.connection.quote_column_name('to')
        end

        def status_flow_utc(time)
          ActiveRecord.default_timezone == :utc ? time.utc : time
        end

        # Mirrors Query#date_clause: a Date is expanded to the user's time zone
        # before being compared to a timestamp column.
        def status_flow_time_bounds(date_from, date_to)
          from = date_from && date_for_user_time_zone(date_from.year, date_from.month, date_from.day).beginning_of_day
          to = date_to && date_for_user_time_zone(date_to.year, date_to.month, date_to.day).end_of_day
          [from && status_flow_utc(from), to && status_flow_utc(to)]
        end
      end
    end
  end
end
