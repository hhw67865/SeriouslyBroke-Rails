# frozen_string_literal: true

module EntriesHelper
  TYPE_BADGE_CONFIG = {
    "expense" => { bg: "bg-status-danger-light", text: "text-status-danger", icon: "minus-circle", label: "Expense" },
    "income" => { bg: "bg-status-success-light", text: "text-status-success", icon: "plus-circle", label: "Income" },
    "savings" => { bg: "bg-status-info-light", text: "text-status-info", icon: "circle-stack", label: "Savings" }
  }.freeze

  def entry_type_badge(category_type, with_icon: false)
    config = TYPE_BADGE_CONFIG[category_type]
    return unless config

    content_tag(:span, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{config[:bg]} #{config[:text]}") do
      if with_icon
        safe_join([heroicon(config[:icon], options: { class: "w-3 h-3 mr-1" }), config[:label]])
      else
        config[:label]
      end
    end
  end
end
