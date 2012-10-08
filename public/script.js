function getPlayerObjects() {
    var playerContainer =  $("#player");
    var playerJquery = $("audio", playerContainer);
    var player = playerJquery.get(0);
    return {player: player, jquery: playerJquery};
}

var SONGS = [];
var PLAYBACK_TYPES = {ogg: 'audio/ogg', mp3: 'audio/mpeg'};
var PLAYBACK_TYPE = null;
var nextSong = null;

function preloadSong(successCallback) {
    var item = Math.floor(Math.random() * SONGS.length);
    nextSong = SONGS[item];
    var nextStatus = $("#status-next");
    nextStatus.empty();
    nextStatus.text(nextSong);
    var encodedPath = encodeURIComponent(nextSong);
    var songPath = "/file/" + encodedPath + "?type=" + PLAYBACK_TYPE;
    var request = $.get(songPath);
    var errorCallback = function() {
        setTimeout(function() { preloadSong(successCallback); }, 1000);
    }
    request.error(errorCallback);
    request.success(function() {
        if (successCallback) {
            successCallback();
        } else {
            nextStatus.append("<span style='color: green'>&nbsp;✓</span>");
        }
    });

    // var player = new Audio();
    // var playerContainer = $("#player-preloaded");
    // playerContainer.empty();
    // playerContainer.append(player);
    // var playerJquery = $(player);
    // var encodedPath = encodeURIComponent(nextSong);
    // playerJquery.append("<source src='/file/" + encodedPath + "?type=ogg' type='audio/ogg' />");
    // playerJquery.append("<source src='/file/" + encodedPath + "?type=mp3' type='audio/mpeg' />");
    // playerJquery.attr("preload", "auto");
}

function playRandomSong() {
    var song = nextSong;
    $("#status").text(song);
    var player = getPlayerObjects();
    player.player.pause();
    player.jquery.empty();

    var encodedPath = encodeURIComponent(song);
    var audio_type = PLAYBACK_TYPES[PLAYBACK_TYPE];
    player.jquery.append("<source src=\"/file/" + encodedPath + "?type=" + PLAYBACK_TYPE + "\" type='" + audio_type + "' />");

    player.player.load();
    player.player.play();

    preloadSong();
}

$("#next").click(function() {
    playRandomSong();
});

$(document).ready(function() {
    var audio = new Audio();
    if (audio.canPlayType("audio/ogg")) {
        PLAYBACK_TYPE = "ogg";
    } else if (audio.canPlayType("audio/mpeg")) {
        PLAYBACK_TYPE = "mp3";
    } else {
        $("#status").text("Your browser does not support Vorbis or MP3");
        return;
    }

    var player = getPlayerObjects();
    player.jquery.attr("controls", "controls");

    $.getJSON("/files", function (data) {
        $.each(data, function(key, value) {
            SONGS.push(key);
        });
        player.jquery.bind("ended", playRandomSong);
        // player.jquery.bind("stalled", playRandomSong);
        // player.jquery.bind("error", playRandomSong);
        // player.jquery.bind("abort", playRandomSong);
        // player.jquery.bind("suspend", playRandomSong);
        // player.jquery.bind("emptied", playRandomSong);
        preloadSong(playRandomSong);
    });
});