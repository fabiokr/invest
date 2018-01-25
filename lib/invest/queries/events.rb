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

    private

    # Private: Gets the database instance.
    #
    # Returns a SQLite3::Database.
    def db
      invest.db
    end
  end
end
