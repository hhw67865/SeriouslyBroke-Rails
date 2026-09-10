# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Items" do
  let(:user) { create(:user) }
  let(:groceries) { create(:category, user: user, name: "Groceries") }

  before { sign_in user, scope: :user }

  # The edit form renames an item; moving one is Manage Items' job, so a posted
  # category_id is not a permitted parameter and simply does not land.
  it "ignores a category_id from another user's books", :aggregate_failures do
    bread = create(:item, category: groceries, name: "Bread")
    theirs = create(:category, user: create(:user), name: "Their Pantry")

    patch item_path(bread), params: { item: { name: "Sourdough", category_id: theirs.id } }

    expect(response).to redirect_to(category_path(groceries))
    expect(bread.reload).to have_attributes(name: "Sourdough", category: groceries)
  end

  it "cannot reach an item that belongs to someone else" do
    theirs = create(:item, category: create(:category, user: create(:user)), name: "Their Bread")

    patch item_path(theirs), params: { item: { name: "Mine Now" } }

    expect(response).to have_http_status(:not_found)
  end
end
