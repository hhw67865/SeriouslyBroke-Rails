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
  TYPE_CONFIG = {
    expense: { label: "Expense", plural: "Expenses", color: "text-status-danger", bg: "bg-status-danger", sign: "-" },
    income: { label: "Income", plural: "Income", color: "text-status-success", bg: "bg-status-success", sign: "+" },
    savings: { label: "Savings", plural: "Savings", color: "text-brand-dark", bg: "bg-brand-dark", sign: "+" }
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
