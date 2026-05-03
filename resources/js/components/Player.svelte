<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import { openContextMenu } from '../stores/context_menu.svelte.js';
  import { addToPlaylistItems } from '../lib/menus.js';
  import '../../scss/player.scss';

  let audioEl;
  let isPlaying = $state(false);
  let duration = $state(0);
  let isSeeking = $state(false);
  let seekValue = $state(0);

  let sliderMax = $derived(duration || 100);
  let progressPct = $derived((seekValue / sliderMax) * 100);

  $effect(() => {
    if ($currentlyPlaying.stream_url) {
      audioEl.src = $currentlyPlaying.stream_url;
      audioEl.load();
      audioEl.play().catch(() => {});
    }
  });

  function onTimeUpdate() {
    if (isSeeking || audioEl.seeking) return;
    seekValue = audioEl.currentTime || 0;
  }

  function togglePlay() {
    audioEl.paused ? audioEl.play() : audioEl.pause();
  }

  function onSeekInput() {
    isSeeking = true;
  }

  function onSeekCommit(e) {
    const target = Number(e.target.value);
    if (Number.isFinite(audioEl.duration) && audioEl.duration > 0) {
      audioEl.currentTime = target;
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

<footer>
  <div
    class="currently-playing"
    oncontextmenu={(e) => {
      if ($currentlyPlaying) openContextMenu(e, addToPlaylistItems($currentlyPlaying));
    }}
    role="presentation"
  >
    {#if $currentlyPlaying.thumbnail}
      <img class="thumbnail" src={$currentlyPlaying.thumbnail} alt={$currentlyPlaying.title} />
    {/if}

    <div class="info">
      <span class="title">{$currentlyPlaying.title}</span>
      <span class="artist">{$currentlyPlaying.artist}</span>
    </div>
  </div>

  <div class="controls">
    <button class="pause-play" onclick={togglePlay}>
      {#if isPlaying}
        <svg viewBox="0 0 24 24"><path d="M6 4h4v16H6zM14 4h4v16h-4z"/></svg>
      {:else}
        <svg viewBox="0 0 24 24"><path d="M6 4l14 8-14 8V4z"/></svg>
      {/if}
    </button>

    <div class="progress">
      <span class="time">{formatTime(seekValue)}</span>
      <input type="range" class="progress-slider" style="--fill:{progressPct}%" min="0" max={sliderMax} step="0.1" bind:value={seekValue} oninput={onSeekInput} onchange={onSeekCommit}/>
      <span class="time">{formatTime(duration)}</span>
    </div>
  </div>

  <div></div>

  <audio bind:this={audioEl} bind:duration ontimeupdate={onTimeUpdate} onplay={() => (isPlaying = true)} onpause={() => (isPlaying = false)} onended={() => (isPlaying = false)}></audio>
</footer>
