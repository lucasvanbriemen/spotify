export default {
  selectedTheme: "auto",

  custom_colors: [
    // Add custom color definitions here
    // { name: "primary", light: "#0066cc", dark: "#3399ff" }
  ],

  getTheme() {
    if (this.selectedTheme === "auto") {
      const darkModeMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
      return darkModeMediaQuery.matches ? "dark" : "light";
    }

    return this.selectedTheme;
  },

  setTheme(theme) {
    this.selectedTheme = theme;
    this.applyTheme();
    localStorage.setItem("theme", theme);
  },

  applyTheme() {
    const theme = this.getTheme();
    document.documentElement.setAttribute("data-theme", theme);

    // Apply custom colors
    this.custom_colors.forEach(color => {
      const name = `--${color.name}`;
      const value = theme === "dark" ? color.dark : color.light;
      document.documentElement.style.setProperty(name, value);
    });
  },

  init() {
    const savedTheme = localStorage.getItem("theme");
    if (savedTheme) {
      this.selectedTheme = savedTheme;
    }
    this.applyTheme();
  },
};
