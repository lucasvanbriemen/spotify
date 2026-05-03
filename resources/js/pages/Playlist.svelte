<script>
  import { onMount } from 'svelte';

  let playlist = $state({});
  let { id } = $props();

  onMount(async () => {
    playlist = await api.get(route('playlist.show', { playlist: id }));
    console.log(playlist);
  });
</script>

<main>
  <img src={playlist.image_url} alt={playlist.name} />
  {playlist.name}
</main>