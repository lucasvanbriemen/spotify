<script>
  import { onMount } from 'svelte';
  import Playlist from '../components/home/Playlist.svelte';

  let playlists = $state([]);

  onMount(async () => {
    playlists = await api.get(route('playlists'));
  });

</script>

<main>
  {#each playlists as playlist}
    <Playlist {playlist} />
  {/each}
</main>
