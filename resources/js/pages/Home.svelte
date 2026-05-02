<script>
  import { onMount } from 'svelte';

  let playlists = [];

  onMount(async () => {
    playlists = await api.get(route('playlists'));
  });

</script>

<main>
  {#each playlists as playlist}
    <div>{playlist.name}</div>
  {/each}
</main>
