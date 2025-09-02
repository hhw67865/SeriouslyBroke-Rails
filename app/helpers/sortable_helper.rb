# frozen_string_literal: true

module SortableHelper
  # Generate a sortable table header link
  def sortable_header(column, title, current_sort: nil, current_direction: nil)
    is_current = current_sort == column.to_s
    new_direction = determine_sort_direction(is_current, current_direction)
    url_params = request.query_parameters.merge(sort: column, direction: new_direction)

    link_to entries_path(url_params), class: sortable_header_classes do
      content_tag(:span, title, class: "font-medium") +
        content_tag(:div, class: "sort-icon flex items-center") do
          sort_icon(is_current, current_direction)
        end
    end
  end

  private

  def determine_sort_direction(is_current, current_direction)
    if is_current && current_direction == "asc"
      "desc"
    else
      "asc"
    end
  end

  def sortable_header_classes
    "group flex items-center space-x-2 hover:text-brand hover:bg-gray-100 px-2 py-1 rounded transition-all duration-200"
  end

  def sort_icon(is_current, current_direction)
    if is_current
      if current_direction == "desc"
        heroicon "chevron-down", options: { class: "w-5 h-5 text-brand" }
      else
        heroicon "chevron-up", options: { class: "w-5 h-5 text-brand" }
      end
    else
      heroicon "chevron-up-down", options: { class: "w-5 h-5 text-gray-300 group-hover:text-gray-400" }
    end
  end
end
