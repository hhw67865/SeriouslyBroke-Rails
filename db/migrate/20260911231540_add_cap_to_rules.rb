# frozen_string_literal: true

class AddCapToRules < ActiveRecord::Migration[8.1]
  def change
    add_column :rules, :cap, :money, scale: 2
    add_check_constraint :rules, "cap IS NULL OR (keeps_unspent AND cap > 0::money)", name: "rules_cap_only_on_a_fund"
  end
end
