# frozen_string_literal: true

class AddPeriodToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.integer :period_cadence
      t.date :period_anchor_date
    end
  end
end
