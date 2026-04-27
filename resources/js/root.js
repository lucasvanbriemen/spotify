import theme from "./theme";

const modules = import.meta.glob('./**/*.js', { eager: true });

for (const [path, module] of Object.entries(modules)) {
  if (path === './root.js') continue;
  
  const filename = path.split('/').pop().replace('.js', '');
  window[filename] = module.default;
}

theme.applyTheme();