# frozen_string_literal: true

require "rails_helper"

RSpec.describe Category do
  let(:user) { create(:user) }

  describe "validations", :aggregate_failures do
    it "has two types, a unique name per user, and a non-negative priority" do
      create(:category, user: user, name: "Groceries")

      expect(described_class.category_types.keys).to eq(["expense", "income"])
      expect(build(:category, user: user, name: "groceries")).not_to be_valid
      expect(build(:category, user: user, priority: -1)).not_to be_valid
      expect(build(:category, user: user, name: "  Rent  ").tap(&:valid?).name).to eq("Rent")
    end

    it "is regular and tracked by default" do
      category = create(:category, :income, user: user)

      expect(category).to be_regular
      expect(category).to be_tracked
    end
  end

  describe "scopes", :aggregate_failures do
    it "lists ruled expense categories in fill order" do
      groceries = create(:category, user: user, name: "Groceries", priority: 2)
      rent = create(:category, user: user, name: "Rent", priority: 1)
      create(:category, user: user, name: "Unruled", priority: 0)
      create(:rule, category: groceries)
      create(:rule, category: rent)

      expect(user.categories.in_fill_order).to eq([rent, groceries])
      expect(user.categories.with_a_rule).to contain_exactly(rent, groceries)
    end

    it "separates regular income from the rest" do
      salary = create(:category, :income, user: user)
      create(:category, :income, :irregular, user: user)

      expect(user.categories.incomes.regular).to eq([salary])
    end
  end

  describe ".apply_fill_order" do
    let!(:a) { create(:category, user: user, name: "A", priority: 0).tap { |c| create(:rule, category: c) } }
    let!(:b) { create(:category, user: user, name: "B", priority: 1).tap { |c| create(:rule, category: c) } }

    it "rewrites priorities in the given order", :aggregate_failures do
      expect(described_class.apply_fill_order(user: user, category_ids: [b.id, a.id])).to be(true)
      expect(b.reload.priority).to eq(0)
      expect(a.reload.priority).to eq(1)
    end

    it "refuses a list that is not exactly the ruled categories", :aggregate_failures do
      expect(described_class.apply_fill_order(user: user, category_ids: [a.id])).to be(false)
      expect(described_class.apply_fill_order(user: user, category_ids: [a.id, a.id])).to be(false)
      expect(described_class.apply_fill_order(user: user, category_ids: [])).to be(false)
      expect(a.reload.priority).to eq(0)
    end
  end

  describe ".choose_regular_income" do
    it "sets regular on the chosen income categories and clears the rest", :aggregate_failures do
      salary = create(:category, :income, user: user, name: "Salary")
      bonus = create(:category, :income, :irregular, user: user, name: "Bonus")

      count = described_class.choose_regular_income(user: user, category_ids: [bonus.id])

      expect(count).to eq(1)
      expect(salary.reload).not_to be_regular
      expect(bonus.reload).to be_regular
    end

    it "never touches expense categories or another user's categories", :aggregate_failures do
      expense = create(:category, :irregular, user: user, name: "Rent")
      other_income = create(:category, :income, :irregular, user: create(:user))

      described_class.choose_regular_income(user: user, category_ids: [expense.id, other_income.id])

      expect(expense.reload).not_to be_regular
      expect(other_income.reload).not_to be_regular
    end
  end

  describe "changing type" do
    it "sends an income category's entries back to main when it becomes expense" do
      account = create(:account, user: user)
      create(:account, user: user)
      category = create(:category, :income, user: user)
      entry = create(:entry, item: create(:item, category: category), account: account)

      category.update!(category_type: :expense)

      expect(entry.reload.account).to be_nil
    end

    it "refuses to become income while it carries rules", :aggregate_failures do
      category = create(:category, user: user)
      create(:rule, category: category)

      expect(category.update(category_type: :income)).to be(false)
      expect(category.errors[:category_type]).to include(Category::RULES_KEEP_IT_AN_EXPENSE)
      expect(category.reload).to be_expense
    end
  end

  describe "#ruled? and #display_color", :aggregate_failures do
    it "answers from its rules and its colour" do
      category = create(:category, user: user, color: nil)

      expect(category).not_to be_ruled
      expect(category.display_color).to eq(Category::DEFAULT_COLOR)
      create(:rule, category: category)
      expect(category.reload).to be_ruled
    end
  end
end
