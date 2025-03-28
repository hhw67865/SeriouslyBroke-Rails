# frozen_string_literal: true

module CategoriesHelper
  def budget_status(percentage)
    case percentage
    when (101..) then "Budget exceeded"
    when (91..100) then "Almost depleted"
    when (76..90) then "Warning zone"
    when (51..75) then "On track"
    else "Well under budget"
    end
  end

  def budget_status_color(percentage)
    case percentage
    when (91..) then "bg-status-danger"
    when (76..90) then "bg-status-warning"
    else "bg-brand"
    end
  end
end
