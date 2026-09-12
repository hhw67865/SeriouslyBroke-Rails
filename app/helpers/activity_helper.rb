# frozen_string_literal: true

# Presentation for one Activity row: the kind badge's colours follow the app's existing
# conventions (the savings tint, the entries table's income/expense colours, a neutral badge for
# an adjustment), and the amount is signed everywhere except a transfer, which only moves money
# between the user's own accounts.
module ActivityHelper
  KIND_BADGE = {
    transfer: { bg: "bg-savings-light", text: "text-savings", label: "Transfer" },
    adjustment: { bg: "bg-gray-100", text: "text-gray-600", label: "Adjustment" }
  }.freeze

  def activity_kind_badge(row)
    config = row.entry? ? entry_kind_badge(row) : KIND_BADGE.fetch(row.kind)
    content_tag(
      :span,
      config[:label],
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{config[:bg]} #{config[:text]}"
    )
  end

  def activity_amount(row)
    return number_to_currency(row.amount) if row.transfer? || row.amount.negative?

    "+#{number_to_currency(row.amount)}"
  end

  def activity_amount_class(row) = row.amount.negative? ? "text-status-danger" : "text-gray-900"

  private

  def entry_kind_badge(row)
    row.amount.negative? ? { bg: "bg-status-danger-light", text: "text-status-danger", label: "Entry" } : { bg: "bg-status-success-light", text: "text-status-success", label: "Entry" }
  end
end
