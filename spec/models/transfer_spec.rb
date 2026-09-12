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

  describe ".move" do
    it "creates a transfer between two of the user's own accounts", :aggregate_failures do
      transfer = described_class.move(user: user, from_id: main.id, to_id: savings.id, amount: 40, date: Date.current)

      expect(transfer).to be_persisted
      expect(transfer).to have_attributes(from_account: main, to_account: savings, amount: 40)
    end

    it "404s on an account that is not the user's" do
      foreign = create(:account)

      expect { described_class.move(user: user, from_id: main.id, to_id: foreign.id, amount: 40, date: Date.current) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "refuses the same account on both sides, and a non-positive amount", :aggregate_failures do
      same = described_class.move(user: user, from_id: main.id, to_id: main.id, amount: 40, date: Date.current)
      zero = described_class.move(user: user, from_id: main.id, to_id: savings.id, amount: 0, date: Date.current)

      expect(same).not_to be_persisted
      expect(zero).not_to be_persisted
    end
  end
end
