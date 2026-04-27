import Home from '../pages/Home.svelte';
import page from 'page';

const routes = {
    '/': Home,
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

    page('*', () => {
        page.redirect('/');
    });

    page.start();
}
