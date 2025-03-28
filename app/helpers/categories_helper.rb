module CategoriesHelper
  def budget_status(percentage)
    if percentage > 100
      "Budget exceeded"
    elsif percentage > 90
      "Almost depleted"
    elsif percentage > 75
      "Warning zone"
    elsif percentage > 50
      "On track"
    else
      "Well under budget"
    end
  end

  def budget_status_color(percentage)
    if percentage > 100
      "bg-status-danger"
    elsif percentage > 90
      "bg-status-danger"
    elsif percentage > 75
      "bg-status-warning"
    else
      "bg-brand"
    end
  end
end
