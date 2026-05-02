<script>
  import { onMount } from 'svelte';

  let playlists = $state([]);

  onMount(async () => {
    playlists = await api.get(route('playlists'));
  });

</script>

<main>
  {#each playlists as playlist}
    <div>
      <img src={playlist.image_url} alt={playlist.name} />
      {playlist.name}
    </div>
  {/each}
</main>
