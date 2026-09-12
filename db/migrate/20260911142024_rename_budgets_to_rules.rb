# frozen_string_literal: true

class RenameBudgetsToRules < ActiveRecord::Migration[8.1]
  def change
    rename_table :budgets, :rules
  end
end
