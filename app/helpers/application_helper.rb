# frozen_string_literal: true

module ApplicationHelper
  include Heroicon::Engine.helpers

  def flash_class(flash_type)
    case flash_type.to_sym
    when :notice, :success
      "bg-status-success-light text-status-success"
    when :error, :alert
      "bg-status-danger-light text-status-danger"
    when :warning
      "bg-status-warning-light text-status-warning"
    else
      "bg-status-info-light text-status-info"
    end
  end

  def flash_icon(flash_type)
    case flash_type.to_sym
    when :notice, :success
      heroicon "check-circle", options: { class: "h-5 w-5" }
    when :error, :alert
      heroicon "x-circle", options: { class: "h-5 w-5" }
    when :warning
      heroicon "exclamation-triangle", options: { class: "h-5 w-5" }
    else
      heroicon "information-circle", options: { class: "h-5 w-5" }
    end
  end

  # Standardized Page Header Helpers
  def page_header(title:, subtitle: nil, breadcrumbs: nil, search: nil, actions: nil)
    render "shared/page_header",
           title: title,
           subtitle: subtitle,
           breadcrumbs: breadcrumbs,
           search: search,
           actions: actions
  end

  def standard_action_button(label:, url:, icon: nil, style: :primary, method: nil, confirm: nil)
    classes = case style
              when :primary
                primary_button_classes
              when :secondary
                secondary_button_classes
              when :danger
                danger_button_classes
              else
                style.to_s
              end

    result = {
      label: label,
      url: url,
      icon: icon,
      class: classes
    }
    result[:method] = method if method
    result[:confirm] = confirm if confirm
    result
  end

  def breadcrumb_trail(*crumbs)
    crumbs.map do |crumb|
      case crumb
      when String
        { label: crumb }
      when Array
        { label: crumb.first, url: crumb.last }
      when Hash
        crumb
      end
    end
  end

  def current_month_year?
    selected_month == Date.current.month && selected_year == Date.current.year
  end

  def format_month_year(month: nil, year: nil)
    month ||= selected_month
    year ||= selected_year
    Date.new(year, month, 1).strftime("%B %Y")
  end

  # NOTE: Month/year are stored in session by DateContext and URLs are cleaned via redirect.
  # If a link or form needs to change the visible month, pass :month and :year explicitly;
  # DateContext will update session then redirect to a clean URL without those params.

  private

  def primary_button_classes
    "inline-flex items-center gap-2 px-4 py-2 rounded bg-brand text-white text-sm font-medium hover:bg-brand-dark shadow-sm transition"
  end

  def secondary_button_classes
    "inline-flex items-center gap-2 px-4 py-2 rounded border border-gray-300 bg-white text-gray-700 text-sm font-medium hover:bg-gray-50 shadow-sm transition"
  end

  def danger_button_classes
    "inline-flex items-center gap-2 px-4 py-2 rounded bg-status-danger text-white text-sm font-medium hover:opacity-90 shadow-sm transition"
  end
end
