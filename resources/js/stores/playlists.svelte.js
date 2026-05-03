import { writable } from 'svelte/store';

export const playlists = writable([]);

export async function loadPlaylists() {
  const data = await window.api.get(route('playlists'));
  playlists.set(Array.isArray(data) ? data : []);
}
