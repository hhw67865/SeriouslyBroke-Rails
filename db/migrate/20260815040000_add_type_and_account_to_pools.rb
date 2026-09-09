# frozen_string_literal: true

class AddTypeAndAccountToPools < ActiveRecord::Migration[8.1]
  def change
    add_column :pools, :pool_type, :integer, null: false, default: 2
    add_column :pools, :priority, :integer, null: false, default: 0
    add_reference :pools, :account, type: :uuid, foreign_key: { to_table: :pools }, null: true

    add_index :pools, [:user_id, :priority]
  end
end
