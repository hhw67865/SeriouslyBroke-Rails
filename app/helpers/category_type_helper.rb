# frozen_string_literal: true

# Helper for category type presentation (colors, labels, formatting).
module CategoryTypeHelper
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
