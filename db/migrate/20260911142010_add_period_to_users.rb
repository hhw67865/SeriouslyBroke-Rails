# frozen_string_literal: true

class AddPeriodToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :period_cadence, :integer
    add_column :users, :period_anchor_date, :date
  end
end
