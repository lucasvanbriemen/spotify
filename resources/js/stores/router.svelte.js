import About from '../pages/About.svelte';
import Home from '../pages/Home.svelte';
import page from 'page';

const routes = {
    '/': Home,
    '/about': About,
};

export const router = $state({
    currentComponent: Home,
    params: {},
});

export function initRouter() {
    page('/', () => {
        router.currentComponent = routes['/'];
        router.params = {};
    });

    page('/about', () => {
        router.currentComponent = routes['/about'];
        router.params = {};
    });

    page('*', () => {
        page.redirect('/');
    });

    page.start();
}
