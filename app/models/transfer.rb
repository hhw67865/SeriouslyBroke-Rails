# frozen_string_literal: true

class Transfer < ApplicationRecord
  belongs_to :from_account, class_name: "Account", touch: true
  belongs_to :to_account, class_name: "Account", touch: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :accounts_differ
  validate :accounts_share_a_user

  delegate :user, to: :from_account

  private

  def accounts_differ
    return if from_account.blank? || to_account.blank?

    errors.add(:to_account, "must differ from the source account") if from_account == to_account
  end

  def accounts_share_a_user
    return if from_account.blank? || to_account.blank?

    errors.add(:to_account, "must belong to the same user") unless from_account.user_id == to_account.user_id
  end
end
