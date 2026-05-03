<script>
  import Playlist from '../components/home/Playlist.svelte';
  import { playlistsState } from '../stores/playlists.svelte.js';
</script>

<main>
  {#each playlistsState.list as playlist}
    <Playlist {playlist} />
  {/each}
</main>
