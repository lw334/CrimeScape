# CrimeScape

## Overview

### Initial setup

You'll need Ruby, Sinatra and Redis installed. If you use Homebrew, follow these commands to install everything you need.

```
brew install redis
gem install bundler rerun
bundle install
```

Then run the data loading tool to populate Redis.

```
rake load_data
```

### Running locally

You'll need to fire up Redis as well as the Rack server. Use these two two commands in separate terminals:

```
redis-server
```

```
make server
```

### Running on Heroku

Once you commit changes to the `master` branch, push them to Heroku by typing:

```
git push heroku master
``` 

The `load_data` tool is scheduled to run hourly. If the server ever needs to be rebuilt, and you want to run the script manually, just type this:

```
heroku run rake load_data
```

Here are some other tools that may come in handy when developing on Heroku:

```
heroku logs
heroku restart
heroku ps:stop
heroku redis:cli
flushall
```

## Development assumptions


* The CSV will never change — no columns will get added or removed or moved around.
* Rows will always be in chronological order.
* The tract path points are LongLat, not LatLong.
* The center point is LatLong.

## API endpoints

There are two JSON endpoints.

##### [http://crimescape.herokuapp.com/hour0.json](http://crimescape.herokuapp.com/hour0.json)

This returns city-wide data for a given hour. It's used on the homepage. The `0` can be replaced with any number from 0-72.

##### [http://crimescape.herokuapp.com/tract10100.json](http://crimescape.herokuapp.com/tract10100.json)

This returns all data for a given tract, for use on the tract pages. The `10100` can be replaced with the five- or six-digit ID for a tract.

## Understanding the code

### JavaScript libraries

The site relies on the following libraries to run:

* [Angular](https://angularjs.org/) (v1.3.14)
* [Underscore](http://underscorejs.org/)
* [Mapbox](https://www.mapbox.com/) (v2.2.1)
* [Leaflet](http://leafletjs.com/) (v0.2.1)
* [Highcharts](http://www.highcharts.com/)
* [Highcharts-ng](https://github.com/pablojim/highcharts-ng)
* [date.format.js](https://github.com/jacwright/date.format)

All of these are served from CDNs except Highcharts-ng and date.format.js. Those two, along with all the custom scripts in `scripts.js`, are concatenated into a single file called `scripts-min.js`. This happens automatically on my end with a desktop app called CodeKit. You'll need to run that or something similar, or just edit `scripts-min.js` directly and remove the original three files that compose it.

### Sinatra

All the Ruby code for the Sinatra app is in `crimescape.rb`. 

The `load_data` function handles the import function. First it calls `load_tracts`, which loads all the tract data, and stores it with a key based on the tract number and hour index. Then it calls `load_weather`, which imports all the data that only changes per hour, not per tract. (This includes weather data as well as accuracy rates.) Then it calls `load_chicago_tracts_meta` which loads all the tract-specific data, like tract shape and center.

The two API endpoints are defined under the `# Hour` and `# Tract` headings. They accept a single argument (hour or tract ID) and lookup all the relevant data.

### Source files

To change the URLs of the CSVs that the app uses to gather data, simply change the values of `WEATHER_CSV` and `TRACTS_CSV` in `crimescape.rb`.

### Map

To change the tooltip on the homepage map, edit the `getTooltip` function in `scripts.js` (and/or `scripts-min.js` — see above).

### Charts

All the configuration data for the tract page charts are stored in the `chartConfig` object. The [Highcharts API docs](http://api.highcharts.com/highcharts) are very thorough; if you want to edit the charts, I recommend referencing those docs to understand what you need to change. 

Keep in mind that this object deviates slightly from a standard config object due to how it's being used by `highcharts-ng`, specifically within the `options` key of that object. Reference the docs for `highcharts-ng` for more info.

### CSS and SCSS

The CSS is written in SCSS and precompiled into CSS on the desktop end before committing. You'll need to run a preprocessor like CodeKit or Prepros in order to make further CSS edits. There is a bit of logic and efficiency built into the SCSS so I highly recommend against editing the CSS file directly.

### Static files

All images, CSS, and JS are served from the `/public` directory. The `get '/' do` line in `crimescape.rb` allows static files to be served this way.