getPlayerObjects = ->
    playerContainer =  $("#player")
    playerJquery = $("audio", playerContainer)
    player = playerJquery.get(0)
    return {player: player, jquery: playerJquery}

SONGS = []
PLAYBACK_TYPES = {ogg: 'audio/ogg', mp3: 'audio/mpeg'}
PLAYBACK_TYPE = null
nextSong = null

preloadSong = (successCallback) ->
    item = Math.floor(Math.random() * SONGS.length)
    nextSong = SONGS[item];
    nextStatus = $("#status-next")
    nextStatus.empty()
    nextStatus.text(nextSong)
    encodedPath = encodeURIComponent(nextSong)
    songPath = "/file/#{encodedPath}?type=#{PLAYBACK_TYPE}"
    request = $.get(songPath)
    errorCallback = =>
        setTimeout (-> preloadSong(successCallback)), 1000
    request.error errorCallback
    request.success =>
        if (successCallback)
            successCallback()
        else
            nextStatus.append("<span style='color: green'>&nbsp;✓</span>")

    # // var player = new Audio();
    # // var playerContainer = $("#player-preloaded");
    # // playerContainer.empty();
    # // playerContainer.append(player);
    # // var playerJquery = $(player);
    # // var encodedPath = encodeURIComponent(nextSong);
    # // playerJquery.append("<source src='/file/" + encodedPath + "?type=ogg' type='audio/ogg' />");
    # // playerJquery.append("<source src='/file/" + encodedPath + "?type=mp3' type='audio/mpeg' />");
    # // playerJquery.attr("preload", "auto");

playRandomSong = ->
    song = nextSong
    $("#status").text(song)
    player = getPlayerObjects()
    player.player.pause()
    player.jquery.empty()

    encodedPath = encodeURIComponent(song)
    audioType = PLAYBACK_TYPES[PLAYBACK_TYPE]
    player.jquery.append("<source src=\"/file/#{encodedPath}?type=#{PLAYBACK_TYPE}\" type='#{audioType}' />")

    player.player.load()
    player.player.play()

    preloadSong()

$("#next").click ->
    playRandomSong()

$("#pause").click ->
    player = getPlayerObjects()
    if (player.player.paused)
        player.player.play()
    else
        player.player.pause()
    if player.player.paused
        $("#pause").text "Play"
    else
        $("#pause").text "Pause"

$(document).ready ->
    audio = new Audio();
    if (audio.canPlayType("audio/ogg"))
        PLAYBACK_TYPE = "ogg"
    else if (audio.canPlayType("audio/mpeg"))
        PLAYBACK_TYPE = "mp3"
    else
        $("#status").text("Your browser does not support Vorbis or MP3")
        return

    player = getPlayerObjects()
    player.jquery.attr("controls", "controls")

    $.getJSON "/files", (data) =>
        $.each data, (key, value) =>
            SONGS.push(key)

        player.jquery.bind "ended", playRandomSong
        # // player.jquery.bind("stalled", playRandomSong);
        # // player.jquery.bind("error", playRandomSong);
        # // player.jquery.bind("abort", playRandomSong);
        # // player.jquery.bind("suspend", playRandomSong);
        # // player.jquery.bind("emptied", playRandomSong);
        preloadSong playRandomSong
