# frozen_string_literal: true

class AddPayScheduleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pay_cadence, :integer
    add_column :users, :pay_anchor_date, :date
    add_reference :users, :default_account, type: :uuid, foreign_key: { to_table: :pools }, null: true
  end
end
