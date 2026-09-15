const SCOPE = "https://www.googleapis.com/auth/youtube.readonly";
const API_BASE = "https://www.googleapis.com/youtube/v3";

let accessToken = null;
let tokenClient = null;
let player = null;
let playerReady = false;
let pendingVideoId = null;

let currentVideoId = null;
let chapters = [];
let videoDuration = 0;
let repeatTrack = false;
let loopChapter = false;
let activeChapterIndex = -1;
let boundaryTimer = null;

const el = (id) => document.getElementById(id);

const AUTH_STORAGE_KEY = "chapterPlayerAuth";

// ---------- Tabs ----------

document.querySelectorAll(".tab-btn").forEach((btn) => {
  btn.addEventListener("click", () => switchTab(btn.dataset.tab));
});

function switchTab(name) {
  document.querySelectorAll(".tab-btn").forEach((b) => b.classList.toggle("active", b.dataset.tab === name));
  document.querySelectorAll(".tab-panel").forEach((p) => p.classList.toggle("active", p.id === `tab-${name}`));
}

// ---------- Auth ----------

// The access token itself lasts ~1hr regardless of storage — this only
// avoids re-prompting on every reload within that window. There's no way
// to persist sign-in beyond that without a backend holding a refresh
// token (which needs the OAuth client secret, so it can't live in a
// static front-end app).
function saveAuth(token, expiresInSeconds) {
  const expiresAt = Date.now() + (expiresInSeconds || 3600) * 1000;
  localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify({ accessToken: token, expiresAt }));
}

function loadStoredAuth() {
  try {
    const raw = localStorage.getItem(AUTH_STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed.accessToken || !parsed.expiresAt) return null;
    if (Date.now() >= parsed.expiresAt - 30000) {
      localStorage.removeItem(AUTH_STORAGE_KEY);
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

function clearStoredAuth() {
  localStorage.removeItem(AUTH_STORAGE_KEY);
}

function markSignedIn() {
  el("signin-btn").classList.add("hidden");
  el("signout-btn").classList.remove("hidden");
}

function markSignedOut() {
  accessToken = null;
  clearStoredAuth();
  el("signin-btn").classList.remove("hidden");
  el("signout-btn").classList.add("hidden");
  el("playlists-status").textContent = "Sign in to load your playlists.";
  el("playlists-list").innerHTML = "";
}

window.addEventListener("load", () => {
  const waitForGis = setInterval(() => {
    if (window.google && google.accounts && google.accounts.oauth2) {
      clearInterval(waitForGis);
      tokenClient = google.accounts.oauth2.initTokenClient({
        client_id: CONFIG.CLIENT_ID,
        scope: SCOPE,
        callback: onTokenResponse,
      });

      const stored = loadStoredAuth();
      if (stored) {
        accessToken = stored.accessToken;
        markSignedIn();
        loadPlaylists();
      }
    }
  }, 100);
});

el("signin-btn").addEventListener("click", () => {
  if (!tokenClient) return;
  tokenClient.requestAccessToken({ prompt: accessToken ? "" : "consent" });
});

el("signout-btn").addEventListener("click", () => {
  if (accessToken && window.google) {
    google.accounts.oauth2.revoke(accessToken, () => {});
  }
  markSignedOut();
});

function onTokenResponse(resp) {
  if (resp.error) {
    el("playlists-status").textContent = `Sign-in failed: ${resp.error}`;
    return;
  }
  accessToken = resp.access_token;
  saveAuth(accessToken, resp.expires_in);
  markSignedIn();
  loadPlaylists();
}

async function apiFetch(path) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (res.status === 401) {
    markSignedOut();
    throw new Error("Your session expired — sign in again.");
  }
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`API error ${res.status}: ${body}`);
  }
  return res.json();
}

// ---------- Playlists tab ----------

async function loadPlaylists() {
  el("playlists-status").textContent = "Loading playlists...";
  el("playlist-items-view").classList.add("hidden");
  el("playlists-list").classList.remove("hidden");
  try {
    const data = await apiFetch("/playlists?part=snippet,contentDetails&mine=true&maxResults=50");
    el("playlists-status").textContent = data.items.length ? "" : "No playlists found on this account.";
    renderPlaylists(data.items || []);
  } catch (err) {
    el("playlists-status").textContent = `Couldn't load playlists: ${err.message}`;
  }
}

function renderPlaylists(items) {
  const list = el("playlists-list");
  list.innerHTML = "";
  for (const item of items) {
    const row = document.createElement("button");
    row.className = "list-row";
    const thumb = item.snippet.thumbnails?.default?.url || "";
    row.innerHTML = `
      ${thumb ? `<img src="${thumb}" alt="" />` : ""}
      <div>
        <p class="row-title">${escapeHtml(item.snippet.title)}</p>
        <p class="row-sub">${item.contentDetails.itemCount} videos</p>
      </div>
    `;
    row.addEventListener("click", () => loadPlaylistItems(item.id, item.snippet.title));
    list.appendChild(row);
  }
}

async function loadPlaylistItems(playlistId, title) {
  el("playlists-list").classList.add("hidden");
  el("playlist-items-view").classList.remove("hidden");
  el("playlist-items-title").textContent = title;
  const listEl = el("playlist-items-list");
  listEl.innerHTML = `<p class="hint">Loading...</p>`;
  try {
    const data = await apiFetch(`/playlistItems?part=snippet&playlistId=${playlistId}&maxResults=50`);
    listEl.innerHTML = "";
    for (const item of data.items || []) {
      const videoId = item.snippet.resourceId?.videoId;
      if (!videoId) continue;
      const row = document.createElement("button");
      row.className = "list-row";
      const thumb = item.snippet.thumbnails?.default?.url || "";
      row.innerHTML = `
        ${thumb ? `<img src="${thumb}" alt="" />` : ""}
        <div>
          <p class="row-title">${escapeHtml(item.snippet.title)}</p>
        </div>
      `;
      row.addEventListener("click", () => {
        switchTab("now-playing");
        loadVideo(videoId);
      });
      listEl.appendChild(row);
    }
  } catch (err) {
    listEl.innerHTML = `<p class="hint">Couldn't load videos: ${err.message}</p>`;
  }
}

el("back-to-playlists").addEventListener("click", () => {
  el("playlist-items-view").classList.add("hidden");
  el("playlists-list").classList.remove("hidden");
});

// ---------- Now playing tab ----------

el("load-form").addEventListener("submit", (e) => {
  e.preventDefault();
  const raw = el("video-url-input").value.trim();
  const videoId = parseVideoId(raw);
  if (!videoId) {
    el("chapter-status").textContent = "Couldn't recognize that as a YouTube video URL or ID.";
    return;
  }
  loadVideo(videoId);
});

function parseVideoId(input) {
  if (/^[a-zA-Z0-9_-]{11}$/.test(input)) return input;
  try {
    const url = new URL(input);
    if (url.hostname.includes("youtu.be")) {
      return url.pathname.slice(1).split("/")[0] || null;
    }
    if (url.pathname.startsWith("/shorts/")) {
      return url.pathname.split("/")[2] || null;
    }
    if (url.pathname.startsWith("/embed/")) {
      return url.pathname.split("/")[2] || null;
    }
    const v = url.searchParams.get("v");
    if (v) return v;
  } catch {
    return null;
  }
  return null;
}

async function loadVideo(videoId) {
  if (!accessToken) {
    el("chapter-status").textContent = "Sign in with Google first.";
    return;
  }
  currentVideoId = videoId;
  chapters = [];
  activeChapterIndex = -1;
  el("chapters-list").innerHTML = "";
  el("video-title").textContent = "Loading...";
  el("chapter-status").textContent = "";

  try {
    const data = await apiFetch(`/videos?part=snippet,contentDetails&id=${videoId}`);
    const video = data.items && data.items[0];
    if (!video) {
      el("video-title").textContent = "";
      el("chapter-status").textContent = "Video not found (private, deleted, or wrong ID).";
      return;
    }
    el("video-title").textContent = video.snippet.title;
    videoDuration = parseISO8601Duration(video.contentDetails.duration);
    chapters = parseChapters(video.snippet.description, videoDuration);
    renderChapters();
    el("chapter-status").textContent = chapters.length
      ? `${chapters.length} chapters found`
      : "No chapter timestamps found in the description.";
  } catch (err) {
    el("chapter-status").textContent = `Couldn't load video: ${err.message}`;
  }

  if (playerReady) {
    createOrLoadPlayer(videoId);
  } else {
    pendingVideoId = videoId;
  }
}

function parseISO8601Duration(iso) {
  const m = iso.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/);
  if (!m) return 0;
  const h = parseInt(m[1] || "0", 10);
  const min = parseInt(m[2] || "0", 10);
  const sec = parseInt(m[3] || "0", 10);
  return h * 3600 + min * 60 + sec;
}

function parseChapters(description, duration) {
  const lines = (description || "").split("\n");
  const timeRe = /(\d{1,2}:)?(\d{1,2}):(\d{2})/;
  const found = [];
  for (const line of lines) {
    const m = line.match(timeRe);
    if (!m) continue;
    const h = m[1] ? parseInt(m[1], 10) : 0;
    const min = parseInt(m[2], 10);
    const sec = parseInt(m[3], 10);
    const start = h * 3600 + min * 60 + sec;
    let title = (line.slice(0, m.index) + line.slice(m.index + m[0].length)).trim();
    title = title.replace(/^[-–—:.\s]+|[-–—:.\s]+$/g, "").trim();
    if (!title) title = `Chapter ${found.length + 1}`;
    found.push({ start, title });
  }
  found.sort((a, b) => a.start - b.start);
  const deduped = [];
  for (const c of found) {
    if (deduped.length && deduped[deduped.length - 1].start === c.start) continue;
    deduped.push(c);
  }
  if (deduped.length < 2) return [];
  for (let i = 0; i < deduped.length; i++) {
    deduped[i].end = i + 1 < deduped.length ? deduped[i + 1].start : duration || deduped[i].start;
  }
  return deduped;
}

function formatTime(totalSeconds) {
  const s = Math.max(0, Math.round(totalSeconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
  const ss = String(sec).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
}

function renderChapters() {
  const list = el("chapters-list");
  list.innerHTML = "";
  chapters.forEach((ch, i) => {
    const row = document.createElement("button");
    row.className = "chapter-row";
    row.dataset.index = String(i);
    row.innerHTML = `
      <span class="idx">${i + 1}</span>
      <div style="flex:1; min-width:0;">
        <p class="chapter-title">${escapeHtml(ch.title)}</p>
        <p class="chapter-time">${formatTime(ch.start)} – ${formatTime(ch.end)}</p>
      </div>
    `;
    row.addEventListener("click", () => {
      if (player) {
        player.seekTo(ch.start, true);
        player.playVideo();
      }
    });
    list.appendChild(row);
  });
}

function currentChapterIndex(t) {
  for (let i = 0; i < chapters.length; i++) {
    if (t >= chapters[i].start && t < chapters[i].end) return i;
  }
  if (chapters.length && t >= chapters[chapters.length - 1].end) return chapters.length - 1;
  return -1;
}

function updateActiveChapterUI(idx) {
  if (idx === activeChapterIndex) return;
  const rows = el("chapters-list").children;
  if (activeChapterIndex >= 0 && rows[activeChapterIndex]) {
    rows[activeChapterIndex].classList.remove("active");
  }
  activeChapterIndex = idx;
  if (idx >= 0 && rows[idx]) {
    rows[idx].classList.add("active");
    rows[idx].scrollIntoView({ block: "nearest", behavior: "smooth" });
  }
}

// ---------- YouTube IFrame player ----------

function onYouTubeIframeAPIReady() {
  playerReady = true;
  if (pendingVideoId) {
    createOrLoadPlayer(pendingVideoId);
    pendingVideoId = null;
  }
}
window.onYouTubeIframeAPIReady = onYouTubeIframeAPIReady;

function createOrLoadPlayer(videoId) {
  if (!player) {
    player = new YT.Player("player", {
      videoId,
      playerVars: { rel: 0, playsinline: 1 },
      events: {
        onReady: () => startBoundaryTimer(),
        onStateChange: onPlayerStateChange,
      },
    });
  } else {
    player.loadVideoById(videoId);
  }
}

function onPlayerStateChange(e) {
  el("play-pause-btn").textContent = e.data === YT.PlayerState.PLAYING ? "Pause" : "Play";
  if (e.data === YT.PlayerState.ENDED && repeatTrack) {
    player.seekTo(0, true);
    player.playVideo();
  }
}

function startBoundaryTimer() {
  if (boundaryTimer) return;
  boundaryTimer = setInterval(() => {
    if (!player || typeof player.getCurrentTime !== "function" || !chapters.length) return;
    const t = player.getCurrentTime();

    // Pin the loop to the chapter we last knew we were in, rather than
    // recomputing from raw time first — the 400ms poll interval is coarser
    // than a narrow end-of-chapter window, so by the time we poll again
    // playback has often already crossed into the next chapter's range,
    // and re-deriving the index from time alone would silently start
    // "looping" that next chapter instead of seeking back.
    if (loopChapter && activeChapterIndex >= 0) {
      const loopingChapter = chapters[activeChapterIndex];
      if (t >= loopingChapter.end) {
        player.seekTo(loopingChapter.start, true);
        return;
      }
    }

    updateActiveChapterUI(currentChapterIndex(t));
  }, 400);
}

// ---------- Transport controls ----------

el("play-pause-btn").addEventListener("click", () => {
  if (!player) return;
  const state = player.getPlayerState();
  if (state === YT.PlayerState.PLAYING) player.pauseVideo();
  else player.playVideo();
});

el("prev-chapter-btn").addEventListener("click", () => {
  if (!player || !chapters.length) return;
  const idx = currentChapterIndex(player.getCurrentTime());
  const target = idx > 0 ? chapters[idx - 1].start : 0;
  player.seekTo(target, true);
});

el("next-chapter-btn").addEventListener("click", () => {
  if (!player || !chapters.length) return;
  const idx = currentChapterIndex(player.getCurrentTime());
  if (idx >= 0 && idx < chapters.length - 1) {
    player.seekTo(chapters[idx + 1].start, true);
  }
});

el("repeat-track-btn").addEventListener("click", () => {
  repeatTrack = !repeatTrack;
  el("repeat-track-btn").classList.toggle("active", repeatTrack);
});

el("loop-chapter-btn").addEventListener("click", () => {
  loopChapter = !loopChapter;
  el("loop-chapter-btn").classList.toggle("active", loopChapter);
});

// ---------- Utils ----------

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}
