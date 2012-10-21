createSearchList = (value) ->
        searchValue = value.replace(/^\s+/, '')
        searchValue = searchValue.replace(/\s+$/, '')
        keywords = searchValue.split " "
        keywordsNormalized = []
        for keyword in keywords
                if keyword == ""
                        continue
                keywordsNormalized.push keyword.toLowerCase()
        keywordsNormalized.sort (a, b) ->
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
        for keyword in keywordsNormalized
                if keyword != lastKeyword
                        keywordsUnique.push keyword
                lastKeyword = keyword
        return keywordsUnique


createSearchIndex = (song) ->
        index = song.filename.toLowerCase()
        if song.album
                album = song.album.toLowerCase()
                index += " album:#{album}"
        if song.title
                title = song.title.toLowerCase()
                index += " title:#{title}"
        if song.artist
                artist = song.artist.toLowerCase()
                index += " artist:#{artist}"
        return index


class SearchCache
        constructor: ->
                @searchCache = {"": []}
                @searchDatabase = []

        initialize: (songs) =>
                @searchCache = {}
                fullList = [0...songs.length]
                @searchCache[""] = fullList
                @searchDatabase = []
                for song in songs
                        @searchDatabase.push createSearchIndex song
                        # @searchDatabase.push song.filename

        search: (value) =>
                keywords = createSearchList value
                cacheKey = keywords.join " "
                if cacheKey of @searchCache
                        return @searchCache[cacheKey]

                baseCacheKey = cacheKey
                searchIndexes = @searchCache[""]
                while baseCacheKey != ""
                        if baseCacheKey of @searchCache
                                searchIndexes = @searchCache[baseCacheKey]
                                break
                        baseCacheKey =  baseCacheKey.substring 0, baseCacheKey.length - 1
                result = []
                for index in searchIndexes
                        haystack = @searchDatabase[index]
                        found = true
                        for keyword in keywords
                                if haystack.indexOf(keyword) == -1
                                        found = false
                                        break
                        if found == true
                                result.push index
                @searchCache[cacheKey] = result
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
