# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :set_account, only: [:edit, :update, :destroy]

  def index = assign_index_state

  def edit; end

  def create
    account = Account.open(current_user, name: account_params[:name], balance: account_params[:balance].presence || 0)
    return redirect_to accounts_path, notice: "#{account.name} added." if account.persisted?

    assign_index_state(new_account: account, new_account_balance: account_params[:balance], open_add_account: true)
    render :index, status: :unprocessable_content
  end

  def update
    if AccountForm.new(@account, account_params).save
      redirect_to accounts_path, notice: "#{@account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    pot_before = AccountLedger.new(current_user).pot
    if @account.destroy
      redirect_to accounts_path, notice: deletion_notice(pot_before)
    else
      redirect_to accounts_path, alert: @account.errors[:base].to_sentence
    end
  end

  private

  def set_account = @account = current_user.accounts.find(params[:id])

  # The state `accounts/index` renders with, on a first visit or after a refusal from any of its
  # forms — a drawer opens from `params[:open]`, a preselected move, or (add) a refusal.
  def assign_index_state(new_account: nil, new_account_balance: nil, open_add_account: false)
    @presenter = AccountsPresenter.new(user: current_user, today: current_user.today)
    @new_account = new_account || current_user.accounts.new
    @new_account_balance = new_account_balance
    @open_add_account = open_add_account || params[:open] == "add"
    @transfer = Transfer.new
    @move_to = params[:move_to]
    @open_move_money = params[:move_to].present? || params[:open] == "move"
  end

  def deletion_notice(pot_before)
    returned = (AccountLedger.new(current_user).pot - pot_before).round(2)
    return "#{@account.name} deleted." unless returned.positive?

    "#{@account.name} deleted — #{helpers.number_to_currency(returned)} is back in checking."
  end

  def account_params
    params.expect(account: [:name, :balance, :keeps_extra, { savings_targets_attributes: [[:id, :item_id, :amount, :percent, :starts_on, :_destroy]] }])
  end
end
