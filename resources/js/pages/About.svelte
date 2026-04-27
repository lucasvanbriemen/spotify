<script>
    import { onMount } from 'svelte';
    import theme from '../lib/theme.js';

    let currentTheme = $state('auto');

    onMount(() => {
        console.log('About page mounted');
        currentTheme = theme.selectedTheme;
    });

    function changeTheme(newTheme) {
        currentTheme = newTheme;
        theme.setTheme(newTheme);
    }
</script>

<h1>About Page</h1>
<p>This is the about page. You can add your content here.</p>

<section>
    <h2>Features</h2>
    <ul>
        <li>Svelte 5 with runes mode</li>
        <li>Client-side routing with Page.js</li>
        <li>API integration wrapper</li>
        <li>Theme system (Light/Dark/Auto)</li>
        <li>Laravel SPA integration</li>
        <li>Reusable stores and components</li>
    </ul>
</section>

<section>
    <h2>Theme Switcher</h2>
    <p>Current theme: <strong>{currentTheme}</strong></p>
    <div class="theme-buttons">
        <button onclick={() => changeTheme('light')} class:active={currentTheme === 'light'}>Light</button>
        <button onclick={() => changeTheme('dark')} class:active={currentTheme === 'dark'}>Dark</button>
        <button onclick={() => changeTheme('auto')} class:active={currentTheme === 'auto'}>Auto</button>
    </div>
</section>

<style>
    h1 {
        color: #333;
    }

    h2 {
        color: #555;
    }

    ul {
        list-style-type: disc;
        padding-left: 1.5rem;
    }

    li {
        margin-bottom: 0.5rem;
    }

    section {
        margin: 2rem 0;
        padding: 1rem;
        border: 1px solid #ddd;
        border-radius: 4px;
    }

    .theme-buttons {
        display: flex;
        gap: 1rem;
        margin-top: 1rem;
    }

    .theme-buttons button {
        background-color: #f0f0f0;
        color: #333;
        border: 2px solid #ddd;
        padding: 0.5rem 1rem;
        border-radius: 4px;
        cursor: pointer;
        font-size: 1rem;
        transition: all 0.3s;
    }

    .theme-buttons button:hover {
        background-color: #e0e0e0;
    }

    .theme-buttons button.active {
        background-color: #007bff;
        color: white;
        border-color: #0056b3;
    }
</style>
