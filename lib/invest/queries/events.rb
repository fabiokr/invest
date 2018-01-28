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

    # Public: Memoizes a methods return value based on its arguments.
    #
    # methods - the methods to memoize
    def self.memoize(*methods)
      methods.each do |method|
        define_method(:"#{method}_memoized") do |*args|
          @memoize ||= {}
          @memoize[method] ||= {}

          if @memoize[method].key?(args)
            return @memoize[method][args]
          else
            @memoize[method][args] = send(:"#{method}_original", *args)
          end
        end

        alias_method :"#{method}_original", method
        alias_method method, :"#{method}_memoized"
      end
    end

    attr_reader :invest

    def initialize(invest)
      @invest = invest
    end

    # Public: Gets the years list from the events.
    #
    # Returns an array.
    def year_range
      db.execute(
        "SELECT DISTINCT cast(strftime('%Y', date) AS integer) AS year FROM events ORDER BY year;"
      ).map(&:first)
    end

    # Public: Gets the available categories and their assets from the data.
    #
    # Returns a Hash.
    def categories
      hash = {}

      db.execute(
        "SELECT DISTINCT asset, category FROM events ORDER BY category, asset;"
      ).map do |(asset, category)|
        hash[category] ||= []
        hash[category] << asset
      end

      hash
    end

    # Public: Gets the asset category.
    #
    # asset - the asset name
    #
    # Returns a String.
    def asset_category(asset)
      categories.find { |category, assets| assets.include?(asset) }.first
    end

    # Public: Calculates a month deposits for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_input(asset, year, month)
      start_date = Date.civil(year, month, 1)
      end_date = Date.civil(year, month, -1)

      db.execute(
        "SELECT SUM((quantity/100.0) * price) FROM events WHERE asset = ? AND quantity > 0 AND date(date) >= ? AND date(date) <= ?;",
        [asset, start_date.to_s, end_date.to_s]
      ).first.first
    end

    # Public: Calculates a month withdraws for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_output(asset, year, month)
      start_date = Date.civil(year, month, 1)
      end_date = Date.civil(year, month, -1)

      db.execute(
        "SELECT SUM((quantity/100.0) * price) FROM events WHERE asset = ? AND quantity < 0 AND date(date) >= ? AND date(date) <= ?;",
        [asset, start_date.to_s, end_date.to_s]
      ).first.first
    end

    # Public: Calculates a month average purchase price for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_average_purchase_price(asset, year, month)
      end_date = Date.civil(year, month, -1)

      db.execute(
        "SELECT SUM((quantity/100.0) * price)/SUM(quantity/100.0) FROM events WHERE asset = ? AND quantity > 0 AND date(date) <= ?;",
        [asset, end_date.to_s]
      ).first.first
    end

    # Public: Calculates the month latest price for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_price(asset, year, month)
      date = Date.civil(year, month, -1)

      price = db.execute(
        "SELECT cast(price AS decimal) FROM events WHERE asset = ? AND date(date) <= ? ORDER BY date(date) DESC LIMIT 1;",
        [asset, date.to_s]
      ).first

      price.first if price
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

      return unless date <= self.class.current_month_last_day

      sum = db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_price(asset, year, month)

      sum * price if price
    end

    # Public: Calculates the month profitability for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_profitability(asset, year, month)
      previous_month = Date.new(year, month, 1) << 1
      previous_month_price = asset_month_price(asset, previous_month.year, previous_month.month)
      month_price = asset_month_price(asset, year, month)
      month_purchase_price = asset_month_average_purchase_price(asset, year, month)
      month_inputs = asset_month_input(asset, year, month)

      if month_price
        # if there were inputs on the month, compare against the average purchase price,
        # otherwise compare against last months's price
        if month_inputs && month_inputs > 0
          (month_price - month_purchase_price) / BigDecimal(month_purchase_price, 10)
        else
          (month_price - previous_month_price) / BigDecimal(previous_month_price, 10)
        end
      end
    end

    # Public: Calculates the asset month weight inside the category.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_weight(asset, year, month)
      balance = asset_month_balance(asset, year, month)

      if balance && balance > 0
        category = asset_category(asset)
        balance / BigDecimal.new(category_month_balance(category, year, month), 10)
      end
    end

    # Public: Checks if the asset has data to show on the given month.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a boolean.
    def asset_month_show?(asset, year, month)
      balance = asset_month_balance(asset, year, month)
      input = asset_month_input(asset, year, month)
      output = asset_month_output(asset, year, month)

      # true if there was deposits/withdraws, or if balance is > 0
      (input && input > 0) ||
        (output && output < 0) ||
        (balance && balance > 0)
    end

    # Public: Calculates a year deposits for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_input(asset, year)
      (1..12).inject(0) do |sum, month|
        sum + (asset_month_input(asset, year, month) || 0)
      end
    end

    # Public: Calculates a year withdraws for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_output(asset, year)
      (1..12).inject(0) do |sum, month|
        sum + (asset_month_output(asset, year, month) || 0)
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

      return unless date <= self.class.current_year_last_day

      sum = db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_price(asset, year, 12)

      sum * price if price
    end

    # Public: Calculates the year profitability for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_profitability(asset, year)
      previous_year_price = asset_month_price(asset, year - 1, 12)
      year_price = asset_month_price(asset, year, 12)
      year_purchase_price = asset_month_average_purchase_price(asset, year, 12)
      year_inputs = asset_year_input(asset, year)

      if year_price
        # if there were inputs on the year, compare against the average purchase price,
        # otherwise compare against last year's price
        if year_inputs && year_inputs > 0
          (year_price - year_purchase_price) / BigDecimal(year_purchase_price, 10)
        else
          (year_price - previous_year_price) / BigDecimal(previous_year_price, 10)
        end
      end
    end

    # Public: Calculates the asset year weight inside the category.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_weight(asset, year)
      balance = asset_year_balance(asset, year)

      if balance && balance > 0
        category = asset_category(asset)
        balance / BigDecimal.new(category_year_balance(category, year), 10)
      end
    end

    # Public: Checks if the asset has data to show on the given year.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a boolean.
    def asset_year_show?(asset, year)
      balance = asset_year_balance(asset, year)
      input = asset_year_input(asset, year)
      output = asset_year_output(asset, year)

      # true if there was deposits/withdraws, or if balance is > 0
      (input && input > 0) ||
        (output && output < 0) ||
        (balance && balance > 0)
    end

    # Public: Calculates the total deposits for an asset up to an year.
    #
    # asset - the asset name
    # year - the year
    #
    # Returns a double.
    def asset_total_input(asset, year = year_range.last)
      (year_range.first..year).inject(0) do |sum, y|
        sum + (asset_year_input(asset, y) || 0)
      end
    end

    # Public: Calculates the total withdraws for an asset up to an year.
    #
    # asset - the asset name
    # year - the year
    #
    # Returns a double.
    def asset_total_output(asset, year = year_range.last)
      (year_range.first..year).inject(0) do |sum, y|
        sum + (asset_year_output(asset, y) || 0)
      end
    end

    # Public: Calculates the total profitability for an asset up to an year.
    #
    # asset - the asset name
    # year - the year
    #
    # Returns a double.
    def asset_total_profitability(asset, year = year_range.last)
      price = asset_month_price(asset, year, 12)
      purchase_price = asset_month_average_purchase_price(asset, year, 12)

      if price
        (price - purchase_price) / BigDecimal(purchase_price, 10)
      end
    end

    # Public: Calculates a month deposits for a category.
    #
    # category - the category name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_input(category, year, month)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_month_input(asset, year, month) || 0)
      end
    end

    # Public: Calculates a month withdraws for a category.
    #
    # category - the category name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_output(category, year, month)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_month_output(asset, year, month) || 0)
      end
    end

    # Public: Calculates a month balance for a category.
    #
    # category - the category name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_balance(category, year, month)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_month_balance(asset, year, month) || 0)
      end
    end

    # Public: Calculates the month profitability for a category.
    #
    # category - the category name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_profitability(category, year, month)
      month_balance = category_month_balance(category, year, month)
      month_input = category_month_input(category, year, month) || 0
      month_output = category_month_output(category, year, month) || 0

      previous_month = Date.new(year, month, -1) << 1
      previous_month_balance = category_month_balance(category, previous_month.year, previous_month.month) || 0

      if month_balance
        v = (month_balance == 0 ? month_output : previous_month_balance + month_input)
        profit = month_balance - month_input - previous_month_balance
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    # Public: Calculates the category month weight.
    #
    # category - the category name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_weight(category, year, month)
      balance = category_month_balance(category, year, month)

      if balance && balance > 0
        balance / BigDecimal.new(total_month_balance(year, month), 10)
      end
    end

    # Public: Calculates a year deposits for a category.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_year_input(category, year)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_year_input(asset, year) || 0)
      end
    end

    # Public: Calculates a year withdraws for a category.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_year_output(category, year)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_year_output(asset, year) || 0)
      end
    end

    # Public: Calculates a year balance for a category.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_year_balance(category, year)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_year_balance(asset, year) || 0)
      end
    end

    # Public: Calculates the year profitability for a category.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_year_profitability(category, year)
      year_balance = category_year_balance(category, year)
      year_input = category_year_input(category, year) || 0
      year_output = category_year_output(category, year) || 0

      previous_year_balance = category_year_balance(category, year - 1) || 0

      if year_balance
        v = (year_balance == 0 ? year_output : previous_year_balance + year_input)
        profit = year_balance - year_input - previous_year_balance
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    # Public: Calculates the category year weight.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_year_weight(category, year)
      balance = category_year_balance(category, year)

      if balance && balance > 0
        balance / BigDecimal.new(total_year_balance(year), 10)
      end
    end

    # Public: Calculates the total deposits for a category up to an year.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_total_input(category, year = year_range.last)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_total_input(asset, year) || 0)
      end
    end

    # Public: Calculates the total profitability for a category up to an year.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_total_profitability(category, year = year_range.last)
      balance = category_year_balance(category, year)
      input = category_total_input(category, year) || 0
      output = category_total_output(category, year) || 0

      if balance
        v = (balance == 0 ? output : input)
        profit = balance - input
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    # Public: Calculates the total withdraws for a category up to an year.
    #
    # category - the category name
    # year - the year to check
    #
    # Returns a double.
    def category_total_output(category, year = year_range.last)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_total_output(asset, year) || 0)
      end
    end

    # Public: Calculates a month deposits total.
    #
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def total_month_input(year, month)
      categories.keys.inject(0) do |sum, category|
        sum + (category_month_input(category, year, month) || 0)
      end
    end

    # Public: Calculates a month withdraws total.
    #
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def total_month_output(year, month)
      categories.keys.inject(0) do |sum, category|
        sum + (category_month_output(category, year, month) || 0)
      end
    end

    # Public: Calculates a month balance total.
    #
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def total_month_balance(year, month)
      categories.keys.inject(0) do |sum, category|
        sum + (category_month_balance(category, year, month) || 0)
      end
    end

    # Public: Calculates the month profitability total.
    #
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def total_month_profitability(year, month)
      balance = total_month_balance(year, month)
      input = total_month_input(year, month) || 0
      output = total_month_output(year, month) || 0

      previous_month = Date.new(year, month, -1) << 1
      previous_balance = total_month_balance(previous_month.year, previous_month.month) || 0

      if balance
        v = (balance == 0 ? output : previous_balance + input)
        profit = balance - input - previous_balance
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    # Public: Calculates a year deposits totals.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_year_input(year)
      categories.keys.inject(0) do |sum, category|
        sum + (category_year_input(category, year) || 0)
      end
    end

    # Public: Calculates a year withdraws totals.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_year_output(year)
      categories.keys.inject(0) do |sum, category|
        sum + (category_year_output(category, year) || 0)
      end
    end

    # Public: Calculates a year balance total.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_year_balance(year)
      categories.keys.inject(0) do |sum, category|
        sum + (category_year_balance(category, year) || 0)
      end
    end

    # Public: Calculates the year profitability total.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_year_profitability(year)
      balance = total_year_balance(year)
      input = total_year_input(year) || 0
      output = total_year_output(year) || 0

      previous_balance = total_year_balance(year - 1) || 0

      if balance
        v = (balance == 0 ? output : previous_balance + input)
        profit = balance - input - previous_balance
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    # Public: Calculates the total deposits totals up to an year.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_input(year = year_range.last)
      categories.keys.inject(0) do |sum, category|
        sum + (category_total_input(category, year) || 0)
      end
    end

    # Public: Calculates the total withdraws totals up to an year.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_output(year = year_range.last)
      categories.keys.inject(0) do |sum, category|
        sum + (category_total_output(category, year) || 0)
      end
    end

    # Public: Calculates the total profitability total up to an year.
    #
    # year - the year to check
    #
    # Returns a double.
    def total_profitability(year = year_range.last)
      balance = total_year_balance(year)
      input = total_input(year) || 0
      output = total_output(year) || 0

      if balance
        v = (balance == 0 ? output : input)
        profit = balance - input
        profit / BigDecimal.new(v, 10) if v != 0
      end
    end

    memoize *(instance_methods.map(&:to_s).select do |method|
      method.start_with?("asset") ||
        method.start_with?("category") ||
        method.start_with?("total")
    end + %i(year_range categories))

    private

    # Private: Gets the database instance.
    #
    # Returns a SQLite3::Database.
    def db
      invest.db
    end
  end
end
