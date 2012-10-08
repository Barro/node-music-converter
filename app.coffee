express = require 'express'
app = express()

app.configure =>
        app.set 'views',"#{__dirname}/views"
        app.set 'view engine', 'jade'
        app.use express.static "#{__dirname}/public"

optimist = require('optimist')
argv = optimist.default("port", 8080).argv
[datafile] = argv._

app.get '/', (req, res) ->
        res.render "index"

FileDatabase = require './file-database'

files = new FileDatabase.FileDatabaseView()
files.open datafile
app.get '/files', files.view

FileConverter = require './file-converter'
converter = new FileConverter.FileConverterView files

app.get '/file/*', converter.view

app.listen argv.port
