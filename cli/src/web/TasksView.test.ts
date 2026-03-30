import { describe, expect, test } from "bun:test";
import { resolveHome, shortenDir } from "./TasksView.tsx";

describe("resolveHome", () => {
  test("replaces /Users/username with ~", () => {
    expect(resolveHome("/Users/shingo/projects")).toBe("~/projects");
  });

  test("handles nested paths", () => {
    expect(resolveHome("/Users/alice/a/b/c")).toBe("~/a/b/c");
  });

  test("does not modify paths already using ~", () => {
    expect(resolveHome("~/projects/myapp")).toBe("~/projects/myapp");
  });

  test("does not modify unrelated absolute paths", () => {
    expect(resolveHome("/usr/local/bin")).toBe("/usr/local/bin");
  });

  test("handles bare home directory", () => {
    expect(resolveHome("/Users/shingo")).toBe("~");
  });

  test("handles ~", () => {
    expect(resolveHome("~")).toBe("~");
  });
});

describe("shortenDir", () => {
  test("returns full path for 1 segment", () => {
    expect(shortenDir("~")).toBe("~");
  });

  test("returns full path for 2 segments", () => {
    expect(shortenDir("~/projects")).toBe("~/projects");
  });

  test("returns full path for 3 segments", () => {
    expect(shortenDir("~/projects/myapp")).toBe("~/projects/myapp");
  });

  test("returns last 2 segments for 4+ segments", () => {
    expect(shortenDir("~/a/b/c")).toBe("b/c");
  });

  test("returns last 2 segments for deeply nested path", () => {
    expect(shortenDir("~/projects/github.com/user/repo")).toBe("user/repo");
  });

  test("resolves /Users/ before shortening", () => {
    expect(shortenDir("/Users/shingo/projects/github.com/user/repo")).toBe("user/repo");
  });

  test("/Users/shingo/projects/myapp resolves to 3 segments and shows full", () => {
    expect(shortenDir("/Users/shingo/projects/myapp")).toBe("~/projects/myapp");
  });
});
