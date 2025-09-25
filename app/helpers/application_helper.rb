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

  def standard_action_button(label:, url:, icon: nil, style: :primary)
    classes = case style
              when :primary
                primary_button_classes
              when :secondary
                secondary_button_classes
              else
                style.to_s
              end

    {
      label: label,
      url: url,
      icon: icon,
      class: classes
    }
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

  # NOTE: default_url_options (in DateContext) auto-adds month/year to all links,
  # so helpers to manually append those params are no longer needed.

  private

  def primary_button_classes
    [
      "inline-flex items-center gap-x-2 rounded-md bg-gradient-to-r from-brand to-brand-dark",
      "px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:from-brand-dark",
      "hover:to-brand-dark focus-visible:outline focus-visible:outline-2",
      "focus-visible:outline-offset-2 focus-visible:outline-brand transition-all duration-300"
    ].join(" ")
  end

  def secondary_button_classes
    [
      "inline-flex items-center gap-x-2 rounded-md bg-white px-4 py-2.5 text-sm",
      "font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300",
      "hover:bg-gray-50 transition-colors duration-200"
    ].join(" ")
  end
end
