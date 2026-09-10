# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Entries" do
  let(:user) { create(:user) }
  let(:savings) { create(:account, user: user) }
  let(:salary) { create(:category, :income, user: user, name: "Salary") }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before do
    create(:account, user: user) # the first account a user gets is main
    sign_in user, scope: :user
  end

  it "creates a new item by name in the category and lands income in the chosen account", :aggregate_failures do
    post entries_path, params: { category_id: salary.id, entry: { amount: "1000 + 200", date: "2026-09-05", item_id: "", item_attributes: { name: "Pay" }, account_id: savings.id } }

    expect(response).to redirect_to(entries_path)
    entry = user.entries.sole
    expect(entry).to have_attributes(amount: 1200, account: savings)
    expect(entry.item.name).to eq("Pay")
  end

  it "keeps spending in main whatever account is posted" do
    bread = create(:item, category: groceries, name: "Bread")

    post entries_path, params: { entry: { amount: "5", date: "2026-09-05", item_id: bread.id, account_id: savings.id } }

    expect(user.entries.sole.account).to be_nil
  end

  it "re-renders the form on a refusal" do
    post entries_path, params: { entry: { amount: "abc", date: "2026-09-05", item_id: create(:item, category: groceries).id } }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders the impact card for an expense category" do
    create(:rule, :rate, amount: 400, category: groceries)

    get impact_entries_path, params: { category_id: groceries.id, amount: "50" }

    expect(response.body).to include("$350.00")
  end
end
