require "erb"
require "money"
require "sass"

I18n.enforce_available_locales = false

class Invest
  class Html
    TEMPLATES_PATH = "lib/invest/templates/html/"

    attr_reader :events

    # define delegators to events
    %i(year_range categories asset_month_input).each do |m|
      define_method(m) do |*args|
        events.send(m, *args)
      end
    end

    # Public: Initializes the Html class.
    #
    # events - the events instance.
    def initialize(events)
      @events = events
    end

    # Public: Saves the html report.
    #
    # file - the file to save to
    #
    # Returns nothing.
    def save!(file)
      File.write(file, ERB.new(
        File.read(File.join(TEMPLATES_PATH, "report.html.erb"))).result(binding))
    end

    # Public: Outputs the css.
    #
    # Returns a String.
    def css
      Sass::Engine.new(
        File.read(File.join(TEMPLATES_PATH, "report.scss")),
        syntax: :scss
      ).render
    end

    # Public: Adds a span to a number to include classes based on negative/positive.
    #
    # formatted - the formatted value
    # value - the original numeric value
    #
    # Returns a string.
    def number_span(formatted, value)
      if value > 0
        %(<span class="positive">#{formatted}</span>)
      elsif value < 0
        %(<span class="negative">#{formatted}</span>)
      else
        %(<span class="neutral">#{formatted}</span>)
      end
    end

    # Public: Formats a numeric value as a money.
    #
    # value - the numeric value
    #
    # Returns a String.
    def money(value, span: true)
      if value
        formatted_value = Money.new(value * 100).format(symbol: "")

        if span
          number_span(formatted_value, value)
        elsif value
          formatted_value
        end
      end
    end
  end
end
