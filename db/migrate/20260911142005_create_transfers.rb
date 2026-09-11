# frozen_string_literal: true

class CreateTransfers < ActiveRecord::Migration[8.1]
  def change
    create_table :transfers, id: :uuid do |t|
      t.references :from_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.references :to_account, type: :uuid, null: false, foreign_key: { to_table: :accounts }
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :transfers, :date
    add_check_constraint :transfers, "amount > 0::money", name: "transfers_positive_amount"
    add_check_constraint :transfers, "from_account_id <> to_account_id", name: "transfers_distinct_accounts"
  end
end
