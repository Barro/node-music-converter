class RetryTimeouter
        constructor: (@minTimeout=1000, @maxTimeout=30000) ->
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
                swap_position = Math.floor(Math.random() * (shuffled.length - insert_position))
                swappable = shuffled[insert_position + swap_position]
                shuffled[insert_position + swap_position] = shuffled[insert_position]
                shuffled[insert_position] = swappable
        return shuffled


class SongQueue
        constructor: ->
                _.extend @, Backbone.Events
                @allSongs = []
                @visibleSongs = []
                @queuedSongs = []
                @playbackFiles = []
                @nextSong = null
                @nextLength = 0

        updateAll: (@allSongs) =>
                @trigger "updateAll", @allSongs

        updateVisible: (@visibleSongs) ->
                @playbackFiles = []
                @trigger "updateVisible", @visibleSongs

        length: =>
                length = @queuedSongs.length + @nextLength
                return length

        next: =>
                next = @peek()
                @nextSong = null
                @nextLength = 0
                if next != null
                        @trigger "next", next
                return next

        peek: =>
                if @nextSong != null
                        return @nextSong
                if @queuedSongs.length > 0
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

        add: (song) =>
                @queuedSongs.push song
                # Replace current random song with the first queued song.
                if @nextSong != null and @nextLength == 0
                        @nextSong = null
                        @peek()
                @trigger "add", song
                return @queuedSongs.length

        remove: (index) =>
                [removed] = @queuedSongs.splice(index, 1)
                @trigger "remove", song, index
                return removed

        show: =>
                return @queuedSongs


class PlaybackType
        constructor: (@request, @mime) ->


class Player
        constructor: (@playerElement, @timeouter, @playbackType) ->
                _.extend @, Backbone.Events
                @player = @playerElement.get(0)
                @currentSong = null
                @lastPreload = null
                @_bind()

        _bind: =>
                @playerElement.bind "pause", =>
                        @trigger "pause"
                @playerElement.bind "play", =>
                        @trigger "resume"
                @playerElement.bind "volumechange", =>
                        @trigger "volumechange", @player.volume

        play: (song) =>
                @trigger "play", song
                [index, file] = song
                @playerElement.empty()
                encodedPath = encodeURIComponent file
                @playerElement.append "<source src=\"/file/#{encodedPath}?type=#{@playbackType.request}\" type='#{@playbackType.mime}' />"
                @player.load()
                @player.play()
                @currentSong = file

        preload: (song) =>
                if @lastPreload == song
                        return
                @lastPreload = song
                [index, file] = song
                encodedPath = encodeURIComponent file
                songPath = "/file/#{encodedPath}?type=#{@playbackType.request}"
                @trigger "preloadStart", song
                request = $.get(songPath)
                errorCallback = =>
                        setTimeout (=> @preload song),
                                @timeouter.increaseTimeout()
                request.error errorCallback
                request.success =>
                        @timeouter.reset()
                        @trigger "preloadOk", song

        togglePause: =>
                if @player.paused
                        @player.play()
                else
                        @player.pause()

        setVolume: (value) =>
                @player.volume = value

        setPosition: (value) =>
                @trigger "position", value


PlayerView = (playerElement, player, songQueue) ->
        queueStatus = $("#queue-length", playerElement)
        songQueue.on "add", (song) ->
                queueStatus.text songQueue.length()
        songQueue.on "remove", (song) ->
                queueStatus.text songQueue.length()
        songQueue.on "next", (song) ->
                queueStatus.text songQueue.length()

        songQueue.on "next", (song) ->
                player.play song

        nextSongButton = $("#next", playerElement)
        nextSongButton.click ->
                songQueue.next()

        nextSongStatusElement = $("#status-next", playerElement)

        player.on "play", (song) ->
                player.preload songQueue.peek()
        songQueue.on "add", (song) ->
                player.preload songQueue.peek()

        lastPreloadSong = null
        player.on "preloadStart", (song) ->
                lastPreloadSong = song
                [index, file] = song
                nextSongStatusElement.text file
        player.on "preloadOk", (song) ->
                if song == lastPreloadSong
                        nextSongStatusElement.append "<span style='color: green'>&nbsp;✓</span>"

        playSongButton = $("#play-control", playerElement)
        playSongButton.click ->
                player.togglePause()

        player.on "pause", ->
                playSongButton.text "Play"
        player.on "resume", ->
                playSongButton.text "Pause"
        playerElement.bind "ended", songQueue.next

        currentSongStatusElement = $("#status-current", playerElement)
        player.on "play", (song) ->
                [index, file] = song
                currentSongStatusElement.text file

        slider = $(".volume-slider", playerElement)
        player.on "volumechange", (volume) ->
                slider.attr "value", volume * slider.attr "max"
                $(".volume-intensity", playerElement).text Math.round 100 * volume

        slider.bind "change", ->
                me = $(@)
                newVolume = me.val() / (me.attr("max") - me.attr("min"))
                player.setVolume newVolume


QueueView = (queueElement, queueTable, queue, player) ->
        queue.on "next", (song) ->


        $("tr", queueElement).live "click", ->
                aPos = queueTable.fnGetPosition @
                iPos = aPos[0]

                song = queue.remove aPos
                queueTable.fnDeleteRow iPos
                player.play song


PlaylistView = (playlistElement, songData, player, queue) ->
        columns = [ { "bSearchable": false, "bVisible": false}, { "sTitle": "Song" } ]

        tableProperties =
                sScrollY: "450px"
                sDom: "frtiS"
                bDeferRender: true
                aaData: songData
                aoColumns: columns

        table = playlistElement.dataTable tableProperties

        hashChange = ->
                if document.location.hash.length <= 1
                        return
                songName = document.location.hash.substr(1)
                if songName == player.currentSong
                        return
                $(songData).each (element, index) =>
                        [index, file] = element
                        if file == songName
                                player.play element
                                return false

        hashChange()

        $(window).bind "hashchange", hashChange

        lastIndex = 0
        player.on "play", (song) ->
                oldRow = table.fnGetData lastIndex
                $(oldRow).remove(".playing")
                [newIndex, file] = song
                newRow = table.fnGetData newIndex
                $(newRow).add(".playing")

        $('tr', playlistElement).live "click", ->
                aData = table.fnGetData @
                song = aData
                queue.add song


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
        playerInstance = new Player playerJquery, timeouter, playbackType
        songQueue = new SongQueue()

        PlayerView playerContainer, playerInstance, songQueue

        $.getJSON "/files", (data) =>
                songData = []
                $.each data, (key, index) =>
                        songData.push([index, key])

                songQueue.updateAll songData

                PlaylistView $("#playlist"), songData, playerInstance, songQueue
