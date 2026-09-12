# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Budget page" do
  let(:user) { create(:user, :biweekly) }

  before do
    create(:account, user: user)
    sign_in user, scope: :user
  end

  it "reorders the ruled categories", :aggregate_failures do
    a = create(:category, user: user, name: "A", priority: 0)
    b = create(:category, user: user, name: "B", priority: 1)
    [a, b].each { |category| create(:rule, category: category) }

    patch budget_page_reorder_path, params: { category_ids: [b.id, a.id] }

    expect(response).to redirect_to(budget_page_path)
    expect(b.reload.priority).to eq(0)
  end

  it "refuses an order that is not this user's categories", :aggregate_failures do
    create(:rule, category: create(:category, user: user, name: "A"))

    patch budget_page_reorder_path, params: { category_ids: [create(:category, user: user, name: "B").id] }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("nothing was changed")
  end
end
