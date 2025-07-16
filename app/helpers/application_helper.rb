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

  # Generate a sortable table header link
  def sortable_header(column, title, current_sort: nil, current_direction: nil)
    # Determine if this column is currently being sorted
    is_current = current_sort == column.to_s
    
    # Toggle direction: if current column, flip direction; otherwise default to asc
    new_direction = if is_current && current_direction == 'asc'
                      'desc'
                    else
                      'asc'
                    end
    
    # Build the URL with preserved search parameters
    url_params = request.query_parameters.merge(sort: column, direction: new_direction)
    
    link_to entries_path(url_params), 
            class: "group flex items-center space-x-2 hover:text-brand hover:bg-gray-100 px-2 py-1 rounded transition-all duration-200" do
      content_tag(:span, title, class: "font-medium") +
      content_tag(:div, class: "sort-icon flex items-center") do
        if is_current
          if current_direction == 'desc'
            # Down arrow (desc)
            heroicon "chevron-down", options: { class: "w-5 h-5 text-brand" }
          else
            # Up arrow (asc)
            heroicon "chevron-up", options: { class: "w-5 h-5 text-brand" }
          end
        else
          # Neutral sort icon - up/down arrows
          heroicon "chevron-up-down", options: { class: "w-5 h-5 text-gray-300 group-hover:text-gray-400" }
        end
      end
    end
  end

  # Standardized Page Header Helpers
  def page_header(title:, subtitle: nil, breadcrumbs: nil, search: nil, actions: nil)
    render 'shared/page_header',
           title: title,
           subtitle: subtitle,
           breadcrumbs: breadcrumbs,
           search: search,
           actions: actions
  end

  def standard_action_button(label:, url:, icon: nil, style: :primary)
    classes = case style
              when :primary
                "inline-flex items-center gap-x-2 rounded-md bg-gradient-to-r from-brand to-brand-dark px-4 py-2.5 text-sm font-semibold text-white shadow-sm hover:from-brand-dark hover:to-brand-dark focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-brand transition-all duration-300"
              when :secondary
                "inline-flex items-center gap-x-2 rounded-md bg-white px-4 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 transition-colors duration-200"
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
end
