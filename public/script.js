var SONGS = [];
var nextSong = null;

function preloadSong() {
    var item = Math.floor(Math.random() * SONGS.length);
    nextSong = SONGS[item];
    var player = new Audio();
    var playerContainer = $("#player-preloaded");
    playerContainer.empty();
    playerContainer.append(player);
    var playerJquery = $(player);
    var encodedPath = encodeURIComponent(nextSong);
    playerJquery.append("<source src='/file/" + encodedPath + "?type=ogg' type='audio/ogg' />");
    playerJquery.append("<source src='/file/" + encodedPath + "?type=mp3' type='audio/mpeg' />");
    playerJquery.attr("preload", "auto");
}

function playRandomSong() {
    var song = nextSong;
    $("#status").text(song);
    preloadSong();
    var playerContainer =  $("#player");
    var oldPlayerJquery = $("audio", playerContainer);
    oldPlayerJquery.get(0).pause();
    playerContainer.empty();

    var preloadedContainer =  $("#player-preloaded");
    var preloadedJquery =  $("audio", preloadedContainer);
    playerContainer.append(preloadedJquery);

    var playerJquery = $("audio", playerContainer);
    playerJquery.attr("controls", "controls");
    var player = playerJquery.get(0);
    player.play();
}

$("#next").click(function() {
    playRandomSong();
});

$(document).ready(function() {
    $.getJSON("/files", function (data) {
        $.each(data, function(key, value) {
            SONGS.push(key);
        });
        preloadSong();
        playRandomSong();
    });
});