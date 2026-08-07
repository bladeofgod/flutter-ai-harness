(() => {
  const copyButtons = document.querySelectorAll("[data-copy-target]");

  const writeText = async (value) => {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
      return;
    }

    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();
    if (!copied) {
      throw new Error("Clipboard copy was rejected");
    }
  };

  for (const button of copyButtons) {
    const originalLabel = button.textContent.trim();
    let resetTimer;

    button.addEventListener("click", async () => {
      const target = document.getElementById(button.dataset.copyTarget);
      const status = button
        .closest(".prompt-panel")
        ?.querySelector(".copy-status");
      if (!target) {
        return;
      }

      window.clearTimeout(resetTimer);
      try {
        await writeText(target.textContent.trim());
        button.textContent = button.dataset.copySuccess;
        button.classList.add("is-copied");
        if (status) {
          status.textContent = button.dataset.copySuccess;
        }
      } catch (_) {
        target.focus();
        button.textContent = originalLabel;
        button.classList.remove("is-copied");
        if (status) {
          status.textContent = button.dataset.copyFailure;
        }
        return;
      }

      resetTimer = window.setTimeout(() => {
        button.textContent = originalLabel;
        button.classList.remove("is-copied");
        if (status) {
          status.textContent = "";
        }
      }, 2400);
    });
  }
})();
