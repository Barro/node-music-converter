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


class SongQueue extends Backbone.Events
        constructor: ->
                @allSongs = []
                @visibleSongs= []
                @queuedSongs = []
                @lastSong = null
                @playbackFiles = []

        loadSongs: (@allSongs) ->

        updateVisible: (@visibleSongs) ->
                @playbackFiles = []

        next: =>
                if @queuedSongs.length > 0
                        song = @queuedSongs.shift()
                        return song

                if @visibleSongs.length == 0
                        if @allSongs.length == 0
                                return null
                        playbackCandidates = @allSongs
                else
                        playbackCandidates = @visibleSongs

                if @playbackFiles.length == 0
                        @playbackFiles = shuffledList playbackCandidates
                return @playbackFiles.pop()

        add: (song) =>
                @queuedSongs.push song
                return @queuedSongs.length

        remove: (index) =>
                [removed] = @queuedSongs.splice(index, 1)
                return removed

        show: =>
                return @queuedSongs


class PlaybackType
        constructor: (@request, @mime) ->


class Player extends Backbone.Events
        constructor: (@playerElement, @currentSongElement, @nextSongElement, @timeouter, @playbackType) ->

        play: (song) =>
                @playerElement.empty()
                encodedPath = encodeURIComponent song
                @playerElement.append "<source src=\"/file/#{encodedPath}?type=#{@playbackType.request}\" type='#{@playbackType.mime}' />"
                player = @playerElement.get(0)
                player.load()
                player.play()

        _preload: (song, callback) =>
                encodedPath = encodeURIComponent song
                songPath = "/file/#{encodedPath}?type=#{@playbackType}"
                request = $.get(songPath)
                errorCallback = =>
                        setTimeout (-> @preload callback),
                                @timeouter.increaseTimeout()
                request.error errorCallback
                request.success =>
                        @trigger "preload", song
                        @timeouter.reset()

        togglePause: =>
                @playerElement.pause()

        setVolume: (value) =>

        queue: (song) =>

        unqueue: (song) =>

PlayerView = (playerElement, player, songQueue) ->
        nextSongElement = $("#status-next", playerElement)
        player.on "preload", (song) ->
                nextSongElement.append "<span style='color: green'>&nbsp;✓</span>"

        player.on "play", (song) ->

        $("#play-control", playerElement).click ->
                player.togglePaused()

        playerElement.bind "ended", player.next

        player.jquery.bind "volumechange", ->
                slider = $(".volume-slider")
                slider.attr("value", player.player.volume * slider.attr("max"))
                $(".volume-intensity").text(Math.round(100 * player.player.volume))

        player.jquery.bind "pause", ->
                $("#play-control").text "Play"
        player.jquery.bind "play", ->
                $("#play-control").text "Pause"

        $("#next").click ->
                playRandomSong()

        slider = $(".volume-slider")
        slider.attr("value", player.player.volume * slider.attr("max"))
        $(".volume-intensity").text(Math.round(100 * player.player.volume))
        slider.change ->
                me = $(@)
                newVolume = me.val() / (me.attr("max") - me.attr("min"))
                player.player.volume = newVolume


QueueView = (queueElement, queueTable, queue, player) ->
        queue.on "next", (song) ->


        $("tr", queueElement).live "click", ->
                aPos = queueTable.fnGetPosition @
                iPos = aPos[0]

                song = queue.remove aPos
                queueTable.fnDeleteRow iPos
                player.play song

        $('#playlist tr').live "click", ->
                aData = oTable.fnGetData( this )
                iId = aData[0]
                playSong iId


SonglistView = (songlistElement, queue) ->
        columns = [ { "sTitle": "Song" } ]

        tableProperties =
                sScrollY: "450px"
                sDom: "frtiS"
                bDeferRender: true
                aaData: queue.allSongs
                aoColumns: columns

        table = $(songlistElement).dataTable tableProperties

        queue.on "next", (song) ->

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
        player = playerJquery.get(0)
        timeouter = new RetryTimeouter()
        playerInstance = new Player playerJquery, $("#status"), $("#status-next"), timeouter, playbackType
        songQueue = new SongQueue()

        #$(window).bind "hashchange", playHashSong
        if document.location.hash.length > 1
                console.log "TODO Play hash song."
        else
                #preloadSong playRandomSong

        $.getJSON "/files", (data) =>
                songData = []
                $.each data, (key, value) =>
                        songData.push([key])
