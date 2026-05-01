<script>
    import { searchQuery } from '../stores/search_query.svelte.js';
    let authenticated = $state(false);
    let ready = $state(false);
    let deviceId = $state(null);
    let currentTrack = $state(null);
    let paused = $state(true);
    let error = $state(null);
    let spotifyResults = $state([]);
    let youtubeResults = $state([]);
    let searching = $state(false);
    let activeVideo = $state(null);
    let syncedLines = $state([]);
    let positionMs = $state(0);
    let trackDurationMs = $state(0);

    let player = null;
    let accessToken = null;
    let tokenExpiresAt = 0;
    let searchSeq = 0;
    let searchTimer = null;
    let lastSyncWallMs = 0;
    let lastSyncedPosMs = 0;
    let lyricsContainer;

    async function fetchToken() {
        const data = await api.get(route('spotify.token'));
        if (!data.authenticated) {
            authenticated = false;
            return null;
        }
        authenticated = true;
        accessToken = data.access_token;
        tokenExpiresAt = data.expires_at;
        return data.access_token;
    }

    async function ensureToken() {
        if (!accessToken || Date.now() / 1000 >= tokenExpiresAt - 30) {
            return await fetchToken();
        }
        return accessToken;
    }

    function initPlayer() {
        player = new Spotify.Player({
            name: 'Web Player (Laravel)',
            getOAuthToken: async (cb) => {
                const token = await ensureToken();
                if (token) cb(token);
            },
            volume: 0.5,
        });

        player.addListener('ready', ({ device_id }) => {
            deviceId = device_id;
            ready = true;
        });

        player.addListener('not_ready', ({ device_id }) => {
            ready = false;
        });

        player.addListener('player_state_changed', (state) => {
            if (!state) return;
            currentTrack = state.track_window.current_track;
            paused = state.paused;
            trackDurationMs = state.duration;
            lastSyncedPosMs = state.position;
            lastSyncWallMs = performance.now();
            positionMs = state.position;
        });

        player.addListener('initialization_error', ({ message }) => error = `Init: ${message}`);
        player.addListener('authentication_error', ({ message }) => {
            error = `Auth: ${message}`;
            authenticated = false;
        });
        player.addListener('account_error', ({ message }) => error = `Account: ${message} (Premium required)`);
        player.addListener('playback_error', ({ message }) => error = `Playback: ${message}`);

        player.connect();
    }

    async function bootstrap() {
        const token = await fetchToken();
        if (!token) return;

        await window.spotifySdkReady;
        initPlayer();
    }

    async function spotifyApi(method, path, body) {
        const token = await ensureToken();
        const res = await fetch(`https://api.spotify.com/v1${path}`, {
            method,
            headers: {
                'Authorization': `Bearer ${token}`,
                'Content-Type': 'application/json',
            },
            body: body ? JSON.stringify(body) : undefined,
        });
        if (!res.ok && res.status !== 204) {
            const text = await res.text();
            throw new Error(`${res.status}: ${text}`);
        }
        return res.status === 204 ? null : res.json().catch(() => null);
    }

    async function playUri(uri) {
        error = null;
        activeVideo = null;
        try {
            await spotifyApi('PUT', `/me/player/play?device_id=${deviceId}`, {
                uris: [uri],
            });
        } catch (e) {
            error = e.message;
        }
    }

    async function playVideo(video) {
        error = null;
        try { await player?.pause(); } catch {}
        try {
            const data = await api.get(`${route('youtube.audio')}?id=${encodeURIComponent(video.id)}`);
            if (!data?.stream_url) {
                error = data?.detail || data?.error || 'Could not load audio';
                return;
            }
            activeVideo = { ...video, stream_url: data.stream_url };
        } catch (e) {
            error = e.message;
        }
    }

    async function runSearch(q) {
        const seq = ++searchSeq;
        if (!q.trim()) {
            spotifyResults = [];
            youtubeResults = [];
            searching = false;
            return;
        }
        searching = true;
        const [spotifyRes, youtubeRes] = await Promise.allSettled([
            spotifyApi('GET', `/search?type=track&limit=10&q=${encodeURIComponent(q)}`),
            api.get(`${route('youtube.search')}?q=${encodeURIComponent(q)}`),
        ]);
        if (seq !== searchSeq) return;
        if (spotifyRes.status === 'fulfilled') {
            spotifyResults = spotifyRes.value?.tracks?.items ?? [];
        } else {
            error = spotifyRes.reason?.message ?? 'Spotify search failed';
        }
        if (youtubeRes.status === 'fulfilled') {
            youtubeResults = youtubeRes.value?.items ?? [];
        } else {
            error = youtubeRes.reason?.message ?? 'YouTube search failed';
        }
        searching = false;
    }

    function onQueryInput() {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => runSearch($searchQuery), 250);
    }

    async function togglePlay() {
        try { await player.togglePlay(); } catch (e) { error = e.message; }
    }


    let activeIdx = $derived.by(() => {
        if (!syncedLines.length) return -1;
        let idx = -1;
        for (let i = 0; i < syncedLines.length; i++) {
            if (syncedLines[i].time <= positionMs) idx = i;
            else break;
        }
        return idx;
    });

    $effect(() => {
        if (paused) return;
        const id = setInterval(() => {
            const wall = performance.now();
            positionMs = Math.min(
                lastSyncedPosMs + (wall - lastSyncWallMs),
                trackDurationMs || Number.POSITIVE_INFINITY
            );
        }, 100);
        return () => clearInterval(id);
    });

    $effect(() => {
        if (!player) return;
        const id = setInterval(async () => {
            const state = await player.getCurrentState();
            if (!state) return;
            lastSyncedPosMs = state.position;
            lastSyncWallMs = performance.now();
            paused = state.paused;
            trackDurationMs = state.duration;
        }, 2000);
        return () => clearInterval(id);
    });

    $effect(() => {
        if (activeIdx < 0 || !lyricsContainer) return;
        const el = lyricsContainer.querySelector(`[data-idx="${activeIdx}"]`);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
    });

    bootstrap();
</script>

<main>
    {#if !authenticated}
        <p>Log in with Spotify to start playing music in this browser tab.</p>
        <a class="btn" href="/auth/spotify">Log in with Spotify</a>
    {:else if !ready}
        <p>Connecting player…</p>
    {:else}
        <input
            bind:value={$searchQuery}
            oninput={onQueryInput}
            placeholder="Search songs…"
            autocomplete="off"
        />

        {#if searching}
            <p class="muted">Searching…</p>
        {:else}
            {#if spotifyResults.length}
                <h3>Songs</h3>
                {#each spotifyResults as track (track.id)}
                    <button class="result" onclick={() => playUri(track.uri)}>
                        <strong>{track.name}</strong>
                        <span class="artists">{track.artists.map(a => a.name).join(', ')}</span>
                    </button>
                {/each}
            {/if}

            {#if youtubeResults.length}
                <h3>Videos</h3>
                {#each youtubeResults as video (video.id)}
                    <button class="result video" onclick={() => playVideo(video)}>
                        {#if video.thumbnail}
                            <img src={video.thumbnail} alt="" />
                        {/if}
                        <span class="meta">
                            <strong>{video.title}</strong>
                            <span class="artists">{video.channel}</span>
                        </span>
                    </button>
                {/each}
            {/if}
        {/if}

        {#if activeVideo}
            <div class="video-player">
                <strong>{activeVideo.title}</strong>
                <span class="artists">{activeVideo.channel}</span>
                <audio src={activeVideo.stream_url} autoplay controls></audio>
                <button class="btn" onclick={() => activeVideo = null}>Close</button>
            </div>
        {/if}

        {#if currentTrack}
            <div class="now-playing">
                {#if currentTrack.album?.images?.[0]}
                    <img src={currentTrack.album.images[0].url} alt="" />
                {/if}
                <div>
                    <strong>{currentTrack.name}</strong>
                    <div>{currentTrack.artists.map(a => a.name).join(', ')}</div>
                </div>
            </div>
        {/if}

        <div class="row">
            <button class="btn" onclick={togglePlay}>{paused ? '▶' : '⏸'}</button>
        </div>
    {/if}

    {#if error}
        <p class="error">{error}</p>
    {/if}
</main>
