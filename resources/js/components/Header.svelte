<script>
  import Icon from './Icon.svelte';
  import SearchResult from './SearchResult.svelte';
  import { searchQuery } from '../stores/search_query.svelte.js';
  import '../../scss/header.scss';

  let results = $state([]);
  let resultsVisible = $state(false);
  let searchTimer = null;

  async function getResults() {
    const query = $searchQuery;

    results = await api.get(route('search') + '?q=' + encodeURIComponent(query));
    resultsVisible = true;
  }

  function onQueryInput() {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => getResults(), 250);
  }
</script>

<header>
  <div>
    <a class="logo" href="#/">
      <Icon name="logo" size="2rem" />
      <span class="title">Music</span>
    </a>

    <div class="separator"></div>

    <span>playlist #1</span>
  </div>

  <div class="search-container">
    <input type="text" placeholder="search" bind:value={$searchQuery} on:input={onQueryInput} />
    <Icon name="search" size="1.25rem" className="search-icon" />

    <div class="search-results" class:visible={resultsVisible}>
      {#each results as result}
        <SearchResult {result} on:click={() => playVideo(result)} />
      {/each}
    </div>
  </div>

  <div></div>
</header>
