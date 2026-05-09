import { writable } from 'svelte/store';

export const currentlyPlaying = writable({
  title: 'No track playing',
  artist: 'Nothing to see here',
  album: '',

  thumbnail: '',
  duration: 0,
  position: 0,
  isPaused: false,
  stream_url: '',
});

export let queue = writable([]);
export let randomState = writable(true);
export let pastTracks = writable([]);