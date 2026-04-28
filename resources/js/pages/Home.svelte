<script>
    let authenticated = $state(false);
    let ready = $state(false);
    let deviceId = $state(null);
    let currentTrack = $state(null);
    let paused = $state(true);
    let error = $state(null);
    let query = $state('');
    let results = $state([]);
    let searching = $state(false);
    let lyricsLoading = $state(false);
    let lyricsTrackId = $state(null);
    let syncedLines = $state([]);
    let plainLyrics = $state('');
    let positionMs = $state(0);
    let trackDurationMs = $state(0);

    let player = null;
    let accessToken = null;
    let tokenExpiresAt = 0;
    let searchSeq = 0;
    let searchTimer = null;
    let lyricsSeq = 0;
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
        try {
            await spotifyApi('PUT', `/me/player/play?device_id=${deviceId}`, {
                uris: [uri],
            });
        } catch (e) {
            error = e.message;
        }
    }

    async function runSearch(q) {
        const seq = ++searchSeq;
        if (!q.trim()) {
            results = [];
            searching = false;
            return;
        }
        searching = true;
        try {
            const data = await spotifyApi('GET', `/search?type=track&limit=10&q=${encodeURIComponent(q)}`);
            if (seq !== searchSeq) return;
            results = data?.tracks?.items ?? [];
        } catch (e) {
            if (seq === searchSeq) error = e.message;
        } finally {
            if (seq === searchSeq) searching = false;
        }
    }

    function onQueryInput() {
        clearTimeout(searchTimer);
        searchTimer = setTimeout(() => runSearch(query), 250);
    }

    async function togglePlay() {
        try { await player.togglePlay(); } catch (e) { error = e.message; }
    }

    async function loadLyrics(track) {
        const seq = ++lyricsSeq;
        lyricsTrackId = track.id;
        syncedLines = [];
        plainLyrics = '';
        lyricsLoading = true;

        const artist = track.artists?.[0]?.name ?? '';
        const title = stripFeatured(track.name);
        const album = track.album?.name ?? '';
        const duration = Math.round((track.duration_ms ?? trackDurationMs) / 1000);

        const params = new URLSearchParams({
            artist_name: artist,
            track_name: title,
            album_name: album,
            duration: String(duration),
        });

        try {
            let res = await fetch(`https://lrclib.net/api/get?${params}`);
            if (res.status === 404) {
                const sp = new URLSearchParams({ artist_name: artist, track_name: title });
                res = await fetch(`https://lrclib.net/api/get?${sp}`);
            }
            if (seq !== lyricsSeq) return;
            if (!res.ok) return;

            const data = await res.json();
            if (seq !== lyricsSeq) return;

            syncedLines = data.syncedLyrics ? parseLrc(data.syncedLyrics) : [];
            plainLyrics = (data.plainLyrics ?? '').trim();
        } catch {
            // ignore
        } finally {
            if (seq === lyricsSeq) lyricsLoading = false;
        }
    }

    function stripFeatured(name) {
        return name
            .replace(/\s*[\(\[][^)\]]*(feat\.?|featuring|with)[^)\]]*[\)\]]/gi, '')
            .replace(/\s*-\s*(feat\.?|featuring|with)\s.*$/i, '')
            .trim();
    }

    function parseLrc(text) {
        const lines = [];
        for (const raw of text.split(/\r?\n/)) {
            const stamps = [...raw.matchAll(/\[(\d+):(\d+)(?:[.:](\d+))?\]/g)];
            if (!stamps.length) continue;
            const lyric = raw.replace(/\[[^\]]+\]/g, '').trim();
            for (const m of stamps) {
                const min = +m[1];
                const sec = +m[2];
                const fracStr = m[3] ?? '0';
                const frac = +`0.${fracStr}`;
                const timeMs = (min * 60 + sec + frac) * 1000;
                if (Number.isNaN(timeMs)) continue;
                lines.push({ time: timeMs, text: lyric });
            }
        }
        lines.sort((a, b) => a.time - b.time);
        return lines;
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
        if (currentTrack && currentTrack.id !== lyricsTrackId) {
            loadLyrics(currentTrack);
        }
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
                bind:value={query}
                oninput={onQueryInput}
                placeholder="Search songs…"
                autocomplete="off"
            />

        {#if searching}
            <p class="muted">Searching…</p>
        {:else if results.length}
            <ul class="results">
                {#each results as track (track.id)}
                    <li>
                        <button class="result" onclick={() => playUri(track.uri)}>
                            {#if track.album?.images?.at(-1)}
                                <img src={track.album.images.at(-1).url} alt="" />
                            {/if}
                            <span class="meta">
                                <strong>{track.name}</strong>
                                <span class="artists">{track.artists.map(a => a.name).join(', ')}</span>
                            </span>
                        </button>
                    </li>
                {/each}
            </ul>
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

            <div class="lyrics" bind:this={lyricsContainer}>
                {#if lyricsLoading}
                    <p class="muted">Loading lyrics…</p>
                {:else if syncedLines.length}
                    <ol class="synced">
                        {#each syncedLines as line, i (i)}
                            <li
                                data-idx={i}
                                class:active={i === activeIdx}
                                class:past={i < activeIdx}
                            >
                                {line.text || '♪'}
                            </li>
                        {/each}
                    </ol>
                {:else if plainLyrics}
                    <p class="muted">No synced lyrics — showing plain text.</p>
                    <pre>{plainLyrics}</pre>
                {:else}
                    <p class="muted">No lyrics found.</p>
                {/if}
            </div>
        {/if}

        <div class="row">
            <button class="btn" onclick={togglePlay}>{paused ? '▶' : '⏸'}</button>
        </div>

        <a class="logout" href="/auth/spotify/logout">Log out</a>
    {/if}

    {#if error}
        <p class="error">{error}</p>
    {/if}
</main>
