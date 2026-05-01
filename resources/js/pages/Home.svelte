<script>
    import { searchQuery } from '../stores/search_query.svelte.js';
    let currentTrack = $state(null);
    let paused = $state(true);
    let error = $state(null);
    let youtubeResults = $state([]);
    let searching = $state(false);
    let activeVideo = $state(null);
    let trackDurationMs = $state(0);

    let player = null;
    let searchSeq = 0;
    let searchTimer = null;
    let lastSyncWallMs = 0;
    let lastSyncedPosMs = 0;

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
        const [youtubeRes] = await Promise.allSettled([
            api.get(`${route('youtube.search')}?q=${encodeURIComponent(q)}`),
        ]);
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

</script>

<main>
        <input
            bind:value={$searchQuery}
            oninput={onQueryInput}
            placeholder="Search songs…"
            autocomplete="off"
        />

        {#if searching}
            <p class="muted">Searching…</p>
        {:else}
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

    {#if error}
        <p class="error">{error}</p>
    {/if}
</main>
