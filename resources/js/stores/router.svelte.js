import Home from '../pages/Home.svelte';
import page from 'page';

const routes = {
    '/': Home,
};

export const router = $state({
    currentComponent: Home,
    params: {},
});

function isSpaPath(pathname) {
    return Object.keys(routes).some((pattern) => {
        const regex = new RegExp(
            '^' + pattern.replace(/:[^/]+/g, '[^/]+') + '$'
        );
        return regex.test(pathname);
    });
}

export function initRouter() {
    document.addEventListener('click', (e) => {
        const a = e.target.closest('a[href]');
        if (!a) return;
        if (a.target && a.target !== '_self') return;
        if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
        let url;
        try { url = new URL(a.href, location.origin); } catch { return; }
        if (url.origin !== location.origin) return;
        if (!isSpaPath(url.pathname)) e.stopImmediatePropagation();
    }, true);

    page('/', () => {
        router.currentComponent = routes['/'];
        router.params = {};
    });

    page('*', (ctx) => {
        if (isSpaPath(ctx.pathname)) {
            page.redirect('/');
        } else {
            window.location.href = ctx.path;
        }
    });

    page.start();
}
