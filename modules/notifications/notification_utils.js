const getFriendlyNotifTimeString = (timestamp) => {
    if (!timestamp) return '';
    const messageTime = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - messageTime.getTime();

    // less than 1 minute
    if (diffMs < 60000)
        return 'Now';

    // same day
    if (messageTime.toDateString() === now.toDateString()) {
        const diffMinutes = Math.floor(diffMs / 60000);
        const diffHours = Math.floor(diffMs / 3600000);

        if (diffHours > 0) {
            return `${diffHours}h`;
        } else {
            return `${diffMinutes}m`;
        }
    }

    // multiple days
    const diffDays = Math.floor(diffMs / 86400000);
    if (diffDays > 0) {
        return `${diffDays}d`;
    }

    if (messageTime.toDateString() === new Date(now.getTime() - 86400000).toDateString())
        return 'Yesterday';

    return Qt.formatDateTime(messageTime, "MMMM dd");
};

const processNotificationBody = (body, appName) => {
    if (!body)
        return "";

    let processedBody = body;

    // clean browser notification header line
    if (appName) {
        const lowerApp = appName.toLowerCase();
        const browsers = ["helium", "chrome", "chromium", "brave", "vivaldi", "opera", "microsoft edge"];

        if (browsers.some(name => lowerApp.includes(name))) {
            const lines = body.split('\n\n');

            if (lines.length > 1 && lines[0].startsWith('<a')) {
                processedBody = lines.slice(1).join('\n\n');
            }
        }
    }

    return processedBody;
};

const getWebsiteInfo = (body, summary, appName) => {
    const raw = (body || "") + " " + (summary || "");
    const lower = raw.toLowerCase();
    const lowerApp = (appName || "").toLowerCase();

    const browsers = ["helium", "chrome", "chromium", "brave", "firefox", "vivaldi", "opera", "edge", "zen", "browser"];
    const isBrowser = browsers.some(b => lowerApp.includes(b));
    if (!isBrowser) {
        return { name: appName || "System", domain: "", favicon: "" };
    }

    // extract domain from url or text
    let domain = "";
    const urlMatch = raw.match(/https?:\/\/([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})/i);
    if (urlMatch) {
        domain = urlMatch[1].toLowerCase();
    } else {
        const domainMatch = raw.match(/\b([a-zA-Z0-9.-]+\.(?:com|org|net|io|edu|gov|co|app|vn|dev|me|ai|so|xyz|gg|tv))\b/i);
        if (domainMatch) {
            domain = domainMatch[1].toLowerCase();
            if (domain.includes("@")) domain = domain.split("@")[1];
        }
    }

    // known site patterns
    if (domain.includes("telegram") || lower.includes("telegram") || lower.includes("t.me")) {
        return { name: "Telegram", domain: "web.telegram.org", favicon: "https://www.google.com/s2/favicons?domain=web.telegram.org&sz=64" };
    }

    const isEmail = lower.includes("@gmail.com") || lower.includes("new email") || lower.includes("emails") || lower.includes("mail.google.com");
    if (isEmail) {
        return { name: "Gmail", domain: "mail.google.com", favicon: "https://www.google.com/s2/favicons?domain=mail.google.com&sz=64" };
    }

    if (domain.includes("claude.ai") || lower.includes("claude.ai") || lower.includes("anthropic")) {
        return { name: "Claude", domain: "claude.ai", favicon: "https://www.google.com/s2/favicons?domain=claude.ai&sz=64" };
    }

    if (domain.includes("github.com") || lower.includes("github.com")) {
        return { name: "GitHub", domain: "github.com", favicon: "https://www.google.com/s2/favicons?domain=github.com&sz=64" };
    }

    if (domain.includes("youtube.com") || lower.includes("youtube.com")) {
        return { name: "YouTube", domain: "youtube.com", favicon: "https://www.google.com/s2/favicons?domain=youtube.com&sz=64" };
    }

    if (domain.includes("chatgpt.com") || domain.includes("openai.com") || lower.includes("chatgpt")) {
        return { name: "ChatGPT", domain: "chatgpt.com", favicon: "https://www.google.com/s2/favicons?domain=chatgpt.com&sz=64" };
    }

    if (domain) {
        let clean = domain.replace(/^www\./, "").replace(/^web\./, "");
        let name = clean.split(".")[0];
        name = name.charAt(0).toUpperCase() + name.slice(1);
        return { name: name, domain: domain, favicon: "https://www.google.com/s2/favicons?domain=" + encodeURIComponent(domain) + "&sz=64" };
    }

    return { name: appName || "Browser", domain: "", favicon: "" };
};