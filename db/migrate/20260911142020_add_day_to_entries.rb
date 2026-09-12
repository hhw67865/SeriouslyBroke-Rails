# frozen_string_literal: true

class AddDayToEntries < ActiveRecord::Migration[8.1]
  def change
    add_column :entries, :day, :date
  end
end
