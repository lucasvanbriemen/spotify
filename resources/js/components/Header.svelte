<script>
  import Icon from './Icon.svelte';
  import { searchQuery } from '../stores/search_query.svelte.js';
  import '../../scss/header.scss';
</script>

<header>
  <a class="logo" href="#/">
    <Icon name="logo" size="2rem" />
    <span class="title">Music</span>
  </a>

  <div class="separator"></div>

  <span>playlist #1</span>

  <input type="text" placeholder="search" bind:value={$searchQuery}>
</header>
