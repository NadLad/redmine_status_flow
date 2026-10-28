# frozen_string_literal: true

require 'redmine/export/csv'
require 'redmine/export/pdf'

module RedmineStatusHistory
  # Renders the status history intervals as CSV or PDF. Included in
  # StatusHistoriesController, so the methods below can use `l`, `format_time`,
  # `format_date` and `current_language` from Redmine::I18n.
  #
  # CSV and PDF share the same COLUMNS definition and the same row extractor,
  # so the two formats cannot drift apart. `history_to_csv` and
  # `history_to_pdf` take a preloaded `IssueStatusHistory` relation (see
  # IssueStatusHistory::INTERVAL_PRELOAD) and must never load associations
  # row by row.
  module Export
    # Each entry is [header_key, value_symbol]. A nil header renders the
    # literal `#` (the issue id column), matching Redmine's own export.
    COLUMNS = [
      [nil, :issue_number],
      [:field_tracker, :tracker],
      [:field_subject, :subject],
      [:label_history_status_from, :previous_status],
      [:label_history_status_to, :status],
      [:label_status_flow_export_changed_on, :changed_on],
      [:label_status_flow_export_ended_on, :ended_on],
      [:label_status_flow_export_duration, :duration],
      [:field_author, :author]
    ].freeze

    # Relative column widths for the landscape PDF. The subject column gets
    # most of the page; the id and duration columns are narrow.
    PDF_WEIGHTS = [1, 2, 8, 3, 3, 3, 3, 2, 3].freeze

    def history_to_csv(intervals)
      Redmine::Export::CSV.generate do |csv|
        csv << COLUMNS.map { |key, _| export_header(key) }
        intervals.each { |interval| csv << export_row(interval) }
      end
    end

    def history_to_pdf(intervals, project)
      pdf = Redmine::Export::PDF::ITCPDF.new(current_language, 'L')
      pdf.set_title("#{project} - #{l(:label_history_main_search)}")
      pdf.alias_nb_pages
      pdf.footer_date = format_date(User.current.today)
      pdf.add_page('L')

      page_height = pdf.get_page_height # 210 for landscape A4
      left_margin = pdf.get_original_margins['left']
      right_margin = pdf.get_original_margins['right']
      bottom_margin = pdf.get_footer_margin
      table_width = pdf.get_page_width - left_margin - right_margin
      row_height = 6

      weights = PDF_WEIGHTS
      widths = weights.map { |w| table_width * w / weights.sum }

      render_history_header(pdf, widths, row_height)

      intervals.each do |interval|
        if pdf.get_y + row_height > page_height - bottom_margin
          pdf.add_page('L')
          render_history_header(pdf, widths, row_height)
        end

        pdf.SetFontStyle('', 8)
        export_row(interval).each_with_index do |value, i|
          align = COLUMNS[i][1] == :issue_number ? 'C' : 'L'
          pdf.RDMCell(widths[i], row_height, value.to_s, 1, 0, align)
        end
        pdf.ln
      end

      pdf.output
    end

    private

    def render_history_header(pdf, widths, row_height)
      pdf.SetFontStyle('B', 8)
      pdf.set_fill_color(230, 230, 230)
      COLUMNS.each_with_index do |(key, _), i|
        pdf.RDMCell(widths[i], row_height, export_header(key), 1, 0, 'C', 1)
      end
      pdf.ln
      pdf.set_fill_color(255, 255, 255)
    end

    def export_header(key)
      key.nil? ? '#' : l(key)
    end

    def export_row(interval)
      COLUMNS.map { |_, sym| export_value(interval, sym) }
    end

    def export_value(interval, sym)
      issue = interval.issue
      case sym
      when :issue_number then issue&.id
      when :tracker then issue&.tracker&.name
      when :subject then issue&.subject
      when :previous_status then interval.previous_status&.name
      when :status then interval.status&.name
      when :changed_on then format_time(interval.from)
      when :ended_on then interval.to ? format_time(interval.to) : ''
      when :duration then interval.duration_label
      when :author then interval.user&.name
      end
    end
  end
end
