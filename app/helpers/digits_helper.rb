# frozen_string_literal: true

# `delimiter: ""` is required: `number_to_rounded` delimits by default, so "$1,500" would reach
# the DOM as "1,500.00" and `parseFloat` would read it as 1.5.
module DigitsHelper
  module_function

  def digits(amount) = ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: "")
end
