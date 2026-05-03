export const playlistsState = $state({ list: [] });

export async function loadPlaylists() {
  const data = await window.api.get(route('playlists'));
  playlistsState.list = Array.isArray(data) ? data : [];
}
