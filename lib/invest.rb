require "sqlite3"
require "csv"
require "date"

class Invest
  EVENTS_FILE = "data/events.csv".freeze
  PRICES_FILE = "data/prices.csv".freeze
  INDEXES_FILE = "data/indexes.csv".freeze
  IBOVESPA_FILE = "data/ibovespa.csv".freeze

  CSV_OPTIONS = {
    headers: true,
    quote_char: '"',
    force_quotes: true
  }

  attr_reader :options, :queries

  # Public: Initializes the Invest class.
  #
  # options - initialization options
  def initialize(options = nil)
    @options = options || {
      ignore: []
    }

    @queries = ["BEGIN TRANSACTION"]

    import_data_from_events!
    import_data_from_prices!
    import_data_from_indexes!
    import_data_from_ibovespa!

    @queries << "COMMIT"
    db.execute_batch(@queries.join(";"))
  end

  # Public: Generates an html report.
  #
  # file - the file to output the report to.
  #
  # Returns nothing.
  def html_report!(file)
    puts "Generating output to #{file}"

    Html.new(events_query).save!(file)
  end

  # Public: Gets the events query instance.
  def events_query
    EventsQuery.new(self)
  end

  # Public: Gets the in memory sqlite database with the data imported from
  # data/data.csv.
  #
  # Returns a SQLite3::Database.
  def db
    @db ||= begin
      File.delete("tmp/invest.db") if File.exist?("tmp/invest.db")
      db = SQLite3::Database.new("tmp/invest.db")

      db.execute <<-SQL
        create table events (
          date text,
          asset text,
          category text,
          quantity integer,
          price integer,
          brokerage integer
        );
      SQL

      db.execute <<-SQL
        create table indexes (
          date text,
          asset text,
          value integer
        );
      SQL

      db.execute <<-SQL
        create table ibovespa (
          asset text
        );
      SQL

      db
    end
  end

  private

  # Private: Imports data from the data/events.csv to the sqlite db.
  #
  # Returns nothing.
  def import_data_from_events!
    puts "Importing data from #{EVENTS_FILE}"

    @queries += read_csv(EVENTS_FILE).map do |event|
      date, asset, category, quantity, price, brokerage = event.to_a.map(&:last)

      next if event.header_row? || options[:ignore].include?(asset)

      begin
        # formats values before sending to the db
        date = Date.strptime(date, '%Y-%m-%d').to_s
        quantity = quantity.gsub(",", ".").to_f * 100
        price = price.gsub(",", ".").to_f * 100
        brokerage = brokerage.gsub(",", ".").to_f * 100

        %{insert into events (date, asset, category, quantity, price, brokerage)
          values ("#{date}", "#{asset}", "#{category}", #{quantity}, #{price}, #{brokerage})}
      rescue NoMethodError
        puts "Invalid row #{event}"
        raise
      end
    end
  end

  # Private: Imports data from the data/prices.csv to the sqlite db.
  #
  # Returns nothing.
  def import_data_from_prices!
    puts "Importing data from #{PRICES_FILE}"

    @queries += read_csv(PRICES_FILE).map do |event|
      date, asset, category, price = event.to_a.map(&:last)

      next if event.header_row? || options[:ignore].include?(asset)

      # formats values before sending to the db
      date = Date.strptime(date, '%Y-%m-%d').to_s
      price = price.gsub(",", ".").to_f * 100

      %{insert into events (date, asset, category, quantity, price, brokerage)
        values ("#{date}", "#{asset}", "#{category}", 0, #{price}, 0)}
    end
  end

  # Private: Imports data from the data/indexes.csv to the sqlite db.
  #
  # Returns nothing.
  def import_data_from_indexes!
    puts "Importing data from #{INDEXES_FILE}"

    @queries += read_csv(INDEXES_FILE).map do |event|
      date, asset, value = event.to_a.map(&:last)

      next if event.header_row? || options[:ignore].include?(asset)

      # formats values before sending to the db
      date = Date.strptime(date, '%Y-%m-%d').to_s
      value = value.gsub(",", ".").to_f * 100

      %{insert into indexes (date, asset, value) values ("#{date}", "#{asset}", #{value})}
    end
  end

  # Private: Imports data from the data/ibovespa.csv to the sqlite db.
  #
  # Returns nothing.
  def import_data_from_ibovespa!
    puts "Importing data from #{IBOVESPA_FILE}"

    @queries += read_csv(IBOVESPA_FILE).map do |line|
      asset = line.to_a.first.last

      %{insert into ibovespa (asset) values ("#{asset}")}
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

require_relative "invest/queries/events"
require_relative "invest/html"
