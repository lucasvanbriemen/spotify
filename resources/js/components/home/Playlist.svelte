<script>
  let { playlist } = $props();
</script>

<a href="/playlist/{playlist.id}">
  <img src={playlist.image_url} alt={playlist.name} />
  {playlist.name}
</a>