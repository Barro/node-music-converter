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

normalizeKey = (value) ->
        normalized = value
        normalized = normalized.replace /\s+/g, '-'
        normalized = normalized.replace /-+/g, '-'

        normalized = normalized.toLowerCase()

        normalized = normalized.replace "album:", "#{Identifier.ALBUM}:"
        normalized = normalized.replace "title:", "#{Identifier.TITLE}:"
        normalized = normalized.replace "artist:", "#{Identifier.ARTIST}:"

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


createSearchIndex = (song) ->
        index = song.filename.toLowerCase()
        if song.album
                album = normalizeKey (song.album_normalized or song.album)
                index += " #{Identifier.ALBUM}:#{album}"
        if song.title
                title = normalizeKey (song.title_normalized or song.title)
                index += "-#{Identifier.TITLE}:#{title}"
        if song.artist
                artist = normalizeKey (song.artist_normalized or song.artist)
                index += "-#{Identifier.ARTIST}:#{artist}-"
        return index


class SearchCache
        constructor: ->
                @searchCache = {"": []}
                @searchDatabase = []

        setDatabase: (@searchDatabase) =>
                fullList = [0...@searchDatabase.length]
                @searchCache[""] = fullList

        initialize: (songs) =>
                @searchDatabase = []
                for song in songs
                        @searchDatabase.push createSearchIndex song
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
                SEARCH_CACHE.initialize data.songs
                message =
                        type: "initialize"
                self.postMessage message
        else
                throw new Error "Unknown message type #{data.type}"
