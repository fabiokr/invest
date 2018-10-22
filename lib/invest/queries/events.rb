require "date"
require "bigdecimal"

class Invest
  class EventsQuery
    IR_CATEGORIES = %w(Acoes Opcoes Ativos FI Criptomoedas Metais)

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

    # Private: Builds income taxes data.
    #
    # Returns an Array.
    def ir
      data = []

      year_range.each do |year|
        (1..12).each do |month|
          categories.each do |category, assets|
            next unless IR_CATEGORIES.include?(category)

            output = category_month_output(category, year, month)
            profit = category_month_profit(category, year, month)

            if profit != 0
              data << [year, month, category, -output, profit]
            end
          end
        end
      end

      data.reverse
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

    # Public: Calculates a month withdraws quantity for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_output_quantity(asset, year, month)
      start_date = Date.civil(year, month, 1)
      end_date = Date.civil(year, month, -1)

      db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND quantity < 0 AND date(date) >= ? AND date(date) <= ?;",
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

    # Public: Calculates a month quantity balance for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_quantity(asset, year, month)
      date = Date.civil(year, month, -1)

      db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first
    end

    # Public: Calculates a month purchase balance for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_purchase_balance(asset, year, month)
      date = Date.civil(year, month, -1)

      return unless date <= self.class.current_month_last_day

      sum = db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_average_purchase_price(asset, year, month)

      sum * price if price
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

    # Public: Calculates a month profit for an asset.
    #
    # asset - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def asset_month_profit(asset, year, month)
      output = asset_month_output(asset, year, month)

      if output && output <= 0
        output_quantity = -asset_month_output_quantity(asset, year, month)
        purchase_price = asset_month_average_purchase_price(asset, year, month)
        -output - (output_quantity * purchase_price)
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
      previous = Date.new(year, month, 1) << 1
      previous_balance = asset_month_balance(asset, previous.year, previous.month) || 0
      balance = asset_month_balance(asset, year, month)
      input = asset_month_input(asset, year, month) || 0
      output = asset_month_output(asset, year, month) || 0

      if (balance && balance >= 0) || output < 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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
      output = asset_month_output(asset, year, month) || 0
      balance = asset_month_balance(asset, year, month) || 0

      if (balance > 0 || output < 0)
        category = asset_category(asset)
        category_output = category_month_output(category, year, month) || 0
        category_balance = category_month_balance(category, year, month) || 0
        (balance + (-output)) / BigDecimal.new(category_balance + (-category_output), 10)
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

    # Public: Calculates a year quantity balance for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_quantity(asset, year)
      date = Date.new(year, 12, 31)

      db.execute(
        "SELECT SUM(quantity/100.0) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first
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
        "SELECT SUM(quantity) FROM events WHERE asset = ? AND date(date) <= date(?);",
        [asset, date.to_s]
      ).first.first

      price = asset_month_price(asset, year, 12)

      (sum / BigDecimal.new(100, 10)) * price if price
    end

    # Public: Calculates the year profitability for an asset.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def asset_year_profitability(asset, year)
      previous_balance = asset_year_balance(asset, year - 1) || 0
      balance = asset_year_balance(asset, year)
      input = asset_year_input(asset, year) || 0
      output = asset_year_output(asset, year) || 0

      if (balance && balance >= 0) || output < 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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
      balance = asset_year_balance(asset, year)
      input = asset_total_input(asset, year) || 0
      output = asset_total_output(asset, year) || 0

      (balance + (-output) - input) / BigDecimal(input, 10)
    end

    # Public: Checks if the asset is part of the IBOVESPA index.
    #
    # asset - the asset name
    #
    # Returns a boolean.
    def asset_is_in_ibovespa(asset)
      sum = db.execute(
        "SELECT COUNT(*) FROM ibovespa WHERE asset = ?;",
        [asset]
      ).first.first

      sum > 0
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

    # Public: Calculates a month profit for a category.
    #
    # category - the asset name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def category_month_profit(category, year, month)
      categories[category].inject(0) do |sum, asset|
        sum + (asset_month_profit(asset, year, month) || 0)
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
      previous = Date.new(year, month, 1) << 1
      previous_balance = category_month_balance(category, previous.year, previous.month) || 0
      balance = category_month_balance(category, year, month)
      input = category_month_input(category, year, month) || 0
      output = category_month_output(category, year, month) || 0

      if balance && balance >= 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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
      output = category_month_output(category, year, month) || 0
      balance = category_month_balance(category, year, month) || 0

      if balance > 0 || output < 0
        total_output = total_month_output(year, month) || 0
        total_balance = total_month_balance(year, month) || 0
        (balance + (-output)) / BigDecimal.new(total_balance + (-total_output), 10)
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
      previous_balance = category_year_balance(category, year - 1) || 0
      balance = category_year_balance(category, year)
      input = category_year_input(category, year) || 0
      output = category_year_output(category, year) || 0

      if balance && balance >= 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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

      if balance && balance >= 0
        (balance + (-output) - input) / BigDecimal(input, 10)
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
      previous = Date.new(year, month, 1) << 1
      previous_balance = total_month_balance(previous.year, previous.month) || 0
      balance = total_month_balance(year, month)
      input = total_month_input(year, month) || 0
      output = total_month_output(year, month) || 0

      if balance && balance >= 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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
      previous_balance = total_year_balance(year - 1) || 0
      balance = total_year_balance(year)
      input = total_year_input(year) || 0
      output = total_year_output(year) || 0

      if balance && balance >= 0
        v = previous_balance + input
        (balance + (-output) - v) / BigDecimal(v, 10)
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

      if balance && balance >= 0
        (balance + (-output) - input) / BigDecimal(input, 10)
      end
    end

    # Public: Calculates the index month value.
    #
    # asset - the index name
    # year - the year to check
    # month - the month to check
    #
    # Returns a double.
    def index_month_value(asset, year, month)
      start_date = Date.civil(year, month, 1)
      end_date = Date.civil(year, month, -1)

      value = db.execute(
        "SELECT cast(value AS decimal) / 10000.0 FROM indexes WHERE asset = ? AND date(date) >= ? AND date(date) <= ? ORDER BY date(date) DESC LIMIT 1;",
        [asset, start_date.to_s, end_date.to_s]
      ).first

      value.first if value
    end

    # Public: Calculates a year value for an index.
    #
    # asset - the asset name
    # year - the year to check
    #
    # Returns a double.
    def index_year_value(asset, year)
      (1..12).inject(0) do |sum, month|
        sum + (index_month_value(asset, year, month) || 0)
      end
    end

    memoize *(instance_methods.map(&:to_s).select do |method|
      method.start_with?("asset") ||
        method.start_with?("category") ||
        method.start_with?("total") ||
        method.start_with?("index")
    end + %i(year_range categories ir))

    private

    # Private: Gets the database instance.
    #
    # Returns a SQLite3::Database.
    def db
      invest.db
    end
  end
end
