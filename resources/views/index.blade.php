<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ config('app.name', 'Laravel') }}</title>
    @vite(['resources/js/main.js'])
</head>
<body>
    <script>
        const API_ROUTES = [];
        const currentDomain = window.location.origin;

        function route(name, params = {}) {
            const route = API_ROUTES.find(r => r.name === name);
            let uri = route.uri;

            for (const [key, value] of Object.entries(params)) {
                const cleanKey = key.startsWith('$') ? key.slice(1) : key;
                uri = uri.replace(`{${cleanKey}}`, encodeURIComponent(value));
            }

            return `/${uri}`;
        }
    </script>

    <div id="app"></div>
</body>
</html>