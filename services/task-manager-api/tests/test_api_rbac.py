def auth_headers(role: str, user_id: str, username: str | None = None) -> dict[str, str]:
    return {
        "X-Role": role,
        "X-User-Id": user_id,
        "X-Username": username or user_id,
        "X-Email": f"{user_id}@example.local",
    }


def create_task(client, headers: dict[str, str], title: str, status: str = "new"):
    return client.post(
        "/tasks",
        headers=headers,
        json={"title": title, "description": "test task", "status": status},
    )


def test_healthcheck_returns_ok(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_me_returns_current_user_from_development_headers(client):
    response = client.get("/me", headers=auth_headers("developer", "dev-1", "devuser"))

    assert response.status_code == 200
    assert response.json() == {
        "id": "dev-1",
        "username": "devuser",
        "email": "dev-1@example.local",
        "role": "developer",
    }


def test_viewer_cannot_create_tasks(client):
    response = create_task(client, auth_headers("viewer", "viewer-1"), "viewer task")

    assert response.status_code == 403
    assert response.json()["detail"] == "Insufficient role permissions"


def test_admin_can_create_update_and_delete_any_task(client):
    admin_headers = auth_headers("admin", "admin-1")
    developer_headers = auth_headers("developer", "dev-1")
    created = create_task(client, developer_headers, "developer task")
    task_id = created.json()["id"]

    update_response = client.put(
        f"/tasks/{task_id}",
        headers=admin_headers,
        json={"status": "done", "description": "updated by admin"},
    )
    delete_response = client.delete(f"/tasks/{task_id}", headers=admin_headers)
    get_after_delete_response = client.get(f"/tasks/{task_id}", headers=admin_headers)

    assert created.status_code == 201
    assert update_response.status_code == 200
    assert update_response.json()["status"] == "done"
    assert delete_response.status_code == 204
    assert get_after_delete_response.status_code == 404


def test_developer_can_manage_only_own_tasks(client):
    owner_headers = auth_headers("developer", "dev-owner")
    other_headers = auth_headers("developer", "dev-other")
    owner_task = create_task(client, owner_headers, "owner task")
    other_task = create_task(client, other_headers, "other task")

    owner_task_id = owner_task.json()["id"]
    other_task_id = other_task.json()["id"]

    own_update = client.put(f"/tasks/{owner_task_id}", headers=owner_headers, json={"status": "in_progress"})
    other_read = client.get(f"/tasks/{other_task_id}", headers=owner_headers)
    other_update = client.put(f"/tasks/{other_task_id}", headers=owner_headers, json={"status": "done"})
    other_delete = client.delete(f"/tasks/{other_task_id}", headers=owner_headers)
    list_response = client.get("/tasks", headers=owner_headers)

    assert owner_task.status_code == 201
    assert other_task.status_code == 201
    assert own_update.status_code == 200
    assert other_read.status_code == 403
    assert other_update.status_code == 403
    assert other_delete.status_code == 403
    assert [task["owner_id"] for task in list_response.json()] == ["dev-owner"]


def test_viewer_can_read_existing_tasks_but_cannot_modify_them(client):
    admin_headers = auth_headers("admin", "admin-1")
    viewer_headers = auth_headers("viewer", "viewer-1")
    task = create_task(client, admin_headers, "visible task")
    task_id = task.json()["id"]

    list_response = client.get("/tasks", headers=viewer_headers)
    get_response = client.get(f"/tasks/{task_id}", headers=viewer_headers)
    update_response = client.put(f"/tasks/{task_id}", headers=viewer_headers, json={"status": "archived"})
    delete_response = client.delete(f"/tasks/{task_id}", headers=viewer_headers)

    assert task.status_code == 201
    assert list_response.status_code == 200
    assert len(list_response.json()) == 1
    assert get_response.status_code == 200
    assert update_response.status_code == 403
    assert delete_response.status_code == 403


def test_task_payload_validation(client):
    headers = auth_headers("developer", "dev-1")
    empty_title_response = client.post("/tasks", headers=headers, json={"title": "", "status": "new"})
    invalid_status_response = client.post("/tasks", headers=headers, json={"title": "bad status", "status": "blocked"})

    assert empty_title_response.status_code == 422
    assert invalid_status_response.status_code == 422
