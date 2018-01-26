require "date"
require "bigdecimal"

class Invest
  class EventsQuery
    # Public: Gets the current month last day date.
    #
    # Returns a date.
    def self.current_month_last_day
      @current_month_last_day ||= Date.civil(Date.today.year, Date.today.month, -1)
    end

    # Public: Gets the current year last day date.
    #
    # Returns a date.
    def self.current_year_last_day
      @current_year_last_day ||= Date.new(Date.today.year, 12, 31)
    end

    attr_reader :invest

    def initialize(invest)
      @invest = invest
    end

    # Public: Gets the years list from the events.
    #
    # Returns an array.
    def year_range
      @year_range ||= db.execute(
        "SELECT DISTINCT cast(strftime('%Y', date) AS integer) AS year FROM events ORDER BY year;"
      ).map(&:first)
    end

    # Public: Gets the available categories and their assets from the data.
    #
    # Returns a Hash.
    def categories
      @categories ||= begin
        hash = {}

        db.execute(
          "SELECT DISTINCT asset, category FROM events ORDER BY category, asset;"
        ).map do |(asset, category)|
          hash[category] ||= []
          hash[category] << asset
        end

        hash
      end
    end

    # Public: Calculates a month withdraws and deposits for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_input(asset, year, month)
      @asset_month_input ||= {}

      if cached = @asset_month_input[[asset, year, month]]
        return cached
      end

      start_date = Date.civil(year, month, 1)
      end_date = Date.civil(year, month, -1)

      @asset_month_input[[asset, year, month]] = db.execute(
        "SELECT SUM(quantity * price) FROM events WHERE asset = ? AND date(date) >= ? AND date(date) <= ?;",
        [asset, start_date.to_s, end_date.to_s]
      ).first.first
    end

    # Public: Calculates a year withdraws and deposits for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_input(asset, year)
      @asset_year_input ||= {}

      if cached = @asset_year_input[[asset, year]]
        return cached
      end

      start_date = Date.new(year, 1, 1)
      end_date = Date.new(year, 12, 31)

      @asset_year_input[[asset, year]] = db.execute(
        "SELECT SUM(quantity * price) FROM events WHERE asset = ? AND date(date) >= ? AND date(date) <= ?;",
        [asset, start_date.to_s, end_date.to_s]
      ).first.first
    end

    # Public: Calculates a month balance for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_balance(asset, year, month)
      date = Date.civil(year, month, -1)

      @asset_month_balance ||= {}

      if cached = @asset_month_balance[[asset, year, month]]
        return cached
      end

      return unless date <= self.class.current_month_last_day

      sum = db.execute(
        "SELECT SUM(quantity) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_price(asset, year, month)

      @asset_month_balance[[asset, year, month]] = if price
        sum * price
      end
    end

    # Public: Calculates a year balance for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_balance(asset, year)
      date = Date.new(year, 12, 31)

      @asset_year_balance ||= {}

      if cached = @asset_year_balance[[asset, year]]
        return cached
      end

      return unless date <= self.class.current_year_last_day

      sum = db.execute(
        "SELECT SUM(quantity) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_price(asset, year, 12)

      @asset_year_balance[[asset, year]] = if price
        sum * price
      end
    end

    # Public: Calculates the month latest price for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_price(asset, year, month)
      @asset_month_price ||= {}

      if cached = @asset_month_price[[asset, year, month]]
        return cached
      end

      date = Date.civil(year, month, -1)

      price = db.execute(
        "SELECT cast(price AS decimal) FROM events WHERE asset = ? AND date(date) <= ? ORDER BY date(date) DESC LIMIT 1;",
        [asset, date.to_s]
      ).first

      if price
        @asset_month_price[[asset, year, month]] = price.first
      end
    end

    # Public: Calculates the month profit for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_profit(asset, year, month)
      @asset_month_profit ||= {}

      if cached = @asset_month_profit[[asset, year, month]]
        return cached
      end

      previous_month = Date.new(year, month, -1) << 1
      month_balance = asset_month_balance(asset, year, month)

      @asset_month_profit[[asset, year, month]] = if month_balance
        month_balance -
          (asset_month_input(asset, year, month) || 0) -
          (asset_month_balance(asset, previous_month.year, previous_month.month) || 0)
      end
    end

    # Public: Calculates the month profitability for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_profitability(asset, year, month)
      month_balance = asset_month_balance(asset, year, month)
      month_input = asset_month_input(asset, year, month) || 0

      previous_month = Date.new(year, month, -1) << 1
      previous_month_balance = asset_month_balance(asset, previous_month.year, previous_month.month) || 0

      if month_balance
        v = (month_balance == 0 ? -month_input : previous_month_balance + month_input)
        asset_month_profit(asset, year, month) / BigDecimal.new(v, 10) if v != 0
      end
    end

    private

    # Private: Gets the database instance.
    #
    # Returns a SQLite3::Database.
    def db
      invest.db
    end
  end
end
