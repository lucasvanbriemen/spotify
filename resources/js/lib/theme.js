import api from "./api.js";

export default {
  themeUrl: "https://components.lucasvanbriemen.nl/api/colors",

  custom_colors: {
  },

  getTheme() {
    const darkModeMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
    return darkModeMediaQuery.matches ? "dark" : "light";
  },

  async applyTheme() {
    document.documentElement.setAttribute("data-theme", this.getTheme());
    const colors = await api.get(this.themeUrl);

    const mergedColors = { ...this.custom_colors, ...colors };

    Object.keys(mergedColors).forEach(key => {
      const name = `--${key}`;
      const value = this.getTheme() === "dark" ? mergedColors[key].dark : mergedColors[key].light;
      document.documentElement.style.setProperty(name, value);
    });
  },

  init() {
    this.applyTheme();

    window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => {
      this.applyTheme();
    });
  },
};