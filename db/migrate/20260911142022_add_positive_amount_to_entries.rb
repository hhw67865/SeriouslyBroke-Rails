# frozen_string_literal: true

class AddPositiveAmountToEntries < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :entries, "amount > 0::money", name: "entries_positive_amount"
  end
end
