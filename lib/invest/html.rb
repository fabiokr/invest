require "erb"
require "money"
require "sass"

I18n.enforce_available_locales = false

class Invest
  class Html
    TEMPLATES_PATH = "lib/invest/templates/html/"

    attr_reader :events

    # define delegators to events
    %i(year_range categories).each do |m|
      define_method(m) { events.send(m) }
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
  end
end
