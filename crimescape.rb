require 'sinatra/base'
require 'sinatra/cross_origin'
require 'redis'
require 'csv'
require 'open-uri'
require 'json'

class CrimeScape < Sinatra::Base
  register Sinatra::CrossOrigin

  MAX_HOURS = 72
  WEATHER_CSV = "https://www.dropbox.com/s/e49qru4cltthvm9/Weather_Forecasts.csv?raw=1"
  TRACTS_CSV = "https://www.dropbox.com/s/n48n2bbfwb6si9c/Crime%20Prediction%20CSV%20MOCK%20-%20revised.csv?raw=1"
  EXCLUDE_COLUMNS = ['id', 'hournumber']
  WEATHER_LEGEND = ["dt", "wind_speed", "relative_humidity", "hourly_precip", "drybulb_fahrenheit", "Assault Accuracy Rate", "Robbery Accuracy Rate", "ViolentCrime Accuracy Rate"]

  configure do
    enable :cross_origin
  end

  def initialize(app = nil, params = {})
    super(app)

    @redis = Redis.new(url: ENV['REDIS_URL'])
  end

  # Home
  get '/' do
    File.read(File.join('public', 'index.html'))
  end

  get '/tract/:tract_num' do
    File.read(File.join('public', 'index.html'))
  end

  get '/about' do
    File.read(File.join('public', 'index.html'))
  end

  # 404 Error
  not_found do
    redirect to('/')
  end

  """
    ENDPOINTS
      Home: /
      Hours: /hour0.json
      Tract: /tract10900.json
  """

  # Hour
  get %r{/hour([0-9]|[1-6][0-9]|7[0-1]).json$} do
    hour_index = params[:captures][0]

    results = weather_for(hour_index)
    results[:hourindex] = hour_index
    results[:legend] = hour_legend
    results[:tracts] = tracts_for_hour(hour_index)

    results.to_json
  end

  # Tract
  get '/tract:tract_num.json' do
    tract_num = params[:tract_num]
    hours = tract_all_hours(tract_num)
    meta = chicago_tract_meta(tract_num)
    data_legend = tract_legend()

    weather_legend = weather_legend()
    first_weather = weather_for(0)

    metadata_legend = weather_legend - ['prediction_timestamp', 'year', 'hournumber']
    all_metadata = all_weather(metadata_legend)

    results = {}
    results[:tract] = tract_num
    results[:starting_time] = hours.first[data_legend.index('dt')]
    results[:prediction_timestamp] = first_weather['prediction_timestamp']
    results[:center] = meta['center']
    results[:legend] = data_legend
    results[:metadata_legend] = metadata_legend
    results[:metadata] = all_metadata
    results[:hours] = hours

    results.to_json
  end

  def load_data
    puts "Loading all data..."
    load_tracts
    load_weather
    load_chicago_tracts_meta
    puts "Loaded all data..."
  end

private
  def weather_for(hour_index)
    @redis.hgetall "weather:#{hour_index}"
  end

  def all_weather(cols)
    MAX_HOURS.times.collect { |h|
      @redis.hmget("weather:#{h}", cols)
    }
  end

  def tract_legend
    @redis.lrange "tract_legend", 1, -1
  end

  def hour_legend
    @redis.lrange "tract_legend", 5, 7
  end

  def weather_legend
    @redis.lrange "weather_legend", 0, -1
  end

  def tracts_for_hour(hour_index)
    @redis.keys("tract:*:#{hour_index}").each_with_object({}) do |key, hash|
      tract_num = key.split(':')[1]
      hash[tract_num] = @redis.lrange key, 5, 7
    end
  end

  def tract_all_hours(tract_num)
    sorted_keys = @redis.keys("tract:#{tract_num}:*").sort_by { |x| x.split(':').last.to_i }

    sorted_keys.collect do |key|
      @redis.lrange key, 1, -1
    end
  end

  def chicago_tract_meta(tract_num)
    JSON.parse @redis.get "chicago:#{tract_num}"
  end

  def load_weather
    puts "Loading weather..."

    # Fetch from URL
    csv = open(WEATHER_CSV) {|f| CSV.parse(f.read, headers: true)}

    # Legend
    @redis.del "weather_legend"
    @redis.rpush "weather_legend", csv.first.headers

    # Transform
    weather = csv.collect {|row| row.to_hash}
    weather.slice! MAX_HOURS, 1000

    # Cache
    weather.each_with_index {|hash, index| @redis.hmset "weather:#{index}", hash.flatten}
    @redis.set "cached:weather", 1

    # Return
    puts "Loaded weather..."
    weather
  end

  def load_tracts
    puts "Loading tracts..."

    # Fetch from URL
    csv = open(TRACTS_CSV) {|f| CSV.parse(f.read, headers: true)}

    # Delete excluded columns
    EXCLUDE_COLUMNS.each {|c| csv.delete(c) }

    # Legend
    @redis.del "tract_legend"
    @redis.rpush "tract_legend", csv.first.headers

    # Transform
    tracts = csv.each_with_object({}) do |row, hash|
      (hash[row['census_tra']] ||= []) << row.to_hash.values
    end

    # Cache
    tracts.each do |tract_num, hours|
      hours.slice(0, MAX_HOURS).each_with_index do |hour, index|
        hour_key = "tract:#{tract_num}:#{index}"
        @redis.del hour_key
        @redis.rpush hour_key, hour
      end
    end
    @redis.set "cached:tracts", 1

    # Return
    puts "Loaded tracts..."
    tracts
  end

  def load_chicago_tracts_meta
    puts "Loading Chicago tracts meta..."

    # Read
    data = JSON.parse File.read('chicago_tracts.json')

    # Transform
    chicago = data.each_with_object({}) do |obj, hash|
      tract_num = obj[0].to_i
      center = [obj[1]['properties']['TRACT_CE_3'], obj[1]['properties']['TRACT_CE_2']]
      path = obj[1]['geometry']['coordinates'][0]

      hash[tract_num] = {center: center, path: path}
    end

    # Cache
    chicago.each do |tract_num, meta|
      @redis.set "chicago:#{tract_num}", meta.to_json
    end
    @redis.set "cached:chicago", 1

    # Return
    puts "Loaded Chicago tracts meta..."
    chicago
  end
end
