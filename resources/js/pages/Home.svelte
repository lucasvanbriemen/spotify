<script>
  import { onMount } from 'svelte';

  let playlists = $state([]);

  onMount(async () => {
    playlists = await api.get(route('playlists'));
  });

</script>

<main>
  {#each playlists as playlist}
    <a href="/playlist/{playlist.id}">
      <img src={playlist.image_url} alt={playlist.name} />
      {playlist.name}
    </a>
  {/each}
</main>
