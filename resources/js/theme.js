export default (() => {
  const themeUrl = "https://components.lucasvanbriemen.nl/api/colors";
  const selectedTheme = "auto";

  const getTheme = () => {
    if (selectedTheme === "auto") {
      const darkModeMediaQuery = window.matchMedia("(prefers-color-scheme: dark)");
      return darkModeMediaQuery.matches ? "dark" : "light";
    }

    return selectedTheme;
  };

  const applyTheme = async () => {
    document.documentElement.setAttribute("data-theme", getTheme());

    try {
      const colors = await api.get(themeUrl);
      console.log(colors);
    } catch (err) {
      console.error("Failed to fetch theme colors:", err);
    }
  };

  return { getTheme, applyTheme };
})();