class Invest
  class EventsQuery
    attr_reader :invest

    def initialize(invest)
      @invest = invest
    end

    # Public: Gets the years list from the events.
    #
    # Returns an array.
    def year_range
      @year_range ||= db.execute(
        "SELECT DISTINCT strftime('%Y', date) AS year FROM events ORDER BY year;"
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
      db.execute(
        "SELECT SUM(quantity * price) FROM events WHERE asset = ? AND CAST(strftime('%Y', date) AS integer) = ? AND CAST(strftime('%m', date) AS integer) = ?;",
        [asset, year, month]
      ).first.first
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
