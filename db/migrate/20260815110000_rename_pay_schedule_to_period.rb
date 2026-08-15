# frozen_string_literal: true

class RenamePayScheduleToPeriod < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :pay_cadence, :period_cadence
    rename_column :users, :pay_anchor_date, :period_anchor_date
    add_column :users, :typical_income, :money, scale: 2
  end
end
