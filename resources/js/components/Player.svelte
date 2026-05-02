<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import '../../scss/player.scss';

  let audioEl;

  $effect(() => {
    if (audioEl && $currentlyPlaying.stream_url) {
      audioEl.src = $currentlyPlaying.stream_url;
      audioEl.load();
      audioEl.play().catch(() => {});
    }
  });
</script>

<footer>
  <div>
    <span class="artist">{$currentlyPlaying.artist}</span>
    <div class="separator"></div>
    <span class="album">{$currentlyPlaying.album}</span>
    <div class="separator"></div>
    <span class="title">{$currentlyPlaying.title}</span>
  </div>

  <div class="search-container">
    <audio bind:this={audioEl} controls></audio>
  </div>

  <div></div>
</footer>
