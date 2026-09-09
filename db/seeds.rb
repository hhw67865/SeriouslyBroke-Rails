# frozen_string_literal: true

[Adjustment, Rule, Transfer, Entry, Item, Category, Account, User].each(&:delete_all)

User.create!(email: "demo@example.com", password: "password123", name: "Demo User", timezone: "America/New_York")
