# frozen_string_literal: true

class Transfer < ApplicationRecord
  # One account's side of its newest transfer: which way the money went, and when.
  Touch = Data.define(:amount, :date, :direction) do
    def in? = direction == "in"
  end

  belongs_to :from_account, class_name: "Account", touch: true
  belongs_to :to_account, class_name: "Account", touch: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :accounts_differ
  validate :accounts_share_a_user

  delegate :user, to: :from_account

  # Moves money between two of the user's own accounts, or returns a transfer carrying its errors.
  # A foreign account id is not the user's to name, so it 404s rather than failing validation.
  def self.move(user:, from_id:, to_id:, amount:, date:)
    from_account = user.accounts.find(from_id)
    to_account = user.accounts.find(to_id)
    transfer = new(from_account: from_account, to_account: to_account, amount: amount, date: date)
    transfer.save
    transfer
  end

  # The newest transfer touching each account, in one query: the union folds "from" and "to" into
  # a common account_id and direction, so DISTINCT ON can pick the latest per account.
  def self.latest_per_account(account_ids)
    return {} if account_ids.blank?

    sql = sanitize_sql_array(
      [
        <<~SQL.squish, account_ids, account_ids
          SELECT DISTINCT ON (account_id) account_id, amount, date, direction FROM (
            SELECT from_account_id AS account_id, amount::numeric AS amount, date, 'out' AS direction
            FROM transfers WHERE from_account_id IN (?)
            UNION ALL
            SELECT to_account_id AS account_id, amount::numeric AS amount, date, 'in' AS direction
            FROM transfers WHERE to_account_id IN (?)
          ) touching
          ORDER BY account_id, date DESC
        SQL
      ]
    )
    connection.select_all(sql).each_with_object({}) do |row, hash|
      hash[row["account_id"]] = Touch.new(amount: row["amount"].to_d, date: row["date"].to_date, direction: row["direction"])
    end
  end

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
