# frozen_string_literal: true

# The Savings page's state, for savings#show and for the controllers that render it after a refusal
# from one of its forms: a drawer opens from `params[:open]`, a preselected transfer, or a refusal.
module SavingsPageState
  extend ActiveSupport::Concern

  private

  def assign_savings_state(new_account: nil, new_account_balance: nil, open_add_account: false, transfer: nil, open_transfer: false)
    @presenter = SavingsPresenter.new(user: current_user, today: current_user.today)
    @new_account = new_account || current_user.accounts.new
    @new_account_balance = new_account_balance
    @open_add_account = open_add_account || params[:open] == "add"
    @transfer = transfer || Transfer.new
    @transfer_to = params[:to]
    @open_transfer = open_transfer || params[:to].present? || params[:open] == "transfer"
  end

  def refuse_on_savings_page(message)
    flash.now[:alert] = message
    assign_savings_state
    render "savings/show", status: :unprocessable_content
  end
end
