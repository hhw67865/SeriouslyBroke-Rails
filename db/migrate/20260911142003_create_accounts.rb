# frozen_string_literal: true

class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.money :opening_balance, scale: 2, null: false, default: 0
      t.date :opened_on
      t.timestamps
    end
    add_index :accounts, "user_id, lower(name)", unique: true, name: "index_accounts_on_user_id_and_lower_name"
  end
end
