import { currentlyPlaying } from './currently_playing.svelte.js';

export const queueState = $state({ songs: [], index: 0, autoExtend: false });

const MAX_SKIP_ATTEMPTS = 5;
const streamUrlCache = new Map();

function normalize(song) {
  return {
    id: song.id ?? song.mp3_url,
    title: song.title ?? song.name,
    artist: song.artist ?? '',
    album: song.album ?? '',
    thumbnail: song.thumbnail ?? song.image_url ?? '',
    duration: song.duration ?? (song.duration_ms ? Math.round(song.duration_ms / 1000) : 0),
  };
}

function fetchStreamUrl(id) {
  if (streamUrlCache.has(id)) return streamUrlCache.get(id);

  const promise = window.api
    .get(`${route('get-mp3-url')}?id=${encodeURIComponent(id)}`)
    .then((data) => data?.stream_url ?? null)
    .catch(() => null);

  streamUrlCache.set(id, promise);

  promise.then((url) => {
    if (!url) streamUrlCache.delete(id);
  });

  return promise;
}

async function extendFromRecommendations() {
  const seed = normalize(queueState.songs[queueState.index]);
  if (!seed.id) return false;

  const recs = await window.api.get(`${route('recommendations')}?seed=${encodeURIComponent(seed.id)}`);
  if (!Array.isArray(recs) || recs.length === 0) return false;

  const seen = new Set(queueState.songs.map((s) => s.id ?? s.mp3_url));
  const fresh = recs.filter((r) => !seen.has(r.id));
  if (fresh.length === 0) return false;

  queueState.songs = [...queueState.songs, ...fresh];
  return true;
}

async function ensureNextExists() {
  if (queueState.index < queueState.songs.length - 1) return true;
  if (!queueState.autoExtend) return false;
  return extendFromRecommendations();
}

async function advance() {
  const ok = await ensureNextExists();
  if (!ok) return false;
  queueState.index += 1;
  return true;
}

async function prefetchNext() {
  const ok = await ensureNextExists();
  if (!ok) return;

  const nextRaw = queueState.songs[queueState.index + 1];
  const id = nextRaw?.id ?? nextRaw?.mp3_url;
  if (!id) return;

  fetchStreamUrl(id);
}

async function playCurrent({ skipsRemaining = MAX_SKIP_ATTEMPTS } = {}) {
  const raw = queueState.songs[queueState.index];
  if (!raw) return;

  const song = normalize(raw);
  if (!song.id) return;

  const streamUrl = await fetchStreamUrl(song.id);
  if (streamUrl) {
    currentlyPlaying.set({ ...song, stream_url: streamUrl });
    prefetchNext();
    return;
  }

  if (skipsRemaining <= 0) return;
  const advanced = await advance();
  if (!advanced) return;
  await playCurrent({ skipsRemaining: skipsRemaining - 1 });
}

export async function playFromQueue(songs, index = 0, { autoExtend = false } = {}) {
  queueState.songs = songs;
  queueState.index = index;
  queueState.autoExtend = autoExtend;
  await playCurrent();
}

export async function playNext() {
  const advanced = await advance();
  if (!advanced) return;
  await playCurrent();
}
