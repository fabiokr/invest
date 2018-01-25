require "erb"
require "money"

I18n.enforce_available_locales = false

class Invest
  class Html
    attr_reader :invest

    # Public: Initializes the Html class.
    #
    # invest - the invest instance.
    def initialize(invest)
      @invest = invest
    end

    # Public: Saves the html report.
    #
    # file - the file to save to
    #
    # Returns nothing.
    def save!(file)
      File.write(file, ERB.new(
        File.read("lib/invest/templates/report.html.erb")).result(binding))
    end
  end
end
