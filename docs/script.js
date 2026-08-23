const menuButton = document.querySelector(".menu-button");
const siteNav = document.querySelector(".site-nav");

menuButton?.addEventListener("click", () => {
  const isOpen = menuButton.getAttribute("aria-expanded") === "true";
  menuButton.setAttribute("aria-expanded", String(!isOpen));
  menuButton.setAttribute("aria-label", isOpen ? "Open navigation" : "Close navigation");
  siteNav?.classList.toggle("open", !isOpen);
});

siteNav?.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => {
    menuButton?.setAttribute("aria-expanded", "false");
    menuButton?.setAttribute("aria-label", "Open navigation");
    siteNav.classList.remove("open");
  });
});

const previewImage = document.querySelector("#showcase-image");
const previewTabs = document.querySelectorAll(".preview-tab");

previewTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    if (tab.classList.contains("active") || !previewImage) return;

    previewTabs.forEach((item) => {
      const isActive = item === tab;
      item.classList.toggle("active", isActive);
      item.setAttribute("aria-pressed", String(isActive));
    });

    previewImage.classList.add("changing");
    window.setTimeout(() => {
      previewImage.src = tab.dataset.image;
      previewImage.alt = tab.dataset.alt;
      previewImage.width = Number(tab.dataset.width);
      previewImage.height = Number(tab.dataset.height);
      previewImage.classList.remove("changing");
    }, 140);
  });
});
