require "sqlite3"
require "csv"
require "date"

class Invest
  EVENTS_FILE = "data/events.csv".freeze

  CSV_OPTIONS = {
    headers: true,
    quote_char: '"',
    force_quotes: true
  }

  def initialize
    import_data_from_events!
  end

  private

  # Private: Gets the in memory sqlite database with the data imported from
  # data/data.csv.
  #
  # Returns the SQLite3::Database.
  def db
    @db ||= begin
      db = SQLite3::Database.new(":memory:")

      db.execute <<-SQL
        create table events (
          date text,
          asset text,
          category text,
          quantity integer,
          price decimal(20, 10),
          brokerage decimal(20, 10)
        );
      SQL

      db
    end
  end

  # Private: Imports data from the data/events.csv to the sqlite db.
  #
  # Returns nothing.
  def import_data_from_events!
    read_csv(EVENTS_FILE).map do |event|
      next if event.header_row?

      date, asset, category, quantity, price, brokerage = event.to_a.map(&:last)

      # formats values before sending to the db
      date = Date.strptime(date, '%d/%m/%y').to_s

      db.execute "insert into events (date, asset, category, quantity, price, brokerage) values (?, ?, ?, ?, ?, ?)",
        [date, asset, category, quantity, price, brokerage]
    end
  end

  # Private: Reads a CSV file.
  #
  # file_path - the csv file path
  #
  # Returns a CSV.
  def read_csv(file_path)
    if File.exists?(file_path)
      CSV.read(file_path, CSV_OPTIONS)
    else
      []
    end
  end
end
