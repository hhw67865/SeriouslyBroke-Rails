# frozen_string_literal: true

class TransfersController < ApplicationController
  def create
    attrs = transfer_params
    transfer = Transfer.move(
      user: current_user,
      from_id: attrs[:from_account_id],
      to_id: attrs[:to_account_id],
      amount: attrs[:amount],
      date: attrs[:date]
    )
    return redirect_to accounts_path, notice: moved_notice(transfer) if transfer.persisted?

    render_refused(transfer)
  end

  private

  def transfer_params
    params.expect(transfer: [:from_account_id, :to_account_id, :amount, :date])
  end

  def moved_notice(transfer)
    "Moved #{helpers.number_to_currency(transfer.amount)} from #{transfer.from_account.name} to #{transfer.to_account.name}."
  end

  def render_refused(transfer)
    @presenter = AccountsPresenter.new(user: current_user, today: current_user.today)
    @new_account = current_user.accounts.new
    @new_account_balance = nil
    @open_add_account = false
    @transfer = transfer
    @move_to = transfer.to_account_id
    @open_move_money = true
    render "accounts/index", status: :unprocessable_content
  end
end
