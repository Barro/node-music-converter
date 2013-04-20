importScripts "../external/js/unorm.min.js"

log = (message) ->
  data =
    type: "message"
    message: message
  self.postMessage data

Identifier =
  ALBUM: "a"
  TITLE: "t"
  ARTIST: "r"

IdentifierStr =
  ALBUM: " #{Identifier.ALBUM}:"
  TITLE: " #{Identifier.TITLE}:"
  ARTIST: " #{Identifier.ARTIST}:"

IdentifierStrRaw =
  ALBUM: "#{Identifier.ALBUM}:"
  TITLE: "#{Identifier.TITLE}:"
  ARTIST: "#{Identifier.ARTIST}:"

normalizeKey = (value) ->
  normalized = value
  normalized = normalized.replace /[\s\-]+/g, '-'

  normalized = normalized.toLowerCase()

  if normalized.indexOf("title:") != -1
    normalized = normalized.replace "title:", IdentifierStrRaw.TITLE
  if normalized.indexOf("album:") != -1
    normalized = normalized.replace "album:", IdentifierStrRaw.ALBUM
  if normalized.indexOf("artist:") != -1
    normalized = normalized.replace "artist:", IdentifierStrRaw.ARTIST

  return normalized


parseKeywords = (searchValue) ->
  cleaned = UNorm.nfkd searchValue
  cleaned = cleaned.replace(/^\s+/, '')
  cleaned = cleaned.replace(/\s+$/, '')
  keywords = cleaned.split /\s+/
  keywordsNormalized = []
  for keyword in keywords
    if keyword == ""
      continue
    keywordsNormalized.push normalizeKey keyword
  return keywordsNormalized


createSearchList = (keywords) ->
  unorderedKeywords = (keyword for keyword in keywords)
  unorderedKeywords.sort (a, b) ->
    if (b.length - a.length) == 0
      if a == b
        return 0
      else if a < b
        return -1
      else
        return 1
    return b.length - a.length
  lastKeyword = null
  keywordsUnique = []
  for keyword in unorderedKeywords
    if keyword != lastKeyword
      keywordsUnique.push keyword
    lastKeyword = keyword
  return keywordsUnique


createSearchIndex = (directories, fileData, fields) ->
  filename = fileData[fields.filename_normalized] or fileData[fields.filename]
  directory = directories[fileData[fields.directory]]
  index = [directory + "/" + normalizeKey filename]

  title = fileData[fields.title_normalized] or fileData[fields.title]
  if title
    index.push IdentifierStr.TITLE
    index.push normalizeKey title

  album = fileData[fields.album_normalized] or fileData[fields.album]
  if album
    index.push IdentifierStr.ALBUM
    index.push normalizeKey album

  artist = fileData[fields.artist_normalized] or fileData[fields.artist]
  if artist
    index.push IdentifierStr.ARTIST
    index.push normalizeKey artist

  return index.join ""


class SearchCache
  constructor: ->
    @searchCache = {"": []}
    @searchDatabase = []

  setDatabase: (@searchDatabase) =>
    fullList = [0...@searchDatabase.length]
    @searchCache[""] = fullList

  initialize: (data) =>
    directories = data.directories

    for directory, index in directories
      [parentStr, name, normalizedName] = directory.split "/"
      if not normalizedName
        normalizedName = name
      if parentStr == ""
        continue
      parent = parseInt parentStr
      directories[index] = directories[parent] + "/" + normalizedName

    for directory, index in directories
      directories[index] = normalizeKey directory

    @searchDatabase = []

    fields = {}
    for fieldName, fieldIndex in data.fields
      fields[fieldName] = fieldIndex

    for file, index in data.files
      @searchDatabase.push createSearchIndex directories, file, fields
    @setDatabase @searchDatabase
    return @searchDatabase

  _getBaseCache: (key) =>
    baseCacheKey = key
    searchIndexes = @searchCache[""]
    while baseCacheKey != ""
      if baseCacheKey of @searchCache
        searchIndexes = @searchCache[baseCacheKey]
        break
      baseCacheKey =  baseCacheKey.substring 0, baseCacheKey.length - 1
    return searchIndexes


  search: (value) =>
    keywords = parseKeywords value
    searchWords = createSearchList keywords

    searchKey = searchWords.join " "
    if searchKey of @searchCache
      return @searchCache[searchKey]

    keywordKey = keywords.join " "
    if keywordKey of @searchCache
      return @searchCache[keywordKey]

    searchIndexes = @_getBaseCache searchKey
    if keywordKey != searchKey
      keywordIndexes = @_getBaseCache keywordKey
      if keywordIndexes.length < searchIndexes.length
        searchIndexes = keywordIndexes

    result = []
    for index in searchIndexes
      haystack = @searchDatabase[index]
      found = true
      for keyword in searchWords
        if haystack.indexOf(keyword) == -1
          found = false
          break
      if found == true
        result.push index

    # Save some memory by not creating a new list if all items
    # are in the older list.
    if result.length == searchIndexes.length
      result = searchIndexes

    @searchCache[keywordKey] = result
    @searchCache[searchKey] = result
    return result


SEARCH_CACHE = new SearchCache()


self.onmessage = (event) ->
  data = event.data
  if data.type == "search"
    result = SEARCH_CACHE.search data.value
    message =
      type: "result"
      searchId: data.searchId
      matches: result
    self.postMessage message
  else if data.type == "initialize"
    SEARCH_CACHE.initialize data.data
    message =
      type: "initialize"
    self.postMessage message
  else
    throw new Error "Unknown message type #{data.type}"
