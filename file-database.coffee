crypto = require 'crypto'
fs = require 'fs'
path = require "path"
lazy = require 'lazy'
unorm = require 'unorm'


stripEmptyItems = (list) ->
  while list[list.length - 1] == ""
    list.pop()
  return list


normalizeAttribute = (attribute) ->
  if not attribute
    return ""
  attributeNormalized = unorm.nfkd attribute
  if attribute == attributeNormalized
    return ""
  return attributeNormalized


class FilenameShortener
  constructor: ->
    @directoryId = 0
    @directoryIds = {"": 0}
    @directories = [""]

  shorten: (filename) =>
    parts = filename.split "/"
    # Remove filename
    basename = parts.pop()
    if parts.length == 0
      return basename

    firstPart = parts.shift()
    fullDirectory = firstPart
    if firstPart of @directoryIds
      currentId = @directoryIds[firstPart]
    else
      currentId = @directories.length
      addPart = "" + firstPart
      # This style of directory normalization adds 1.1 %
      # with my test set to the compressed file size.
      normalizedPart = normalizeAttribute firstPart
      if normalizedPart
        addPart += "/#{normalizedPart}"
      @directories.push addPart
      @directoryIds[fullDirectory] = firstPart

    for part in parts
      fullDirectory += "/#{part}"
      if fullDirectory of @directoryIds
        currentId = @directoryIds[fullDirectory]
      else
        normalizedPart = normalizeAttribute part
        addPart = "#{currentId}/#{part}"
        if normalizedPart
          addPart += "/#{normalizedPart}"
        @directories.push addPart
        currentId = @directories.length - 1
        @directoryIds[fullDirectory] = currentId
    return "#{currentId}/#{basename}"

defaultShortener = new FilenameShortener()


exports.FileDatabaseView = class FileDatabaseView
  constructor: (@cacheDir, @cacheLocation, @log, @filenameShortener=defaultShortener) ->
    @filenames = {}
    @cacheKey = ""

  _cacheName: (type) =>
    return "#{@cacheKey}.#{type}.json"

  _cachePath: (type) =>
    return path.join @cacheDir, @_cacheName(type)

  _readCacheData: (filename, callback) =>

    stream = fs.ReadStream filename
    stream.on "error", (err) =>
      @log.info "Failed to read playlist cache: #{err}."
      callback err
    fileDataStr = ""
    stream.on "data", (data) =>
      fileDataStr += data
    stream.on "end", =>
      try
        fileData = JSON.parse fileDataStr
      catch err
        @log.warn "Failed to parse playlist cache data: #{err}."
        callback err
        return
      callback null, fileData

  _assignFileinfo: (fileData, callback) =>
    @filenames = fileData.filenames
    @cacheKey = fileData.cacheKey
    callback null

  _createChecksum: (filename, callback) =>
    hash = crypto.createHash "sha512"
    stream = fs.ReadStream filename
    stream.on "error", (err) =>
      @log.error "Failed to open playlist file '#{filename}': #{err}."
      callback err
    stream.on "data", (data) ->
      hash.update data
    stream.on "end", ->
      checksum = hash.digest "hex"
      callback null, checksum

  _processCacheData: (err, parser, filename, fileData, callback) =>
    if not err
      @log.info "Loaded cached file database for #{filename}"
      @filenames = @_createFileMap fileData
      callback null
      return
    parser.parse filename, (err, files) =>
      if err
        callback err
        return
      @filenames = @_createFileMap files
      @_createCache files, callback

  _createCache: (files, callback) =>
    filesFilename = @_cachePath "filedata"
    fs.writeFile filesFilename, JSON.stringify(files), "utf-8", (err) =>
      if err
        @log.warn "Failed to create file info cache file: #{filesFilename}."

    playlistData = @_createPlayerDatabase files
    playlistFilename = @_cachePath "playlist"
    fs.writeFile playlistFilename, JSON.stringify(playlistData), "utf-8", (err) =>
      if err
        @log.warn "Failed to create playlist cache file: #{playlistFilename}."
      callback null, files

  open: (parser, filename, callback) =>
    @_createChecksum filename, (err, checksum) =>
      if err
        callback err
        return
      @cacheKey = checksum
      @_readCacheData @_cachePath("filedata"), (err, fileData) =>
        @_processCacheData err, parser, filename, fileData, callback

  _createFileMap: (files) =>
    filenames = {}
    # TODO unicode normalization for file names.
    for fileinfo in files
      filenames[fileinfo.filename] = fileinfo.filename
    return filenames

  _createPlayerDatabase: (files) =>
    @log.info "Creating a new file database."
    shortFiles = []
    fields = ["filename", "title", "artist", "album", "filename_normalized", "title_normalized", "artist_normalized", "album_normalized"]

    for fileinfo in files
      if not fileinfo.filename
        continue

      shortenedFilename = @filenameShortener.shorten fileinfo.filename
      file = [shortenedFilename]

      file.push fileinfo.title or ""
      file.push fileinfo.artist or ""
      file.push fileinfo.album or ""

      # By adding normalized items in the end of these arrays
      # we have about 10 % increase in the song list size
      # when compressed and 20 % increse when uncompressed.
      # This is when songs have quite many kana characters on
      # average in their names and about 40 % of songs have
      # at least one attribute that gets normalized.
      # This is probably faster to do here than on the client
      # side when taking into account that clients can be
      # really slow but the relative download time increase
      # is not that high.

      nodirFilename = shortenedFilename.replace /^\d+\//, ""
      file.push normalizeAttribute nodirFilename
      file.push normalizeAttribute fileinfo.title
      file.push normalizeAttribute fileinfo.artist
      file.push normalizeAttribute fileinfo.album

      file = stripEmptyItems file
      shortFiles.push file

    filedata = {}
    filedata.directories = @filenameShortener.directories
    filedata.files = shortFiles
    filedata.fields = fields
    @log.info "Finished reading file data."
    return filedata

  exists: (filename) =>
    return filename of @filenames

  getPath: (filename) =>
    return @filenames[filename]

  _getLocation: =>
    return "#{@cacheLocation}/#{@_cacheName('playlist')}"

  view: (request, response) =>
    console.log request.path
    location = @_getLocation()
    response.set "location", location
    response.send "Go to #{location}", 302
