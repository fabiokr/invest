class Invest
  class EventsQuery
    attr_reader :invest

    def initialize(invest)
      @invest = invest
    end

    # Public: Gets the year range from the events.
    #
    # Returns an array.
    def year_range
      db.execute(
        "SELECT DISTINCT strftime('%Y', date) AS year FROM events ORDER BY year;"
      ).map(&:first)
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
