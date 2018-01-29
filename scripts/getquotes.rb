require "net/http"
require "uri"
require "csv"
require "date"

config = {
  "BBAS3" => "31-Jul-2016",
  "ANIM3" => "01-Ago-2017",
  "BPAN4" => "01-Feb-2017",
  "BRKM5" => "01-Feb-2016",
  "CVCB3" => "01-Sep-2016",
  "ITSA4" => "01-Feb-2016",
  "RAIL3" => "01-Jul-2016",
  "SCAR3" => "01-Apr-2016",
  "CARD3" => "01-Jan-2017",
  "EZTC3" => "01-Jan-2017",
  "PTBL3" => "01-Aug-2017",
  "SHOW3" => "01-Jun-2017",
  "SHUL4" => "01-Jun-2017",
  "BRCR11" => "01-Sep-2017",
  "GGRC11" => "01-Sep-2017",
  "VISC11" => "01-Nov-2017",
}

output = []

config.each do |asset, date|
  puts "Doing #{asset}..."
  uri = URI.parse("https://finance.google.com/finance/historical?q=#{asset}&startdate=#{date}&output=csv")
  response = Net::HTTP.get_response(uri)
  csv = CSV.parse(response.body)
  csv = csv[1..-1].group_by { |l| [Date.parse(l[0]).year, Date.parse(l[0]).month] }
  csv.each do |date, l|
    output << [Date.parse(l.first[0]).strftime("%Y-%m-%d"), asset, "Acoes", l.first[4].gsub(".", ",")]
  end
end

content = CSV.generate do |csv|
  output.each { |l| csv << l }
end

File.write("tmp/cotacoes.csv", content)
