<script>
  import { onMount } from 'svelte';
  import { contextMenu, closeContextMenu } from '../stores/context_menu.svelte.js';
  import '../../scss/context_menu.scss';

  let menuEl;
  let position = $state({ x: 0, y: 0 });

  $effect(() => {
    if ($contextMenu.open) {
      adjustPosition($contextMenu.x, $contextMenu.y);
    }
  });

  function adjustPosition(x, y) {
    position = { x, y };
    queueMicrotask(() => {
      if (!menuEl) return;
      const rect = menuEl.getBoundingClientRect();
      const overflowX = rect.right - window.innerWidth;
      const overflowY = rect.bottom - window.innerHeight;
      position = {
        x: overflowX > 0 ? Math.max(8, x - overflowX - 8) : x,
        y: overflowY > 0 ? Math.max(8, y - overflowY - 8) : y,
      };
    });
  }

  function onDocClick(e) {
    if (!$contextMenu.open) return;
    if (menuEl && menuEl.contains(e.target)) return;
    closeContextMenu();
  }

  function onKey(e) {
    if (e.key === 'Escape') closeContextMenu();
  }

  async function pick(item) {
    closeContextMenu();
    try {
      await item.onSelect?.();
    } catch (err) {
      console.error(err);
    }
  }

  onMount(() => {
    document.addEventListener('mousedown', onDocClick);
    document.addEventListener('contextmenu', onDocClick, true);
    window.addEventListener('keydown', onKey);
    window.addEventListener('blur', closeContextMenu);
    window.addEventListener('resize', closeContextMenu);
    return () => {
      document.removeEventListener('mousedown', onDocClick);
      document.removeEventListener('contextmenu', onDocClick, true);
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('blur', closeContextMenu);
      window.removeEventListener('resize', closeContextMenu);
    };
  });
</script>

{#if $contextMenu.open}
  <div
    class="context-menu"
    bind:this={menuEl}
    style="left: {position.x}px; top: {position.y}px;"
    role="menu"
  >
    {#each $contextMenu.items as item}
      {#if item.type === 'header'}
        <div class="header">{item.label}</div>
      {:else if item.type === 'divider'}
        <div class="divider"></div>
      {:else}
        <button
          class="item"
          class:danger={item.danger}
          role="menuitem"
          onclick={() => pick(item)}
        >
          {#if item.image_url}
            <img src={item.image_url} alt="" />
          {/if}
          <span>{item.label}</span>
        </button>
      {/if}
    {/each}
  </div>
{/if}
