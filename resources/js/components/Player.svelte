<script>
  import { currentlyPlaying } from '../stores/currently_playing.svelte.js';
  import '../../scss/player.scss';

  console.log('currentlyPlaying', $currentlyPlaying);
</script>

<header>
  <div>
    <span class="artist">{$currentlyPlaying.artist}</span>
    <div class="separator"></div>
    <span class="album">{$currentlyPlaying.album}</span>
    <div class="separator"></div>
    <span class="title">{$currentlyPlaying.title}</span>
  </div>

  <div class="search-container">
    <audio src="{$currentlyPlaying.stream_url}" autoplay controls></audio>
  </div>

  <div></div>
</header>
