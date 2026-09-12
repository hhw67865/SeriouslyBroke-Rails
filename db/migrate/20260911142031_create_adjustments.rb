# frozen_string_literal: true

class CreateAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :adjustments, id: :uuid do |t|
      t.string :source_type, null: false
      t.uuid :source_id, null: false
      t.money :amount, scale: 2, null: false
      t.date :date, null: false
      t.timestamps
    end
    add_index :adjustments, [:source_type, :source_id]
    add_index :adjustments, :date
    add_check_constraint :adjustments, "amount <> 0::money", name: "adjustments_non_zero_amount"
    add_check_constraint :adjustments, "source_type <> 'Account' OR amount < 0::money", name: "adjustments_accounts_only_reduce"
  end
end
