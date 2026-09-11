# frozen_string_literal: true

class TransfersController < ApplicationController
  include SavingsPageState

  def create
    attrs = transfer_params
    transfer = Transfer.move(
      user: current_user,
      from_id: attrs[:from_account_id],
      to_id: attrs[:to_account_id],
      amount: attrs[:amount],
      date: attrs[:date]
    )
    return redirect_to(params[:return] == "home" ? root_path : savings_path, notice: moved_notice(transfer)) if transfer.persisted?

    assign_savings_state(transfer: transfer, open_transfer: true)
    @transfer_to = transfer.to_account_id
    render "savings/show", status: :unprocessable_content
  end

  private

  def transfer_params = params.expect(transfer: [:from_account_id, :to_account_id, :amount, :date])

  def moved_notice(transfer)
    "Transferred #{helpers.number_to_currency(transfer.amount)} from #{transfer.from_account.name} to #{transfer.to_account.name}."
  end
end
