class IncomeStatusService
  def initialize(user, months)
    @user = user
    @months = months
  end

  def self.call(user, months)
    new(user, months).call
  end

  def call
    {
      graph_data: graph_data,
      income_sources: income_sources
    }
  end

  private

  attr_reader :user, :months

  def graph_data
    (0...months).map do |month|
      income_data_for_month(month)
    end.reverse
  end

  def income_data_for_month(month)
    start_date, end_date = date_range_for_month(month)

    paychecks = user.paychecks.where(date: start_date..end_date)
    income_sources = paychecks.group_by(&:income_source)

    income_data = income_sources.reduce({}) do |hash, (income_source, paychecks)|
      hash[income_source.name] = paychecks.sum(&:amount)
      hash
    end

    income_data.merge({ month: "#{start_date.strftime("%b")} #{start_date.strftime("%Y")}" })
  end

  def date_range_for_month(month)
    start_date = month.months.ago.beginning_of_month
    end_date = month.months.ago.end_of_month
    [start_date, end_date]
  end

  def income_sources
    start_date = months.months.ago.beginning_of_month
    end_date = Date.today.end_of_month

    paychecks = user.paychecks.where(date: start_date..end_date)
    paychecks.map(&:income_source).map(&:name).uniq
  end
end