# frozen_string_literal: true

# Which items the user reaches for most, so the New entry page can offer them as one-tap chips.
# Ranked by how often an item was entered in the window, ties broken by the more recent one.
class UsualItems
  Row = Struct.new(:item, :count, :last, keyword_init: true) # rubocop:disable Lint/StructNewOverride

  def initialize(user, today:, window: 90, limit: 8)
    @user = user
    @today = today
    @window = window
    @limit = limit
  end

  def rows
    @rows ||= build_rows
  end

  private

  attr_reader :user, :today, :window, :limit

  def build_rows
    ranked = ranked_counts
    return [] if ranked.empty?

    items = user.items.where(id: ranked.map(&:item_id)).index_by(&:id)
    lasts = last_entries_by_item(ranked.map(&:item_id))

    ranked.filter_map do |row|
      item = items[row.item_id]
      last = lasts[row.item_id]
      Row.new(item: item, count: row.entry_count, last: last) if item && last
    end
  end

  # Count and most recent date per item, dated within the window — one grouped query.
  def ranked_counts
    user.entries
      .where(date: (today - window)..today)
      .group(:item_id)
      .select("item_id, COUNT(*) AS entry_count, MAX(date) AS last_date")
      .sort_by { |row| [row.entry_count, row.last_date] }
      .reverse
      .first(limit)
  end

  def last_entries_by_item(item_ids) = Entry.latest_per_item(item_ids).index_by(&:item_id)
end
