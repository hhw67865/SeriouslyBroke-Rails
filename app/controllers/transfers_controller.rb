# frozen_string_literal: true

class TransfersController < ApplicationController
  include SavingsPageState
  include HomeState

  def create
    transfer = move
    return redirect_to(params[:return] == "home" ? root_path : savings_path, notice: moved_notice(transfer)) if transfer.persisted?
    return refuse_on_home(transfer.errors.full_messages.to_sentence) if params[:return] == "home"

    refuse_on_savings(transfer)
  end

  private

  def move
    attrs = transfer_params
    Transfer.move(
      user: current_user,
      from_id: attrs[:from_account_id],
      to_id: attrs[:to_account_id],
      amount: attrs[:amount],
      date: attrs[:date]
    )
  end

  def refuse_on_savings(transfer)
    assign_savings_state(transfer: transfer, open_transfer: true)
    @transfer_to = transfer.to_account_id
    render "savings/show", status: :unprocessable_content
  end

  def transfer_params = params.expect(transfer: [:from_account_id, :to_account_id, :amount, :date])

  def moved_notice(transfer)
    "Transferred #{helpers.number_to_currency(transfer.amount)} from #{transfer.from_account.name} to #{transfer.to_account.name}."
  end
end
