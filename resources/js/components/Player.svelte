<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import '../../scss/player.scss';

  let audioEl;
  let isPlaying = $state(false);
  let duration = $state(0);
  let isMuted = $state(false);
  let isShuffle = $state(false);
  let repeatMode = $state(0); // 0 = off, 1 = all, 2 = one
  let isSeeking = $state(false);
  let pendingSeek = $state(false);
  let seekValue = $state(0);
  let volumeSlider = $state(0.7);

  let sliderMax = $derived(duration || 100);
  let progressPct = $derived((seekValue / sliderMax) * 100);
  let volumePct = $derived((isMuted ? 0 : volumeSlider) * 100);

  $effect(() => {
    if (audioEl) audioEl.volume = isMuted ? 0 : volumeSlider;
  });

  $effect(() => {
    if (audioEl && $currentlyPlaying.stream_url) {
      audioEl.src = $currentlyPlaying.stream_url;
      audioEl.load();
      audioEl.play().catch(() => {});
    }
  });

  function onTimeUpdate() {
    if (isSeeking || pendingSeek || !audioEl || audioEl.seeking) return;
    seekValue = audioEl.currentTime || 0;
  }

  function onSeeked() {
    pendingSeek = false;
  }

  function togglePlay() {
    if (!audioEl) return;
    if (audioEl.paused) audioEl.play().catch(() => {});
    else audioEl.pause();
  }

  function toggleMute() {
    isMuted = !isMuted;
  }

  function toggleShuffle() {
    isShuffle = !isShuffle;
  }

  function cycleRepeat() {
    repeatMode = (repeatMode + 1) % 3;
  }

  function onSeekInput() {
    isSeeking = true;
  }

  function onSeekCommit(e) {
    const target = Number(e.target.value);
    pendingSeek = true;
    if (audioEl && Number.isFinite(audioEl.duration) && audioEl.duration > 0) {
      audioEl.currentTime = target;
    } else {
      pendingSeek = false;
    }
    seekValue = target;
    isSeeking = false;
  }

  function formatTime(t) {
    if (!t || isNaN(t)) return '0:00';
    const m = Math.floor(t / 60);
    const s = Math.floor(t % 60).toString().padStart(2, '0');
    return `${m}:${s}`;
  }

</script>

<footer class="player">
  <div class="track">
    {#if $currentlyPlaying.thumbnail}
      <img class="thumbnail" src={$currentlyPlaying.thumbnail} alt={$currentlyPlaying.title} />
    {:else}
      <div class="thumbnail thumbnail--placeholder"></div>
    {/if}
    <div class="track-meta">
      <span class="title">{$currentlyPlaying.title || '—'}</span>
      <span class="artist">{$currentlyPlaying.artist || ''}</span>
    </div>
  </div>

  <div class="controls">
    <div class="buttons">
      <button class="ctrl" class:active={isShuffle} onclick={toggleShuffle} aria-label="Shuffle">
        <svg viewBox="0 0 24 24"><path d="M16 3h5v5M4 20l16.2-16.2M21 16v5h-5M15 15l5.1 5.1M4 4l5 5"/></svg>
      </button>
      <button class="ctrl" aria-label="Previous">
        <svg viewBox="0 0 24 24"><path d="M19 20L9 12l10-8v16zM5 19V5"/></svg>
      </button>
      <button class="ctrl ctrl--play" onclick={togglePlay} aria-label={isPlaying ? 'Pause' : 'Play'}>
        {#if isPlaying}
          <svg viewBox="0 0 24 24"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>
        {:else}
          <svg viewBox="0 0 24 24"><path d="M6 4l14 8-14 8V4z"/></svg>
        {/if}
      </button>
      <button class="ctrl" aria-label="Next">
        <svg viewBox="0 0 24 24"><path d="M5 4l10 8-10 8V4zM19 5v14"/></svg>
      </button>
      <button class="ctrl" class:active={repeatMode > 0} onclick={cycleRepeat} aria-label="Repeat">
        {#if repeatMode === 2}
          <svg viewBox="0 0 24 24"><path d="M17 1l4 4-4 4M3 11V9a4 4 0 014-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 01-4 4H3"/><text x="9" y="16" font-size="8" font-weight="bold" fill="currentColor" stroke="none">1</text></svg>
        {:else}
          <svg viewBox="0 0 24 24"><path d="M17 1l4 4-4 4M3 11V9a4 4 0 014-4h14M7 23l-4-4 4-4M21 13v2a4 4 0 01-4 4H3"/></svg>
        {/if}
      </button>
    </div>

    <div class="progress">
      <span class="time">{formatTime(seekValue)}</span>
      <input
        type="range"
        class="slider slider--progress"
        style="--fill:{progressPct}%"
        min="0"
        max={sliderMax}
        step="0.1"
        bind:value={seekValue}
        oninput={onSeekInput}
        onchange={onSeekCommit}
      />
      <span class="time">{formatTime(duration)}</span>
    </div>
  </div>

  <div class="extras">
    <button class="ctrl" onclick={toggleMute} aria-label="Mute">
      {#if isMuted || volumeSlider === 0}
        <svg viewBox="0 0 24 24"><path d="M11 5L6 9H2v6h4l5 4V5zM23 9l-6 6M17 9l6 6"/></svg>
      {:else if volumeSlider < 0.5}
        <svg viewBox="0 0 24 24"><path d="M11 5L6 9H2v6h4l5 4V5zM15.5 8.5a5 5 0 010 7"/></svg>
      {:else}
        <svg viewBox="0 0 24 24"><path d="M11 5L6 9H2v6h4l5 4V5zM15.5 8.5a5 5 0 010 7M19 5a9 9 0 010 14"/></svg>
      {/if}
    </button>
    <input
      type="range"
      class="slider slider--volume"
      style="--fill:{volumePct}%"
      min="0"
      max="1"
      step="0.01"
      bind:value={volumeSlider}
    />
  </div>

  <audio
    bind:this={audioEl}
    bind:duration
    ontimeupdate={onTimeUpdate}
    onseeked={onSeeked}
    onplay={() => (isPlaying = true)}
    onpause={() => (isPlaying = false)}
    onended={() => (isPlaying = false)}
  ></audio>
</footer>
