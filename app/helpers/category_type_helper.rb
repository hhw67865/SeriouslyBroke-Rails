# frozen_string_literal: true

# Helper for category type presentation (colors, labels, formatting).
# Keeps styling concerns out of models.
#
# Usage in views:
#   category_type_color(:expense)     # => "text-status-danger"
#   category_type_label(:expense)     # => "Expense"
#   format_amount_with_sign(100, :expense) # => "-$100.00"
#
module CategoryTypeHelper
  # TWO TYPES (plan 3, task 5). The `savings:` row went with the enum value, and it is what the
  # CALENDAR was built out of: both calendar presenters key their per-day totals and their weekly
  # breakdown off `CATEGORY_TYPES`, and four calendar views iterate it. Dropping the row here is
  # what takes the savings column off the grid, out of the legend and out of the week summary — one
  # deletion rather than five, because the calendar was already reading the type list rather than
  # naming the types.
  #
  # MOVEMENTS STILL DO NOT RENDER ON THE CALENDAR, and that is not an omission this leaves behind.
  # The calendar is a story about ENTRIES — money entering or leaving the user's life on a day —
  # and a `PoolMovement` is neither; it is the user's own money changing pockets. Both presenters
  # fetch from `Entry` and nothing else, so there is nothing to gate. Asserted both ways in
  # spec/system/calendar.
  TYPE_CONFIG = {
    expense: { label: "Expense", plural: "Expenses", color: "text-status-danger", bg: "bg-status-danger", sign: "-" },
    income: { label: "Income", plural: "Income", color: "text-status-success", bg: "bg-status-success", sign: "+" }
  }.freeze

  CATEGORY_TYPES = TYPE_CONFIG.keys.freeze

  def category_type_config(type)
    TYPE_CONFIG[type.to_sym]
  end

  def category_type_label(type)
    TYPE_CONFIG[type.to_sym][:label]
  end

  def category_type_plural(type)
    TYPE_CONFIG[type.to_sym][:plural]
  end

  def category_type_color(type)
    TYPE_CONFIG[type.to_sym][:color]
  end

  def category_type_bg(type)
    TYPE_CONFIG[type.to_sym][:bg]
  end

  def category_type_sign(type)
    TYPE_CONFIG[type.to_sym][:sign]
  end

  def format_amount_with_sign(amount, type)
    config = TYPE_CONFIG[type.to_sym]
    "#{config[:sign]}#{number_to_currency(amount)}"
  end
end
