require "erb"
require "money"
require "sass"

I18n.enforce_available_locales = false

class Invest
  class Html
    TEMPLATES_PATH = "lib/invest/templates/html/"

    attr_reader :events

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
        formatted_value = Money.new(value).format(symbol: "")

        if span
          number_span(formatted_value, value)
        elsif value
          formatted_value
        end
      end
    end

    # Public: Formats a numeric value as a percent.
    #
    # value - the numeric value
    #
    # Returns a String.
    def percent(value, span: true)
      if value
        formatted_value = "%.2f\%%" % (value * 100).round(2)

        if span
          number_span(formatted_value, value)
        else
          formatted_value
        end
      end
    end

    # Public: Formats a numeric value as a number.
    #
    # value - the numeric value
    #
    # Returns a String.
    def number(value)
      if value
        "%.2f" % (value).round(2)
      end
    end

    # Public: Delegates missing methods to events if possible.
    def method_missing(method, *args, &block)
      if events.respond_to?(method)
        events.send(method, *args, &block)
      else
        super
      end
    end

    # Public: Checks if events can respond to missing.
    def respond_to_missing?(method, include_private = false)
      if events.respond_to?(method, include_private)
        true
      else
        super
      end
    end
  end
end
