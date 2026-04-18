const statusOrder = ["new", "in_progress", "done", "archived"];

const state = {
  tasks: [],
  me: null,
};

const el = {
  apiBaseUrl: document.getElementById("apiBaseUrl"),
  authMode: document.getElementById("authMode"),
  tokenField: document.getElementById("tokenField"),
  tokenInput: document.getElementById("tokenInput"),
  userId: document.getElementById("userId"),
  username: document.getElementById("username"),
  userEmail: document.getElementById("userEmail"),
  userRole: document.getElementById("userRole"),
  refreshBtn: document.getElementById("refreshBtn"),
  createTaskForm: document.getElementById("createTaskForm"),
  taskTitle: document.getElementById("taskTitle"),
  taskDescription: document.getElementById("taskDescription"),
  taskStatus: document.getElementById("taskStatus"),
  board: document.getElementById("board"),
  meBox: document.getElementById("meBox"),
  toast: document.getElementById("toast"),
};

function showToast(message, isError = false) {
  el.toast.textContent = message;
  el.toast.style.background = isError
    ? "linear-gradient(135deg, #b74949, #cc5b5b)"
    : "linear-gradient(135deg, #1f7a7a, #2f9d8b)";
  el.toast.classList.add("show");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => el.toast.classList.remove("show"), 2200);
}

function initDefaults() {
  const cfg = window.APP_CONFIG || {};
  el.apiBaseUrl.value = cfg.apiBaseUrl || "http://localhost:8000";
  el.authMode.value = cfg.authMode || "headers";
  el.userId.value = "dev-user-1";
  el.username.value = "devuser";
  el.userEmail.value = "devuser@example.com";
  el.userRole.value = "developer";
  toggleAuthMode();
  applyUiPermissions();
}

function toggleAuthMode() {
  const mode = el.authMode.value;
  el.tokenField.style.display = mode === "token" ? "flex" : "none";
}

function buildHeaders(isJson = true) {
  const headers = {};
  if (isJson) headers["Content-Type"] = "application/json";

  if (el.authMode.value === "token") {
    const token = el.tokenInput.value.trim();
    if (!token) throw new Error("Заполни JWT token для режима Bearer.");
    headers.Authorization = `Bearer ${token}`;
    return headers;
  }

  headers["X-User-Id"] = el.userId.value.trim() || "dev-user-1";
  headers["X-Username"] = el.username.value.trim() || "devuser";
  headers["X-Email"] = el.userEmail.value.trim() || "devuser@example.com";
  headers["X-Role"] = el.userRole.value;
  return headers;
}

async function apiFetch(path, options = {}) {
  const base = el.apiBaseUrl.value.trim().replace(/\/$/, "");
  if (!base) throw new Error("Укажи API Base URL.");

  const merged = {
    ...options,
    headers: {
      ...(options.headers || {}),
      ...buildHeaders(options.method !== "GET" && options.method !== "DELETE"),
    },
  };

  const response = await fetch(`${base}${path}`, merged);
  if (!response.ok) {
    let detail = `HTTP ${response.status}`;
    try {
      const json = await response.json();
      detail = json.detail || detail;
    } catch (_) {
      /* ignore parsing errors */
    }
    throw new Error(detail);
  }

  if (response.status === 204) return null;
  return response.json();
}

function renderProfile() {
  if (!state.me) {
    el.meBox.innerHTML = '<p class="muted">Профиль не загружен.</p>';
    return;
  }
  el.meBox.innerHTML = `
    <div class="profile-line"><strong>ID</strong><span>${escapeHtml(state.me.id)}</span></div>
    <div class="profile-line"><strong>Username</strong><span>${escapeHtml(state.me.username)}</span></div>
    <div class="profile-line"><strong>Email</strong><span>${escapeHtml(state.me.email || "-")}</span></div>
    <div class="profile-line"><strong>Role</strong><span>${escapeHtml(state.me.role)}</span></div>
  `;
  applyUiPermissions();
}

function groupByStatus(tasks) {
  const grouped = {};
  for (const status of statusOrder) grouped[status] = [];
  for (const task of tasks) {
    if (!grouped[task.status]) grouped[task.status] = [];
    grouped[task.status].push(task);
  }
  return grouped;
}

function createTaskCard(task) {
  const canEdit = canEditTask(task);
  const wrapper = document.createElement("article");
  wrapper.className = "task";
  wrapper.innerHTML = `
    <div class="task-title">${escapeHtml(task.title)}</div>
    <div class="task-meta">
      <span>#${task.id}</span>
      <span>owner: ${escapeHtml(task.owner_username)}</span>
    </div>
    <p class="muted">${escapeHtml(task.description || "Без описания")}</p>
    <div class="task-actions">
      <select data-action="status" ${canEdit ? "" : "disabled"}>
        ${statusOrder
          .map(
            (status) =>
              `<option value="${status}" ${task.status === status ? "selected" : ""}>${status}</option>`,
          )
          .join("")}
      </select>
      <button data-action="edit" class="edit" ${canEdit ? "" : "disabled"}>Изменить</button>
      <button data-action="delete" class="remove" ${canEdit ? "" : "disabled"}>Удалить</button>
    </div>
  `;

  wrapper.querySelector('[data-action="status"]').addEventListener("change", async (event) => {
    try {
      const status = event.target.value;
      await updateTask(task.id, { status });
      showToast(`Статус задачи #${task.id} обновлён.`);
    } catch (error) {
      showToast(error.message, true);
      event.target.value = task.status;
    }
  });

  wrapper.querySelector('[data-action="edit"]').addEventListener("click", async () => {
    const title = window.prompt("Новое название задачи:", task.title);
    if (title === null) return;
    const description = window.prompt("Новое описание задачи:", task.description || "");
    if (description === null) return;
    try {
      await updateTask(task.id, { title, description });
      showToast(`Задача #${task.id} обновлена.`);
    } catch (error) {
      showToast(error.message, true);
    }
  });

  wrapper.querySelector('[data-action="delete"]').addEventListener("click", async () => {
    const confirmDelete = window.confirm(`Удалить задачу #${task.id}?`);
    if (!confirmDelete) return;
    try {
      await apiFetch(`/tasks/${task.id}`, { method: "DELETE" });
      await refreshAll();
      showToast(`Задача #${task.id} удалена.`);
    } catch (error) {
      showToast(error.message, true);
    }
  });

  return wrapper;
}

function canCreateTask() {
  if (!state.me) return false;
  return state.me.role === "admin" || state.me.role === "developer";
}

function canEditTask(task) {
  if (!state.me) return false;
  if (state.me.role === "admin") return true;
  if (state.me.role === "developer" && task.owner_id === state.me.id) return true;
  return false;
}

function applyUiPermissions() {
  const canCreate = canCreateTask();
  const formControls = el.createTaskForm.querySelectorAll("input, textarea, select, button");
  formControls.forEach((node) => {
    node.disabled = !canCreate;
  });
}

function renderBoard() {
  const grouped = groupByStatus(state.tasks);
  el.board.innerHTML = "";

  for (const status of statusOrder) {
    const tasks = grouped[status] || [];
    const col = document.createElement("section");
    col.className = "column";
    col.innerHTML = `<h4>${status}<span class="count">${tasks.length}</span></h4><div class="tasks"></div>`;
    const tasksBox = col.querySelector(".tasks");

    if (!tasks.length) {
      const empty = document.createElement("div");
      empty.className = "empty";
      empty.textContent = "Нет задач";
      tasksBox.appendChild(empty);
    } else {
      for (const task of tasks) tasksBox.appendChild(createTaskCard(task));
    }
    el.board.appendChild(col);
  }
}

async function refreshAll() {
  const [me, tasks] = await Promise.all([apiFetch("/me"), apiFetch("/tasks")]);
  state.me = me;
  state.tasks = tasks;
  renderProfile();
  renderBoard();
}

async function updateTask(taskId, payload) {
  await apiFetch(`/tasks/${taskId}`, {
    method: "PUT",
    body: JSON.stringify(payload),
  });
  await refreshAll();
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

el.authMode.addEventListener("change", toggleAuthMode);
el.refreshBtn.addEventListener("click", async () => {
  try {
    await refreshAll();
    showToast("Данные обновлены.");
  } catch (error) {
    showToast(error.message, true);
  }
});

el.createTaskForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const payload = {
    title: el.taskTitle.value.trim(),
    description: el.taskDescription.value.trim(),
    status: el.taskStatus.value,
  };
  if (!payload.title) {
    showToast("Название задачи не может быть пустым.", true);
    return;
  }
  try {
    await apiFetch("/tasks", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    el.taskTitle.value = "";
    el.taskDescription.value = "";
    el.taskStatus.value = "new";
    await refreshAll();
    showToast("Задача создана.");
  } catch (error) {
    showToast(error.message, true);
  }
});

initDefaults();
refreshAll()
  .then(() => showToast("Интерфейс готов к работе."))
  .catch((error) => showToast(error.message, true));
