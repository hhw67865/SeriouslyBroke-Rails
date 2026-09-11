# frozen_string_literal: true

# The Savings page's state, for the controllers that render it after a write. Filled in with the page.
module SavingsPageState
  extend ActiveSupport::Concern

  private

  def refuse_on_savings_page(message)
    redirect_to savings_path, alert: message
  end
end
