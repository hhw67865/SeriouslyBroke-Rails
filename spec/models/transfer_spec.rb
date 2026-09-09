# frozen_string_literal: true

require "rails_helper"

RSpec.describe Transfer do
  let(:user) { create(:user) }
  let(:main) { create(:account, user: user) }
  let(:savings) { create(:account, user: user) }

  it "moves a positive amount on a date between two different accounts of one user", :aggregate_failures do
    expect(build(:transfer, from_account: main, to_account: savings, amount: 10)).to be_valid
    expect(build(:transfer, from_account: main, to_account: savings, amount: 0)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: savings, date: nil)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: main)).not_to be_valid
    expect(build(:transfer, from_account: main, to_account: create(:account))).not_to be_valid
  end

  it "belongs to the accounts' user" do
    expect(build(:transfer, from_account: main, to_account: savings).user).to eq(user)
  end
end
