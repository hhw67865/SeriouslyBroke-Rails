# frozen_string_literal: true

# The Budget page's presenter, for the controllers that render it after a write.
module BudgetPageState
  extend ActiveSupport::Concern

  private

  def build_budget_page(user: current_user, declaration: nil)
    BudgetPagePresenter.new(
      user: user,
      today: user.today,
      declaration: declaration,
      open_category_id: params[:open],
      declaring: params[:declare].present?
    )
  end

  def refuse_on_budget_page(message)
    flash.now[:alert] = message
    @presenter = build_budget_page
    render "budget_page/show", status: :unprocessable_content
  end
end
