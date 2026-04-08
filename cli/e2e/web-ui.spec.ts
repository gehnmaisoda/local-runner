import { test, expect } from "@playwright/test";

// Mock task data used across tests
const mockTasks = [
  {
    task: {
      id: "task-1",
      name: "Daily Backup",
      command: "echo backup",
      working_directory: "/Users/testuser/projects",
      schedule: { type: "daily", time: "09:00" },
      enabled: true,
      catch_up: true,
      slack_notify: true,
    },
    isRunning: false,
    nextRunAt: "2026-04-01T00:00:00Z",
    lastRun: {
      id: "r1",
      taskId: "task-1",
      taskName: "Daily Backup",
      command: "echo backup",
      working_directory: "/Users/testuser/projects",
      startedAt: "2026-03-31T00:00:00Z",
      finishedAt: "2026-03-31T00:00:05Z",
      status: "success",
      exitCode: 0,
      stdout: "backup done",
      stderr: "",
    },
  },
  {
    task: {
      id: "task-2",
      name: "Health Check",
      command: "curl localhost:3000/health",
      schedule: { type: "hourly", minute: 0 },
      enabled: true,
      catch_up: false,
      slack_notify: true,
    },
    isRunning: false,
    nextRunAt: "2026-04-01T01:00:00Z",
  },
];

const mockSettings = {
  success: true,
  settings: {
    slack_bot_token: "",
    slack_channel: "",
    default_timeout: 3600,
  },
};

function setupMockRoutes(page: import("@playwright/test").Page) {
  return Promise.all([
    page.route("**/api/tasks", (route) => {
      if (route.request().method() === "GET") {
        route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ success: true, tasks: mockTasks }),
        });
      } else {
        route.fulfill({
          status: 200,
          contentType: "application/json",
          body: JSON.stringify({ success: true }),
        });
      }
    }),
    page.route("**/api/history*", (route) => {
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ success: true, history: [] }),
      });
    }),
    page.route("**/api/settings", (route) => {
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify(mockSettings),
      });
    }),
    page.route("**/api/check-dir*", (route) => {
      route.fulfill({
        status: 200,
        contentType: "application/json",
        body: JSON.stringify({ exists: true }),
      });
    }),
  ]);
}

test.describe("Web UI", () => {
  test("page loads and shows the app header", async ({ page }) => {
    await setupMockRoutes(page);
    await page.goto("/");
    await expect(page.locator("h1")).toHaveText("LocalRunner");
  });

  test("disconnected state shown when daemon is not running", async ({ page }) => {
    // Mock API to return errors (simulating daemon not running)
    await page.route("**/api/tasks", (route) => {
      route.fulfill({
        status: 502,
        contentType: "application/json",
        body: JSON.stringify({ error: "daemon not connected" }),
      });
    });
    await page.route("**/api/settings", (route) => {
      route.fulfill({
        status: 502,
        contentType: "application/json",
        body: JSON.stringify({ error: "daemon not connected" }),
      });
    });
    await page.route("**/api/history*", (route) => {
      route.fulfill({
        status: 502,
        contentType: "application/json",
        body: JSON.stringify({ error: "daemon not connected" }),
      });
    });

    await page.goto("/");
    // Should show disconnected view
    await expect(page.locator("text=デーモンに接続できません")).toBeVisible({ timeout: 5000 });
  });

  test("task list renders when API returns tasks", async ({ page }) => {
    await setupMockRoutes(page);
    await page.goto("/");

    // Wait for tasks to be rendered
    await expect(page.locator("text=Daily Backup")).toBeVisible({ timeout: 5000 });
    await expect(page.locator("text=Health Check")).toBeVisible();
  });

  test("can open task editor by clicking new task button", async ({ page }) => {
    await setupMockRoutes(page);
    await page.goto("/");

    // Wait for the page to load
    await expect(page.locator("text=Daily Backup")).toBeVisible({ timeout: 5000 });

    // Click "new task" button
    await page.click("text=新規タスク");

    // Should show the new task modal
    await expect(page.locator("text=新規タスク").last()).toBeVisible();
    await expect(page.locator("text=タスク名").first()).toBeVisible();
  });

  test("can navigate to settings page", async ({ page }) => {
    await setupMockRoutes(page);
    await page.goto("/");

    // Wait for page load
    await expect(page.locator("h1")).toHaveText("LocalRunner");

    // Click settings tab
    await page.click("text=設定");

    // Should show settings view
    await expect(page.locator("text=Slack 通知")).toBeVisible({ timeout: 5000 });
    await expect(page.locator("text=Bot Token")).toBeVisible();
  });

  test("cron validation warning appears for invalid expression", async ({ page }) => {
    await setupMockRoutes(page);
    await page.goto("/");

    // Wait for tasks to load
    await expect(page.locator("text=Daily Backup")).toBeVisible({ timeout: 5000 });

    // Click new task button
    await page.click("text=新規タスク");

    // Wait for modal
    await expect(page.locator(".modal-new-task")).toBeVisible({ timeout: 5000 });

    // Select cron schedule type within the modal
    const modal = page.locator(".modal-new-task");
    await modal.locator(".sched-pill", { hasText: "cron 式" }).click({ force: true });

    // Type an invalid cron expression (only 3 fields)
    const cronInput = modal.locator(".sched-cron");
    await cronInput.fill("* * *");

    // Should show validation error
    await expect(modal.locator(".field-error")).toBeVisible({ timeout: 3000 });
    await expect(modal.locator(".field-error")).toContainText("5");
  });
});
