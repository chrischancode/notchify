(() => {
  const notch = document.getElementById("notch");
  const handle = document.getElementById("notchHandle");
  const grid = notch.querySelector(".drawer-grid");
  const hint = document.getElementById("demoHint");
  const earLeft = notch.querySelector(".ear-left");
  const earRight = notch.querySelector(".ear-right");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // ---------- Open / close ----------
  // The drawer starts open as the hero; scrolling away tucks it back in,
  // and scrolling back to the top reopens it unless the visitor closed it.
  let closedByUser = false;

  function setOpen(open) {
    notch.classList.toggle("is-open", open);
    handle.setAttribute("aria-expanded", String(open));
    if (hint) {
      hint.textContent = open
        ? "The drawer above is a working demo. Click the notch to close it."
        : "Click the notch at the top of the page to open the drawer.";
    }
    if (!open) stopMirror();
    updateEars();
  }
  const isOpen = () => notch.classList.contains("is-open");

  handle.addEventListener("click", () => {
    const next = !isOpen();
    closedByUser = !next;
    setOpen(next);
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isOpen()) {
      closedByUser = true;
      setOpen(false);
      handle.focus();
    }
  });

  document.addEventListener("pointerdown", (e) => {
    if (isOpen() && !notch.contains(e.target) && window.scrollY > 120) setOpen(false);
  });

  let ticking = false;
  window.addEventListener("scroll", () => {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(() => {
      ticking = false;
      const y = window.scrollY;
      if (y > 160 && isOpen() && !notch.matches(":focus-within")) setOpen(false);
      else if (y < 40 && !isOpen() && !closedByUser) setOpen(true);
    });
  }, { passive: true });

  // ---------- Tabs ----------
  const tabs = notch.querySelectorAll('[role="tab"]');
  const panes = {
    files: notch.querySelector(".pane-files"),
    airdrop: notch.querySelector(".pane-airdrop"),
    notes: notch.querySelector(".pane-notes"),
  };
  function selectTab(name) {
    grid.dataset.tab = name;
    tabs.forEach((t) => t.setAttribute("aria-selected", String(t.dataset.tab === name)));
    Object.entries(panes).forEach(([key, el]) => { el.hidden = key !== name; });
  }
  tabs.forEach((t) => t.addEventListener("click", () => selectTab(t.dataset.tab)));

  // ---------- Closed-state "ears" ----------
  let playing = false;
  let timer = null; // { phase: "focus" | "break", end: number }

  function fmt(ms) {
    const s = Math.max(0, Math.ceil(ms / 1000));
    return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
  }

  function updateEars() {
    const active = Boolean(timer) || playing;
    notch.classList.toggle("has-activity", active);
    if (timer) {
      const isBreak = timer.phase === "break";
      earLeft.innerHTML = `<svg class="${isBreak ? "is-green" : "is-orange"}"><use href="#${isBreak ? "i-cup" : "i-timer"}"/></svg>`;
      earRight.textContent = fmt(timer.end - Date.now());
    } else if (playing) {
      earLeft.innerHTML = '<span class="mini-art"></span>';
      earRight.innerHTML = '<span class="bars"><i></i><i></i><i></i><i></i></span>';
    } else {
      earLeft.textContent = "";
      earRight.textContent = "";
    }
  }

  // ---------- Pomodoro ----------
  const pomoBtn = notch.querySelector('[data-act="pomodoro"]');
  const pomoTime = pomoBtn.querySelector(".act-time");
  let tickId = null;

  function renderPomodoro() {
    pomoBtn.classList.toggle("is-running", timer?.phase === "focus");
    pomoBtn.classList.toggle("is-break", timer?.phase === "break");
    pomoTime.textContent = timer ? fmt(timer.end - Date.now()) : "";
    pomoBtn.setAttribute("aria-label", timer ? "Stop the timer" : "Start a 25 minute focus timer");
    pomoBtn.querySelector("use").setAttribute("href", timer?.phase === "break" ? "#i-cup" : "#i-timer");
    updateEars();
  }

  function startPhase(phase, minutes) {
    timer = { phase, end: Date.now() + minutes * 60 * 1000 };
    clearInterval(tickId);
    tickId = setInterval(() => {
      if (timer && Date.now() >= timer.end) {
        if (timer.phase === "focus") startPhase("break", 5);
        else stopPomodoro();
        return;
      }
      renderPomodoro();
    }, 1000);
    renderPomodoro();
  }
  function stopPomodoro() {
    clearInterval(tickId);
    timer = null;
    renderPomodoro();
  }
  pomoBtn.addEventListener("click", () => (timer ? stopPomodoro() : startPhase("focus", 25)));

  // ---------- Capture ----------
  notch.querySelector('[data-act="capture"]').addEventListener("click", () => {
    closedByUser = true;
    setOpen(false);
    if (reduceMotion) return;
    const flash = document.createElement("div");
    flash.style.cssText = "position:fixed;inset:0;background:#fff;z-index:50;pointer-events:none;opacity:.85;transition:opacity .5s ease";
    document.body.appendChild(flash);
    setTimeout(() => {
      flash.style.opacity = "0";
      setTimeout(() => flash.remove(), 520);
    }, 260);
  });

  // ---------- Music ----------
  const playBtn = document.getElementById("playBtn");
  playBtn.addEventListener("click", () => {
    playing = !playing;
    playBtn.querySelector("use").setAttribute("href", playing ? "#i-pause" : "#i-play");
    playBtn.setAttribute("aria-label", playing ? "Pause" : "Play");
    updateEars();
  });

  // ---------- Shelf (real drag and drop, files never leave the page) ----------
  const shelfList = document.getElementById("shelfList");
  function addFile(file) {
    const li = document.createElement("li");
    li.className = "file";
    const thumb = document.createElement("span");
    thumb.className = "thumb thumb-any";
    if (file.type.startsWith("image/")) {
      const url = URL.createObjectURL(file);
      thumb.style.background = `center / cover no-repeat url("${url}")`;
    } else {
      thumb.textContent = (file.name.split(".").pop() || "FILE").slice(0, 4).toUpperCase();
    }
    const name = document.createElement("span");
    name.className = "fname";
    name.textContent = file.name;
    name.title = file.name;
    li.append(thumb, name);
    shelfList.prepend(li);
  }

  function dropZone(el, onFiles) {
    el.addEventListener("dragover", (e) => { e.preventDefault(); el.classList.add("is-target"); });
    el.addEventListener("dragleave", () => el.classList.remove("is-target"));
    el.addEventListener("drop", (e) => {
      e.preventDefault();
      el.classList.remove("is-target");
      const files = [...(e.dataTransfer?.files || [])];
      if (files.length) onFiles(files);
    });
  }
  dropZone(panes.files, (files) => files.forEach(addFile));
  const airdropText = panes.airdrop.querySelector("p");
  dropZone(panes.airdrop, (files) => {
    airdropText.textContent = `On your Mac, ${files.length === 1 ? "this file" : `these ${files.length} files`} would open in AirDrop now.`;
  });

  // Dragging a file toward the top of the window opens the drawer, as in the app.
  window.addEventListener("dragover", (e) => {
    if (e.clientY < 90 && !isOpen()) {
      closedByUser = false;
      setOpen(true);
    }
  });
  // Stop the browser from opening files dropped outside the drawer.
  window.addEventListener("drop", (e) => { if (!notch.contains(e.target)) e.preventDefault(); });

  // ---------- Camera mirror ----------
  const video = document.getElementById("mirrorVideo");
  const mirrorOff = document.getElementById("mirrorOff");
  const mirrorBtn = document.getElementById("mirrorBtn");
  const mirrorStop = document.getElementById("mirrorStop");
  const mirrorNote = document.getElementById("mirrorNote");
  let stream = null;

  async function startMirror() {
    if (!navigator.mediaDevices?.getUserMedia) {
      mirrorNote.textContent = "This browser can't use the camera.";
      return;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { width: 320, height: 240 }, audio: false });
      video.srcObject = stream;
      video.hidden = false;
      mirrorOff.hidden = true;
      mirrorStop.hidden = false;
      await video.play();
    } catch {
      mirrorNote.textContent = "Camera access was blocked. Allow it in your browser's site settings to try the mirror.";
      stopMirror();
    }
  }
  function stopMirror() {
    stream?.getTracks().forEach((t) => t.stop());
    stream = null;
    if (video) {
      video.srcObject = null;
      video.hidden = true;
    }
    if (mirrorOff) mirrorOff.hidden = false;
    if (mirrorStop) mirrorStop.hidden = true;
  }
  mirrorBtn.addEventListener("click", startMirror);
  mirrorStop.addEventListener("click", stopMirror);

  // ---------- Notes (kept in this browser only) ----------
  const notes = document.getElementById("notes");
  try {
    const saved = localStorage.getItem("notchify-demo-notes");
    if (saved !== null) notes.value = saved;
  } catch {}
  notes.addEventListener("input", () => {
    try { localStorage.setItem("notchify-demo-notes", notes.value); } catch {}
  });

  // ---------- Copy command ----------
  const copyBtn = document.getElementById("copyBtn");
  const cmd = document.getElementById("cmd").textContent.trim();
  copyBtn.addEventListener("click", async () => {
    let ok = false;
    try {
      await navigator.clipboard.writeText(cmd);
      ok = true;
    } catch {
      const ta = document.createElement("textarea");
      ta.value = cmd;
      ta.style.position = "fixed";
      ta.style.opacity = "0";
      document.body.appendChild(ta);
      ta.select();
      try { ok = document.execCommand("copy"); } catch {}
      ta.remove();
    }
    const label = copyBtn.querySelector("span");
    copyBtn.querySelector("use").setAttribute("href", ok ? "#i-check" : "#i-copy");
    label.textContent = ok ? "Copied" : "Select and copy";
    copyBtn.classList.toggle("is-done", ok);
    setTimeout(() => {
      copyBtn.querySelector("use").setAttribute("href", "#i-copy");
      label.textContent = "Copy";
      copyBtn.classList.remove("is-done");
    }, 2000);
  });

  // ---------- Start ----------
  if (window.scrollY > 120) {
    setOpen(false);
  } else if (reduceMotion) {
    setOpen(true);
  } else {
    // The one orchestrated moment: the drawer drops out of the notch.
    setTimeout(() => { if (window.scrollY < 120) setOpen(true); }, 450);
  }
})();
