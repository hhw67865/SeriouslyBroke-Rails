# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories" do
  let(:user) { create(:user) }

  # `scope:` explicitly: routes are loaded lazily, so Devise's mappings are still empty
  # when this runs and it has nothing to infer the scope from.
  before { sign_in user, scope: :user }

  it "writes priority and the regular flag", :aggregate_failures do
    post categories_path, params: { category: { name: "Gifts", category_type: "income", regular: "0", priority: "3" } }

    expect(response).to redirect_to(categories_path(type: "income"))
    expect(user.categories.sole).to have_attributes(regular: false, priority: 3)
  end

  it "shows the holdings card only on an expense category", :aggregate_failures do
    create(:account, user: user)
    expense = create(:category, user: user)
    income = create(:category, :income, user: user)

    get category_path(expense)
    expect(response.body).to include("data-holdings-card")
    get category_path(income)
    expect(response.body).not_to include("data-holdings-card")
  end
end
