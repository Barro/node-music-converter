SEARCH_UPDATE_PRELOAD_DELAY = 2000
CONVERSION_WAIT_TIMEOUT = 180 * 60 * 1000

simpleNormalizeName = (name) ->
        return name.replace /\s+/g, "-"

class RetryTimeouter
        constructor: (@minTimeout=500, @maxTimeout=5000) ->
                @reset()

        increaseTimeout: =>
                timeout = @nextTimeout
                @nextTimeout = timeout + @lastTimeout
                if @nextTimeout > @maxTimeout
                        @nextTimeout = @maxTimeout
                @lastTimeout = timeout
                return timeout

        reset: =>
                @nextTimeout = @minTimeout
                @lastTimeout = @minTimeout


shuffledList = (list) ->
        shuffled = list.slice()
        for insert_position in [0..shuffled.length-1]
                swap_position = parseInt Math.random() * (shuffled.length - insert_position)
                swappable = shuffled[insert_position + swap_position]
                shuffled[insert_position + swap_position] = shuffled[insert_position]
                shuffled[insert_position] = swappable
        return shuffled


class SongQueue
        constructor: (@storage) ->
                _.extend @, Backbone.Events
                @allSongs = []
                @visibleSongs = []
                if @storage.queue
                        @queuedSongs = JSON.parse @storage.queue
                else
                        @queuedSongs = []
                @playbackFiles = []
                @nextSong = null
                @nextLength = 0

        updateAll: (@allSongs) =>
                @trigger "updateAll", @allSongs

        updateVisible: (newVisibleSongs) ->
                if @visibleSongs == newVisibleSongs
                        return
                @visibleSongs = newVisibleSongs
                @playbackFiles = []
                @_removeRandom()
                @trigger "updateVisible", @visibleSongs

        length: =>
                length = @queuedSongs.length + @nextLength
                return length

        next: =>
                next = @peek()
                @clearNext()
                if next != null
                        @trigger "next", next
                return next

        clearNext: =>
                @storage.queue = JSON.stringify @queuedSongs
                @nextSong = null
                @nextLength = 0

        peek: =>
                if @nextSong != null
                        return @nextSong
                if @queuedSongs.length > 0
                        @storage.queue = JSON.stringify @queuedSongs
                        song = @queuedSongs.shift()
                        @nextSong = song
                        @nextLength = 1
                        return song

                if @visibleSongs.length == 0
                        if @allSongs.length == 0
                                return null
                        playbackCandidates = @allSongs
                else
                        playbackCandidates = @visibleSongs

                if @playbackFiles.length == 0
                        @playbackFiles = shuffledList playbackCandidates
                song = @playbackFiles.pop()
                @nextSong = song
                return song

        _removeRandom: =>
                # Replace current random song with the first queued song.
                if @nextSong != null and @nextLength == 0
                        @nextSong = null
                        @peek()

        add: (song) =>
                @queuedSongs.push song
                @storage.queue = JSON.stringify @queuedSongs
                @_removeRandom()
                @trigger "add", song
                return @queuedSongs.length

        remove: (index) =>
                [removed] = @queuedSongs.splice(index, 1)
                @storage.queue = JSON.stringify @queuedSongs
                @trigger "remove", song, index
                return removed

        show: =>
                return @queuedSongs


class PlaybackType
        constructor: (@request, @mime) ->


class Player
        constructor: (@playerElement, @storage, @timeouter, @playbackType) ->
                _.extend @, Backbone.Events
                @player = @playerElement.get(0)
                if @storage.currentSong
                        try
                                @currentSong = JSON.parse @storage.currentSong
                        catch error
                                @currentSong = null
                else
                        @currentSong = null
                @continuePosition = 0
                if @storage.continuePosition
                        @lastPosition = @storage.continuePosition
                else
                        @lastPosition = 0
                @preloads = {}
                @_bind()
                if @storage.volume
                        @setVolume @storage.volume
                @startedPlaying = false

        _bind: =>
                @playerElement.bind "pause", =>
                        @trigger "pause"
                @playerElement.bind "play", =>
                        @trigger "resume"
                @playerElement.bind "ended", =>
                        @trigger "ended"
                @playerElement.bind "volumechange", =>
                        @storage.volume = @player.volume
                        @trigger "volumechange", @player.volume
                @playerElement.bind "timeupdate", =>
                        @storage.continuePosition = @player.currentTime
                        @trigger "timeupdate", @player.currentTime, @player.duration
                @playerElement.bind "durationchange", =>
                        @trigger "durationchange", @player.duration

                @playerElement.bind "loadeddata", =>
                        if @continuePosition
                                @player.currentTime = @continuePosition
                                @continuePosition = 0
                        @player.play()
                        @trigger "play", @currentSong

        resumePlaying: =>
                @continuePosition = @lastPosition
                @play @currentSong

        play: (song) =>
                @playerElement.empty()
                encodedPath = encodeURIComponent song.filename
                @playerElement.append "<source src=\"/file/#{encodedPath}?type=#{@playbackType.request}\" type='#{@playbackType.mime}' />"
                @player.load()
                @currentSong = song
                @storage.currentSong = JSON.stringify @currentSong
                # Preload the currently playing song to handle cases where we
                # fail to play the requested song. As audio element does not
                # send any events on failed playback, we need to use another
                # trick to detect failures.
                @preload song, false
                @startedPlaying = true

        preload: (song, react=true) =>
                console.log "player#preload #{song.title} #{react}"
                if song.filename of @preloads
                        console.log "player#preload #{song.title} return"
                        return
                @preloads[song.filename] = new Date()
                encodedPath = encodeURIComponent song.filename
                songPath = "/file/#{encodedPath}?type=#{@playbackType.request}"
                @trigger "preloadStart", song, react

                settings =
                        type: "HEAD"
                        timeout: CONVERSION_WAIT_TIMEOUT
                request = $.ajax songPath, settings
                failCallback = =>
                        @trigger "preloadFailed", song, react
                errorCallback = =>
                        delete @preloads[song.filename]
                        setTimeout failCallback, @timeouter.increaseTimeout()
                request.error errorCallback
                request.success =>
                        delete @preloads[song.filename]
                        @timeouter.reset()
                        @trigger "preloadOk", song, react

        togglePause: =>
                if @player.paused
                        @player.play()
                else
                        @player.pause()

        setVolume: (value) =>
                @player.volume = value

        getVolume: =>
                return @player.volume

        setPosition: (value) =>
                @player.currentTime = value

        getPosition: =>
                return @player.currentTime

        isPlaying: =>
                return @player.networkState != @player.NETWORK_NO_SOURCE


viewTimeString = (total_seconds) ->
        hours = parseInt total_seconds / 3600
        remaining_seconds = total_seconds - hours * 3600
        minutes = parseInt remaining_seconds / 60
        remaining_seconds -= minutes * 60
        seconds = parseInt remaining_seconds
        hours_str = ""
        if hours > 0
                hours_str = "#{hours}:"

        time_str = hours_str + _.str.sprintf "%02d:%02d", minutes, seconds
        return time_str


PlayerView = (playerElement, player, songQueue) ->
        queueStatus = $("#queue-length", playerElement)
        queueStatus.text songQueue.length()
        songQueue.on "add", (song) ->
                console.log "add -> queuestatus"
                queueStatus.text songQueue.length()
        songQueue.on "remove", (song) ->
                console.log "remove -> queuestatus"
                queueStatus.text songQueue.length()
        songQueue.on "next", (song) ->
                console.log "next -> queuestatus"
                queueStatus.text songQueue.length()

        songQueue.on "next", (song) ->
                console.log "next -> player.play"
                player.play song

        nextSongButton = $("#next", playerElement)
        nextSongButton.click ->
                console.log "nextSongButton.click -> next"
                songQueue.next()

        nextSongStatusElement = $("#preload-status", playerElement)

        player.on "play", (song) ->
                console.log "player.play preload"
                player.preload songQueue.peek(), true

        lastPreloadSong = null
        player.on "preloadStart", (song, react) ->
                console.log "player.preloadStart #{react}"
                if not react
                        console.log "player.preloadStart -> noreact"
                        return
                lastPreloadSong = song
                newsong = $("<span class='notloaded'>✘</span>")
                newsong.attr "title", "#{song.artist} / #{song.album} / #{song.title}"
                nextSongStatusElement.html newsong

        player.on "preloadFailed", (song, react) ->
                console.log "player.preloadFailed #{react}"
                songQueue.clearNext()
                newSong = songQueue.peek()
                if react
                        console.log "player.preloadFailed -> react"
                player.preload newSong, react

        player.on "preloadOk", (song, react) ->
                console.log "player.preloadOk #{song.title} #{react}"
                if not react
                        return
                if song == lastPreloadSong
                        console.log "player.preloadOk #{song.title} -> lastPreloadSong"
                        newsong = $(".notloaded", nextSongStatusElement)
                        newsong.removeClass "notloaded"
                        newsong.addClass "loaded"
                        newsong.text "✓"

                if not player.isPlaying()
                        console.log "player.preloadOk #{song.title} -> notPlaying"
                        player.play song

        preloadOnQueueChange = ->
                if songQueue.peek() == lastPreloadSong
                        return
                player.preload songQueue.peek(), true

        songQueue.on "add", preloadOnQueueChange
        songQueue.on "remove", preloadOnQueueChange
        songQueue.on "updateAll", preloadOnQueueChange

        lastUpdateDelayId = 0
        delayedQueueChangePreload = ->
                lastUpdateDelayId++
                updateDelayId = lastUpdateDelayId
                updateOnChange = (delayId) ->
                        console.log "update on change"
                        if updateDelayId != lastUpdateDelayId
                                console.log "not newest"
                                return
                        preloadOnQueueChange()
                setTimeout updateOnChange, SEARCH_UPDATE_PRELOAD_DELAY
        songQueue.on "updateVisible", delayedQueueChangePreload

        playSongButton = $("#play-control", playerElement)
        playSongButton.click ->
                console.log "playSongButton.click"
                if player.isPlaying()
                        console.log "playSongButton.click -> isPlaying"
                        player.togglePause()
                else
                        console.log "playSongButton.click -> queueNext"
                        songQueue.next()

        player.on "pause", ->
                playSongButton.text "Play"
        player.on "resume", ->
                playSongButton.text "Pause"
        player.on "ended", ->
                console.log "player.ended -> next"
                songQueue.next()

        currentSongStatusElement = $("#status-current", playerElement)
        artistElement = $("#artist", currentSongStatusElement)
        albumElement = $("#album", currentSongStatusElement)
        titleElement = $("#title", currentSongStatusElement)
        player.on "play", (song) ->
                artistElement.text song.artist
                albumElement.text song.album
                titleElement.text song.title

        artistElement.click ->
                searchValue = "artist:#{simpleNormalizeName artistElement.text()}-"
                console.log searchValue
                $("#search").val(searchValue).change()
        albumElement.click ->
                searchValue = "album:#{simpleNormalizeName albumElement.text()}-"
                console.log searchValue
                $("#search").val(searchValue).change()

        volumeSlider = $(".volume-slider", playerElement)
        showVolume = (volume) ->
                volumeSlider.attr "value", volume * volumeSlider.attr "max"
                $(".volume-intensity", playerElement).text Math.round 100 * volume
        player.on "volumechange", (volume) ->
                showVolume volume

        showVolume player.getVolume()

        volumeSlider.bind "change", ->
                me = $(@)
                newVolume = me.val() / (me.attr("max") - me.attr("min"))
                player.setVolume newVolume

        positionSlider = $(".position-slider", playerElement)
        positionElement = $(".current-position", playerElement)
        player.on "timeupdate", (currentTime, duration) ->
                positionSlider.attr "value", currentTime
                positionElement.text viewTimeString currentTime

        positionSlider.bind "change", ->
                me = $(@)
                player.setPosition me.val()

        positionSlider.val player.getPosition()

        durationElement = $(".duration", playerElement)
        player.on "durationchange", (duration) ->
                positionSlider.attr "max", duration
                durationElement.text viewTimeString duration


QueueView = (queueButton, queueElement, queue, player) ->
        queue.on "next", (song) ->
                # remove from queue

        queueButton.on "click", ->
                # show queue

        table = null

        $("tr", queueElement).live "click", ->
                aPos = queueTable.fnGetPosition @
                iPos = aPos[0]

                song = queue.remove aPos
                queueTable.fnDeleteRow iPos
                player.play song


PlaylistView = (playlistElement, songData, player, queue, router, search) ->
        columns = []
        columns.push { "bSearchable": false, "bVisible": false}
        columns.push { "bSearchable": false, "sTitle": "Artist", "bSortable": false, "sClass": "artist", "sWidth": "10em" }
        columns.push { "bSearchable": false, "sTitle": "Album", "bSortable": false, "sClass": "album", "sWidth": "10em" }
        columns.push { "bSearchable": false, "sTitle": "Title", "bSortable": false, "sClass": "title", "sWidth": "10em" }

        tableData = []
        for song, index in songData
                artist = song.artist or 'UNKNOWN'
                album = song.album or 'UNKNOWN'
                title = song.title or 'UNKNOWN'
                tableData.push([index, artist, album, title])

        tableProperties =
                sScrollY: "430px"
                sDom: "rtiS"
                bDeferRender: true
                aaData: tableData
                aoColumns: columns

        table = playlistElement.dataTable tableProperties

        table.on "filter", (event, settings) =>
                queue.updateVisible $.map settings.aiDisplay, (value, index) =>
                        return [ songData[value] ]

        lastHashChange = null

        # TODO forward/backward does not work due to resumption functionality.
        hashChange = (songName) ->
                if lastHashChange == songName
                        return
                lastHashChange = songName

                # Front page for the first time:
                if (not player.startedPlaying) and (not songName?)
                        if player.currentSong
                                console.log "resume playing"
                                player.resumePlaying()
                        else
                                console.log "next song"
                                queue.next()
                        return

                # Hash change while player has already started playing
                # something.
                if player.startedPlaying
                        if songName == player.currentSong.filename
                                console.log "current song"
                                return

                # Cases where the song is selected through the hash element
                # change.
                $(songData).each (index, element) =>
                        song = songData[index]
                        if song.filename == songName
                                console.log "playing"
                                player.play song
                                queue.clearNext()
                                return false

        router.on "play", hashChange

        # TODO highlight currently playing song
        # lastIndex = 0
        # player.on "play", (song) ->
        #         oldRow = table.fnGetData lastIndex
        #         $(oldRow).remove(".playing")
        #         [newIndex, file] = song
        #         newRow = table.fnGetData newIndex
        #         $(newRow).add(".playing")

        lastSong = null

        player.on "play", (song) ->
                if lastHashChange != song.filename
                        router.navigate "/" + song.filename

        $('tr', playlistElement).live "click", ->
                aData = table.fnGetData @
                [index, data...] = aData
                console.log index
                queue.add songData[index]

        table.fnFilter = (string) ->
                oSettings = @fnSettings()
                # Tell the draw function we have been filtering
                search.search string, (result) =>
                        oSettings.bFiltered = true
                        oSettings.aiDisplay = result
                        $(oSettings.oInstance).trigger('filter', oSettings);
                        # Redraw the table
                        oSettings._iDisplayStart = 0;
                        @_fnCalculateEnd oSettings
                        @_fnDraw oSettings

        if search.lastSearch
                $("#search").val search.lastSearch
                table.fnFilter search.lastSearch
        doSearch = ->
                searchValue = $("#search").val()
                if searchValue == search.lastSearch
                        return
                table.fnFilter searchValue
        $("#search").keyup doSearch
        $("#search").change doSearch


class PlayerRouter extends Backbone.Router
        routes:
                "": 'playSong'
                "*filename": 'playSong'

        playSong: (filename) =>
                if filename?
                        filename = "/" + decodeURIComponent(filename)
                @trigger "play", filename


class Search
        constructor: (@storage) ->
                _.extend @, Backbone.Events
                @worker = new Worker "frontend/search.js"
                @worker.onmessage = (event) =>
                        @_handle event.data
                @searchId = 0
                @searchCallbacks = {}
                if @storage.lastSearch
                        @lastSearch = @storage.lastSearch
                else
                        @lastSearch = ''

        _handle: (data) =>
                if data.type == "initialize"
                        @_handleInitialize()
                else if data.type == "result"
                        @_handleResult data
                else if data.type == "message"
                        console.log data.message
                else
                        throw new Error "Unknown message type #{data.type}"

        _handleInitialize: =>
                # Handle case where we initialize search in the page load.
                if @searchId of @searchCallbacks
                        callback = @searchCallbacks[@searchId]
                        @searchCallbacks[@searchId] = (matches) =>
                                callback matches
                                @trigger "initialize"
                else
                        @trigger "initialize"

        _handleResult: (result) =>
                callback = @searchCallbacks[result.searchId]
                delete @searchCallbacks[result.searchId]
                # Only accept results from the latest search.
                if result.searchId == @searchId
                        matches = result.matches
                        callback matches
                        @trigger "result", result

        initialize: (songs) =>
                @worker.postMessage {type: "initialize", songs: songs}

        search: (string, callback) =>
                @searchId++
                @searchCallbacks[@searchId] = callback
                @lastSearch = string
                @storage.lastSearch = string
                @worker.postMessage {type: "search", searchId: @searchId, value: string}


HotkeysView = (player, queue) ->
        $(document).bind "keypress.b", ->
                queue.next()
        $(document).bind "keypress.x", ->
                player.togglePause()

$(document).ready ->
        audio = new Audio();
        playbackType = null
        if (audio.canPlayType("audio/ogg"))
                playbackType = new PlaybackType "ogg", "audio/ogg"
        else if (audio.canPlayType("audio/mpeg"))
                playbackType = new PlaybackType "mp3", "audio/mpeg"
        else
                $("#status").text("Your browser does not support Vorbis or MP3")
                return

        playerContainer =  $("#player")
        playerJquery = $("audio", playerContainer)
        timeouter = new RetryTimeouter()
        playerInstance = new Player playerJquery, localStorage, timeouter, playbackType
        songQueue = new SongQueue localStorage


        PlayerView playerContainer, playerInstance, songQueue
        HotkeysView playerInstance, songQueue

        router = new PlayerRouter()

        QueueView $("#toggle-queue"), $("#queue"), songQueue, playerInstance

        search = new Search localStorage

        $.getJSON "/files", (data) =>
                directories = data.directories
                for index in [1..(directories.length - 1)]
                        directory = directories[index]
                        [parent, name] = directory.split "/"
                        directories[index] = "#{directories[parseInt(parent)]}/#{name}"

                files = []
                for fileinfo, index in data.files
                        fileObject = {}
                        for field, index in data.fields
                                if index < fileinfo.length
                                        fileObject[field] = fileinfo[index]
                        if fileObject.filename.indexOf("/") != -1
                                [directory, basename] = fileObject.filename.split "/"
                                fileObject.filename = "#{directories[parseInt(directory)]}/#{basename}"

                        # This guess is often wrong as not everything is
                        # organized like this, but this is usually better
                        # than showing nothing.
                        if not fileObject.artist or not fileObject.album or not fileObject.title
                                filenameParts = fileObject.filename.split "/"
                                [artistPart, albumPart, titlePart] = filenameParts[(filenameParts.length - 3)..(filenameParts.length - 1)]
                                fileObject.artist = fileObject.artist or artistPart
                                fileObject.album = fileObject.album or albumPart
                                fileObject.title = fileObject.title or titlePart

                        files.push fileObject

                search.initialize files

                songQueue.updateAll files

                PlaylistView $("#playlist"), files, playerInstance, songQueue, router, search

                search.on "initialize", ->
                        Backbone.history.start()
