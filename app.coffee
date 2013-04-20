connectAssets = require "connect-assets"
express = require "express"
gzippo = require "gzippo"
nodefs = require "node-fs"
optimist = require "optimist"
util = require "./util"
winston = require "winston"
_s = require "underscore.string"

argv = optimist
  .default("port", 8080)
  .describe("port", "The port that this server listens for connections.")
  .default("cache-directory", "/tmp/.nmc")
  .describe("cache-directory", "Cache directory for temporary files.")
  .default("root-path", "/")
  .describe("root-path", "Server root that all requests go to.")
  .default("prefixes", null)
  .describe("prefixes",
    "A list of file prefixes that can be removed and still maintain unique filenames.")
  .usage("Usage: $0 [options] PLAYLIST")
  .demand(1)
  .argv
[datafile] = argv._

assets = connectAssets {src: "#{__dirname}/frontend", buildDir: "#{__dirname}/build/frontend"}
css.root = "/"
js.root = "/"

app = express()

cacheDir = argv['cache-directory']
nodefs.mkdirSync cacheDir, 0o0755, true

root = _s.rstrip argv['root-path'], "/"
urlPath = (path) ->
  return "#{root}/#{path}"

cacheLocation = urlPath "converted"

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
  app.use urlPath("external"), gzippo.staticGzip "#{__dirname}/external"
  app.use cacheLocation, gzippo.staticGzip cacheDir
  app.use assets

FileDatabase = require './file-database'

Playlist = require "./playlist"

prefixStripper = new util.PrefixStripper []
prefixesFile = argv['prefixes']
if prefixesFile
  prefixStripper = util.createPrefixStripper prefixesFile

files = new FileDatabase.FileDatabaseView prefixStripper, cacheDir, cacheLocation, logger

indexView = (req, res) ->
  res.render "index", {root: urlPath(''), cacheKey: files.cacheKey}
if root
  app.get root, indexView
app.get urlPath(''), indexView

app.get urlPath('files'), files.view

FileConverter = require './file-converter'
cache = new FileConverter.FileCache cacheDir, cacheLocation
converter = new FileConverter.FileConverterView logger, files, cache

app.get urlPath('file/*'), converter.redirectView
app.get urlPath('preload/*'), converter.preloadView

parser = new Playlist.Parser logger
files.open parser, datafile, (err) ->
  if err
    logger.error "Failed to create playlist data: #{err}."
    return
  server = app.listen argv.port
  server.on "listening", (err, value) ->
    console.log "Listening to port #{argv.port} at path #{root}."
