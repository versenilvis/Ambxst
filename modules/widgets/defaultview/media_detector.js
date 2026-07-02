// cache of detected domains by track title
let domainCache = {};

function detectMedia(player, windowList) {
    let result = {
        title: "Unknown Track",
        artist: "Unknown Artist",
        domain: "",
        hasCustomInfo: false
    };

    if (!player) return result;

    let dbusName = (player.dbusName || "").toLowerCase();
    let desktopEntry = (player.desktopEntry || "").toLowerCase();
    let identity = (player.identity || "").toLowerCase();
    let trackTitle = player.trackTitle || "";
    let trackArtist = player.trackArtist || "";

    // normalize trackTitle (remove leading notification badge like "(1) ")
    let cleanTitle = trackTitle.replace(/^\(\d+\)\s+/, "").trim();

    let domain = "";
    if (domainCache[trackTitle]) {
        domain = domainCache[trackTitle];
    } else {
        // detect domain and website first
        let trackArtUrl = (player.trackArtUrl || "").toLowerCase();
        let mUrl = (player.metadata && (player.metadata["xesam:url"] || player.metadata["url"]) || "").toLowerCase();
        if (cleanTitle.toLowerCase().includes("youtube") || identity.includes("youtube") || dbusName.includes("youtube") || desktopEntry.includes("youtube") || trackArtUrl.includes("ytimg.com") || trackArtUrl.includes("youtube.com") || mUrl.includes("youtube.com") || mUrl.includes("youtu.be")) {
            domain = "youtube.com";
        } else if (cleanTitle.toLowerCase().includes("on x") || cleanTitle.toLowerCase().includes(" / x") || identity.includes("twitter") || dbusName.includes("twitter") || trackArtUrl.includes("twimg.com") || trackArtUrl.includes("twitter.com") || mUrl.includes("x.com") || mUrl.includes("twitter.com")) {
            domain = "x.com";
        } else if (identity.includes("spotify") || dbusName.includes("spotify") || desktopEntry.includes("spotify") || cleanTitle.toLowerCase().includes("spotify") || mUrl.includes("spotify.com")) {
            domain = "spotify.com";
        } else if (cleanTitle.toLowerCase().includes("soundcloud") || trackArtUrl.includes("sndcdn.com") || trackArtUrl.includes("soundcloud.com") || mUrl.includes("soundcloud.com")) {
            domain = "soundcloud.com";
        } else if (cleanTitle.toLowerCase().includes("twitch") || mUrl.includes("twitch.tv")) {
            domain = "twitch.tv";
        } else if (cleanTitle.toLowerCase().includes("facebook") || trackArtUrl.includes("fbcdn.net") || trackArtUrl.includes("facebook.com") || mUrl.includes("facebook.com")) {
            domain = "facebook.com";
        } else if (cleanTitle.toLowerCase().includes("reddit") || mUrl.includes("reddit.com")) {
            domain = "reddit.com";
        } else if (cleanTitle.toLowerCase().includes("netflix") || mUrl.includes("netflix.com")) {
            domain = "netflix.com";
        }

        // search window list if domain is still empty and it is a browser
        if (domain === "" && windowList && (dbusName.includes("chromium") || dbusName.includes("chrome") || dbusName.includes("firefox"))) {
            for (let i = 0; i < windowList.length; i++) {
                let client = windowList[i];
                let wt = (client.title || "").toLowerCase();
                if (trackTitle !== "" && wt.includes(trackTitle.toLowerCase())) {
                    if (wt.includes("youtube")) {
                        domain = "youtube.com";
                        break;
                    }
                    if (wt.includes("on x") || wt.includes(" / x") || wt.includes("twitter")) {
                        domain = "x.com";
                        break;
                    }
                    if (wt.includes("spotify")) {
                        domain = "spotify.com";
                        break;
                    }
                    if (wt.includes("soundcloud")) {
                        domain = "soundcloud.com";
                        break;
                    }
                    if (wt.includes("twitch")) {
                        domain = "twitch.tv";
                        break;
                    }
                    if (wt.includes("facebook")) {
                        domain = "facebook.com";
                        break;
                    }
                    if (wt.includes("reddit")) {
                        domain = "reddit.com";
                        break;
                    }
                }
            }
        }

        // cache the detected domain
        if (domain !== "" && trackTitle !== "" && trackTitle !== "Unknown Track") {
            domainCache[trackTitle] = domain;
        }
    }

    result.domain = domain;

    // parse title and artist based on domain
    if (domain === "youtube.com") {
        result.hasCustomInfo = true;
        let parts = cleanTitle.split(" - ");
        if (parts.length > 1) {
            let lastPart = parts[parts.length - 1].trim();
            if (lastPart.toLowerCase().includes("youtube")) {
                parts.pop();
                if (parts.length > 0) {
                    result.artist = parts[parts.length - 1].trim();
                    parts.pop();
                    if (parts.length > 0) {
                        result.title = parts.join(" - ").trim();
                    } else {
                        result.title = result.artist;
                    }
                }
            } else {
                result.title = cleanTitle;
                result.artist = trackArtist || "YouTube Creator";
            }
        } else {
            result.title = cleanTitle.replace(/ - YouTube/i, "").trim();
            result.artist = trackArtist || "YouTube Creator";
        }
    } else if (domain === "x.com") {
        result.hasCustomInfo = true;
        let parts = [];
        if (cleanTitle.includes(" on X: ")) {
            parts = cleanTitle.split(" on X: ");
            result.artist = parts[0].trim();
            let tweetText = parts[1].trim();
            if (tweetText.startsWith('"') && tweetText.endsWith('"')) {
                tweetText = tweetText.substring(1, tweetText.length - 1);
            }
            result.title = tweetText;
        } else if (cleanTitle.includes(" on X")) {
            parts = cleanTitle.split(" on X");
            result.artist = parts[0].trim();
            result.title = "Post on X";
        } else if (cleanTitle.includes(" / X")) {
            parts = cleanTitle.split(" / X");
            result.artist = parts[0].trim();
            result.title = "Post on X";
        } else {
            result.title = cleanTitle;
            result.artist = trackArtist || "X User";
        }
    } else if (domain === "spotify.com") {
        result.hasCustomInfo = true;
        result.title = cleanTitle.replace(/ - Spotify/i, "").trim();
        result.artist = trackArtist || "Spotify Artist";
    } else if (domain === "soundcloud.com") {
        result.hasCustomInfo = true;
        let temp = cleanTitle.replace(/ \| SoundCloud/i, "").trim();
        if (temp.toLowerCase().startsWith("stream ")) {
            result.artist = temp.substring(7).trim();
            result.title = "SoundCloud Stream";
        } else if (temp.includes(" by ")) {
            let parts = temp.split(" by ");
            result.title = parts[0].trim();
            result.artist = parts[1].trim();
        } else {
            result.title = temp;
            result.artist = trackArtist || "SoundCloud Creator";
        }
    } else if (domain === "facebook.com") {
        result.hasCustomInfo = true;
        let temp = cleanTitle.replace(/ \| Facebook/i, "").trim();
        if (temp.toLowerCase() === "facebook") {
            result.title = "Video on Facebook";
            result.artist = trackArtist || "Facebook Creator";
        } else {
            result.title = temp;
            result.artist = trackArtist || "Facebook Creator";
        }
    } else if (domain === "twitch.tv") {
        result.hasCustomInfo = true;
        let temp = cleanTitle.replace(/ - Twitch/i, "").trim();
        if (temp.toLowerCase() === "twitch") {
            result.title = "Live Stream";
            result.artist = "Twitch Streamer";
        } else {
            result.artist = temp;
            result.title = "Live Stream";
        }
    } else {
        result.title = trackTitle || "Unknown Track";
        result.artist = trackArtist || "Unknown Artist";
    }

    if (result.title === "") result.title = "Unknown Track";
    if (result.artist === "") result.artist = "Unknown Artist";

    return result;
}
