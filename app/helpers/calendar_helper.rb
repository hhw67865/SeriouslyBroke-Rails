# frozen_string_literal: true

module CalendarHelper
  # Formats currency amounts in compact form (e.g., $1.5k, $2.3m)
  # Used in monthly calendar day cells where space is limited.
  def compact_currency(amount)
    "$#{number_to_human(
      amount,
      format: "%n%u",
      precision: 3,
      significant: true,
      strip_insignificant_zeros: true,
      units: { unit: "", thousand: "k", million: "m", billion: "b", trillion: "t" }
    )}"
  end
end
