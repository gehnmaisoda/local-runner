import { describe, test, expect } from "bun:test";
import { parseVersion, isNewer } from "./update-check.ts";

describe("parseVersion", () => {
  test("parses simple semver", () => {
    expect(parseVersion("1.2.3")).toEqual([1, 2, 3]);
  });

  test("strips v prefix", () => {
    expect(parseVersion("v1.2.3")).toEqual([1, 2, 3]);
  });

  test("parses two-part version", () => {
    expect(parseVersion("1.0")).toEqual([1, 0]);
  });
});

describe("isNewer", () => {
  test("returns true when latest is newer (patch)", () => {
    expect(isNewer("1.0.1", "1.0.0")).toBe(true);
  });

  test("returns true when latest is newer (minor)", () => {
    expect(isNewer("1.1.0", "1.0.0")).toBe(true);
  });

  test("returns true when latest is newer (major)", () => {
    expect(isNewer("2.0.0", "1.9.9")).toBe(true);
  });

  test("returns false when versions are equal", () => {
    expect(isNewer("1.0.0", "1.0.0")).toBe(false);
  });

  test("returns false when current is newer", () => {
    expect(isNewer("1.0.0", "1.0.1")).toBe(false);
  });

  test("handles v prefix", () => {
    expect(isNewer("v1.1.0", "1.0.0")).toBe(true);
    expect(isNewer("1.1.0", "v1.0.0")).toBe(true);
  });

  test("handles different segment lengths", () => {
    expect(isNewer("1.0.1", "1.0")).toBe(true);
    expect(isNewer("1.0", "1.0.0")).toBe(false);
  });
});
