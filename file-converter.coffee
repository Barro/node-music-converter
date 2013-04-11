child_process = require 'child_process'
crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
_s = require "underscore.string"
temp = require 'temp'

# 1 minute of 160 kbps music.
FAILED_CONVERSION_IS_OK_SIZE = 60 * 160 * 1000 / 8

FFMPEG = "ffmpeg"
XMP = "xmp"

class ModPreprocessor
  knownTypes: ["it", "xm", "mod", "s3m", "mtm"]

  constructor: (@log) ->

  canPreprocess: (source) =>
    suffix = source.replace /.+\./, ""
    suffix = suffix.toLowerCase()
    if suffix in @knownTypes
      return true
    return false

  preprocess: (source, callback) =>
    resultFile = temp.path {suffix: ".wav"}
    @log.debug "Started preprocessing #{source} to #{resultFile}."
    options =
      cwd: "/tmp/"
    args = ["--nocmd", "-o", resultFile, source]
    xmp = child_process.spawn XMP, args, options
    @log.debug "Started xmp with #{XMP} #{_s.join ' ', args...}."
    xmp.on "error", =>
      throw new Error "No xmp executable '#{XMP}' in path!"
    xmp.stdout.on 'data', (data) ->
    xmp.stderr.on 'data', (data) ->
    xmp.on 'exit', (code) =>
      if code != 0
        err = "Exited with non-0 status!"
      else
        err = null
      @log.debug "Finished preprocessing #{source} to #{resultFile} with exit status #{code}."
      callback err, resultFile


class AudioConverter
  constructor: (@log) ->

  _conversionDone: (target, code, callback) =>
    @log.debug "Converted with code #{code} to #{target}"
    if code != 0
      # We have failed file conversion. Let's check
      # if the resulting file is large enough so that
      # we can accept the conversion anyway.
      fs.stat target, (err, stats) ->
        if err
          callback "Failed file conversion. No file exists."
          return
        if stats.size >= FAILED_CONVERSION_IS_OK_SIZE
          @_audioGain target, callback
          return
        callback "Failed file conversion. Not enough data converted (#{stats.size} bytes)."
      return
    @_audioGain target, callback


class OpusConverter extends AudioConverter
  suffix: =>
    return "opus"

  audioType: =>
    return "audio/opus"

  mimeType: =>
    return "audio/ogg"

  _audioGain: (target, callback) =>
    callback null

  convert: (source, bitrate, target, callback) =>
    options =
      cwd: "/tmp/"
    args = ["-i", source, '-vn', '-acodec', 'libopus', '-ab', bitrate, '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', '-y', target]
    @log.debug "Starting Opus conversion: #{FFMPEG} #{args.join(' ')}"
    ffmpeg = child_process.spawn FFMPEG, args, options
    ffmpeg.stdout.on 'data', (data) ->
    ffmpeg.stderr.on 'data', (data) ->
    ffmpeg.on "error", =>
      throw new Error "No ffmpeg executable '#{FFMPEG}' in path!"
    ffmpeg.on 'exit', (code) =>
      @_conversionDone target, code, callback


class VorbisConverter extends AudioConverter
  suffix: =>
    return "ogg"

  audioType: =>
    return "audio/ogg"

  mimeType: =>
    return "application/ogg"

  _audioGain: (target, callback) =>
    options =
      cwd: "/tmp/"
    @log.debug "Starting Vorbis audio gain for #{target}"
    vorbisgain = child_process.spawn "vorbisgain", [target], options
    vorbisgain.stdout.on 'data', (data) ->
    vorbisgain.stderr.on 'data', (data) ->
    vorbisgain.on "error", =>
      @log.warn "Unable to execute vorbisgain for #{target}"
      callback null
    vorbisgain.on 'exit', (code) =>
      @log.debug "Audio gain for #{target}"
      callback null

  convert: (source, bitrate, target, callback) =>
    options =
      cwd: "/tmp/"
    args = ["-i", source, '-vn', '-acodec', 'libvorbis', '-ab', bitrate, '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', '-y', target]
    @log.debug "Starting Vorbis conversion: #{FFMPEG} #{args.join(' ')}"
    ffmpeg = child_process.spawn FFMPEG, args, options
    ffmpeg.stdout.on 'data', (data) ->
    ffmpeg.stderr.on 'data', (data) ->
    ffmpeg.on "error", =>
      throw new Error "No ffmpeg executable '#{FFMPEG}' in path!"
    ffmpeg.on 'exit', (code) =>
      @_conversionDone target, code, callback


class Mp3Converter extends AudioConverter
  suffix:  =>
    return "mp3"

  audioType: =>
    return "audio/mpeg"

  mimeType: =>
    return "audio/mpeg"

  _audioGain: (target, callback) =>
    options =
      cwd: "/tmp/"
    mp3gain = child_process.spawn "mp3gain", [target], options
    mp3gain.stdout.on 'data', (data) ->
    mp3gain.stderr.on 'data', (data) ->
    mp3gain.on "error", =>
      @log.warn "Unable to execute mp3gain for #{target}"
      callback null
    mp3gain.on 'exit', (code) =>
      callback null

  convert: (source, bitrate, target, callback) =>
    options =
      cwd: "/tmp/"
    args = ["-i", source, '-vn', '-acodec', 'libmp3lame', '-ab', bitrate, '-y', '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', target]
    @log.debug "Starting MP3 conversion: #{FFMPEG} #{args.join(' ')}"
    ffmpeg = child_process.spawn FFMPEG, args, options
    ffmpeg.stdout.on 'data', (data) ->
    ffmpeg.stderr.on 'data', (data) ->
    ffmpeg.on "error", =>
      throw new Error "No ffmpeg executable '#{FFMPEG}' in path!"
    ffmpeg.on 'exit', (code) =>
      @_conversionDone target, code, callback


class FileCacheInstance
  constructor: (@cache, @conversionParams) ->

  createCache: (convertedFilename, callback) =>
    return @cache.createCache convertedFilename, @conversionParams, callback

  getCached: (callback) =>
    return @cache.getCached @conversionParams, callback

  getKey: =>
    return @cache.getDigest @conversionParams


exports.FileCache = class FileCache
  constructor: (@cachedir="/tmp", @cacheLocation) ->

  generate: (conversionParams) =>
    return new FileCacheInstance @, conversionParams

  getDigest: (conversionParams) ->
    paramList = []
    for key, value of conversionParams
      paramList.push("#{key}:#{value}")
    paramList.sort()
    parameters = paramList.join("|")
    hashable = "#{parameters}"
    hash = crypto.createHash("sha512")
    hash.update(hashable)
    return hash.digest("hex")

  _createFilename: (conversionParams) =>
    digest = @getDigest conversionParams
    filename = "#{digest}.#{conversionParams.suffix}"
    return filename

  _getCacheName: (conversionParams) =>
    filename = @_createFilename conversionParams
    return path.join @cachedir, filename

  _getLocation: (conversionParams) =>
    filename = @_createFilename conversionParams
    return "#{@cacheLocation}/#{filename}"

  getCached: (conversionParams, callback) =>
    filepath = @_getCacheName conversionParams
    fs.exists filepath, (exists) =>
      if not exists
        callback "File '#{filepath}' does not exist.", null
        return
      callback null, @_getLocation conversionParams

  createCache: (convertedFilename, conversionParams, callback) =>
    filepath = @_getCacheName conversionParams
    input = fs.createReadStream convertedFilename
    input.on "error", (err) =>
      console.log "Read stream error: #{err}"
    output = fs.createWriteStream filepath
    input.pipe output
    input.on "end", =>
      callback null, @_getLocation conversionParams

createPreloadCallback = (response) ->
  responseCallback = (headers, content, code) ->
    if code == 302
      response.send content
      return
    for header, value of headers
      response.set header, value
    response.send content, code
  return responseCallback

createRedirectCallback = (response) ->
  responseCallback = (headers, content, code) ->
    for header, value of headers
      response.set header, value
    response.send content, code
  return responseCallback

class FileConverter
  constructor: (@log, @cache)->
    @bitrate = "160k"
    @preprocessors = [new ModPreprocessor @log]
    @converters =
      mp3: new Mp3Converter @log
      ogg: new VorbisConverter @log
    @_ongoingConversions = {}

  _redirectToCachefile: (cacheInstance, response) =>

  _createResponse: (err, cacheInstance, tempname, callback) =>
    if err
      @log.error "Encoding error: #{err}."
      fs.exists tempname, (exists) =>
        if exists
          @log.debug "Unlinking file on error: #{tempname}."
          fs.unlink tempname, (err) =>
            if err
              @log.warn "Failed to unlink file #{tempname}: #{err}"
        callback {data: ["Failed to convert.", 500], headers: {}}
        return
      return
    fs.stat tempname, (statErr, stats) =>
      if statErr
        callback {data: ["Failed to read resulting file name.", 500], headers: {}}
        return
      cacheInstance.createCache tempname, (err, location) =>
        fs.unlink tempname, (err) =>
          if err
            @log.warn "Failed to unlink file #{tempname}: #{err}"
          else
            @log.debug "Unlinked #{tempname}."
        callback {data: ["Go to #{location}", 302], headers: {"location": location}}

  _conversionDone: (err, cacheInstance, tempname) =>
    @log.debug "Conversion finished."
    @_createResponse err, cacheInstance, tempname, (responseParams) =>
      @log.debug "Sending response to clients: #{tempname}."
      for response in @_ongoingConversions[cacheInstance.getKey()]
        [content, code] = responseParams.data
        response responseParams.headers, content, code
      delete @_ongoingConversions[cacheInstance.getKey()]

  convert: (type, filename, responseCallback) =>
    @log.info "Starting conversion of '#{filename}' to type #{type}."
    if type not of @converters
      responseCallback {}, "I do not know how to convert to type #{type}.", 406
      return
    converter = @converters[type]
    suffix = converter.suffix()
    conversionParams =
      filename: filename
      type: type
      suffix: suffix
      bitrate: @bitrate

    cacheInstance = @cache.generate conversionParams

    cacheInstance.getCached (err, location) =>
      if not err
        @log.debug "Found cached file of #{filename}"
        responseCallback {location: location}, "Go to #{location}", 302
        return

      fs.stat filename, (statErr, stats) =>
        if statErr
          responseCallback {}, "Failed to read original file name.", 500
          return

        cacheKey = cacheInstance.getKey()
        if cacheKey of @_ongoingConversions
          @log.debug "Adding #{cacheKey} to ongoing encodings."
          @_ongoingConversions[cacheKey].push responseCallback
          return
        else
          @log.debug "Creating new ongoing encoding cache key #{cacheKey}."
          @_ongoingConversions[cacheKey] = [responseCallback]

        tempname = temp.path {suffix: ".#{suffix}"}
        @log.debug "Created temporary target file path #{tempname}"
        preprocessed = false
        convertFile = (err, sourceName, delfile) =>
          @log.debug "Conversion done for #{sourceName} with error '#{err}' and cleanup #{delfile}."
          if err
            if delfile
              fs.unlink sourceName, (err) =>
                if err
                  @log.warn "Failed to delete source file #{sourceName}: #{err}"
                else
                  @log.debug "Unlinked #{sourceName}."
            @_conversionDone err, cacheInstance, tempname
            return
          converter.convert sourceName, @bitrate, tempname, (err) =>
            if delfile
              fs.unlink sourceName, (err) =>
                if err
                  @log.warn "Failed to delete source file #{sourceName}: #{err}"
                else
                  @log.debug "Unlinked #{sourceName}."
            @_conversionDone err, cacheInstance, tempname

        for preprocessor in @preprocessors
          if preprocessor.canPreprocess filename
            preprocessor.preprocess filename, (err, sourceName) =>
              convertFile err, sourceName, true
            preprocessed = true
            break
        if not preprocessed
          convertFile null, filename, false


exports.FileConverterView = class FileConverterView
  constructor: (@log, @fileDatabase, @cache, @defaultType="mp3") ->
    @converter = new FileConverter @log, @cache

  _convert: (request, responseCallback) =>
    filename = request.params[0]
    if not @fileDatabase.exists filename
      response.send "Not found", 404
      return
    fullPath = @fileDatabase.getPath filename
    targetType = request.query.type or @defaultType
    @converter.convert targetType, fullPath, responseCallback

  preloadView: (request, response) =>
    responseCallback = createPreloadCallback response
    @_convert request, responseCallback

  redirectView: (request, response) =>
    responseCallback = createRedirectCallback response
    @_convert request, responseCallback