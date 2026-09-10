# frozen_string_literal: true

class AccountsController < ApplicationController
  include HomeState

  before_action :set_account, only: [:edit, :update, :destroy]

  def edit; end

  def create
    account = Account.open(current_user, name: account_params[:name], balance: account_params[:balance].presence || 0)
    return redirect_to root_path, notice: "#{account.name} added." if account.persisted?

    assign_home_state(new_account: account, new_account_balance: account_params[:balance])
    render "home/index", status: :unprocessable_content
  end

  def update
    if @account.revise(name: account_params[:name], balance: account_params[:balance])
      redirect_to root_path, notice: "#{@account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    pot_before = AccountLedger.new(current_user).pot
    if @account.destroy
      redirect_to root_path, notice: deletion_notice(pot_before)
    else
      redirect_to root_path, alert: @account.errors[:base].to_sentence
    end
  end

  private

  def set_account = @account = current_user.accounts.find(params[:id])

  def deletion_notice(pot_before)
    returned = (AccountLedger.new(current_user).pot - pot_before).round(2)
    return "#{@account.name} deleted." unless returned.positive?

    "#{@account.name} deleted — #{helpers.number_to_currency(returned)} is back in checking."
  end

  def account_params = params.expect(account: [:name, :balance])
end
