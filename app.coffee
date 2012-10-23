express = require 'express'
nodefs = require 'node-fs'
optimist = require 'optimist'
winston = require 'winston'

argv = optimist
        .default("port", 8080)
        .default("cache-directory", "/tmp/.nmc")
        .argv
[datafile] = argv._

app = express()

cacheDir = argv['cache-directory']
nodefs.mkdirSync cacheDir, 0o0755, true
cacheLocation = "/converted"

loggerParams =
        transports: [new winston.transports.Console {colorize: true}]
logger = new winston.Logger loggerParams
winstonStream =
        write: (message, encoding) ->
                logger.info message

app.configure =>
        app.set 'views',"#{__dirname}/views"
        app.set 'view engine', 'jade'
        app.use express.logger {stream: winstonStream}
        app.use "/frontend", express.static "#{__dirname}/build/frontend"
        app.use "/external", express.static "#{__dirname}/external"
        app.use cacheLocation, express.static cacheDir

app.get '/', (req, res) ->
        res.render "index"

FileDatabase = require './file-database'

Playlist = require "./playlist"

files = new FileDatabase.FileDatabaseView cacheDir, cacheLocation, logger

app.get '/files', files.view

FileConverter = require './file-converter'
cache = new FileConverter.FileCache cacheDir, cacheLocation
converter = new FileConverter.FileConverterView logger, files, cache

app.get '/file/*', converter.view

parser = new Playlist.Parser logger
parser.parse datafile, (err, result) ->
        if err
                logger.error "Failed to read data file: #{err}."
                return
        files.open result, (err) =>
                if err
                        logger.error "Failed to create playlist data: #{err}."
                        return
                server = app.listen argv.port
                server.on "listening", (err, value) ->
                        console.log "Listening to port #{argv.port}."
