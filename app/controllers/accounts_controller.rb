# frozen_string_literal: true

class AccountsController < ApplicationController
  include SavingsPageState

  before_action :set_account, only: [:edit, :update, :destroy]
  before_action :load_form_options, only: [:edit, :update]

  def edit; end

  def create
    account = Account.open(current_user, name: account_params[:name], balance: account_params[:balance].presence || 0)
    return redirect_to savings_path, notice: "#{account.name} added." if account.persisted?

    assign_savings_state(new_account: account, new_account_balance: account_params[:balance], open_add_account: true)
    render "savings/show", status: :unprocessable_content
  end

  def update
    if AccountForm.new(@account, account_params).save
      redirect_to savings_path, notice: "#{@account.name} updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    pot_before = AccountLedger.new(current_user).pot
    if @account.destroy
      redirect_to savings_path, notice: deletion_notice(pot_before)
    else
      redirect_to savings_path, alert: @account.errors[:base].to_sentence
    end
  end

  private

  def set_account = @account = current_user.accounts.find(params[:id])

  def load_form_options
    @income_items = current_user.items.incomes.order(:name)
    @typical_income = SavingsPresenter.new(user: current_user, today: current_user.today).typical_income
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
