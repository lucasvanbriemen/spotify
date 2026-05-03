<script>
  import Playlist from '../components/home/Playlist.svelte';
  import { playlists } from '../stores/playlists.svelte.js';
</script>

<main>
  {#each $playlists as playlist}
    <Playlist {playlist} />
  {/each}
</main>
