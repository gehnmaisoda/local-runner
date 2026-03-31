import { describe, test, expect } from "bun:test";
import { validateCron } from "./TasksView.tsx";

describe("validateCron", () => {
  describe("valid expressions", () => {
    test("standard 5-field cron", () => {
      expect(validateCron("* * * * *")).toBeNull();
    });

    test("specific values", () => {
      expect(validateCron("0 9 * * *")).toBeNull();
    });

    test("ranges", () => {
      expect(validateCron("0-30 * * * *")).toBeNull();
    });

    test("steps", () => {
      expect(validateCron("*/15 * * * *")).toBeNull();
    });

    test("lists (commas)", () => {
      expect(validateCron("0,15,30,45 * * * *")).toBeNull();
    });

    test("complex expression", () => {
      expect(validateCron("0,30 9-17 * * 1-5")).toBeNull();
    });

    test("all wildcards", () => {
      expect(validateCron("* * * * *")).toBeNull();
    });

    test("step with range", () => {
      expect(validateCron("0-59/15 * * * *")).toBeNull();
    });

    test("expression with extra whitespace", () => {
      expect(validateCron("  0  9  *  *  *  ")).toBeNull();
    });
  });

  describe("invalid expressions - wrong number of fields", () => {
    test("too few fields (3)", () => {
      const result = validateCron("* * *");
      expect(result).not.toBeNull();
      expect(result).toContain("5");
      expect(result).toContain("3");
    });

    test("too few fields (4)", () => {
      const result = validateCron("* * * *");
      expect(result).not.toBeNull();
      expect(result).toContain("4");
    });

    test("too many fields (6)", () => {
      const result = validateCron("* * * * * *");
      expect(result).not.toBeNull();
      expect(result).toContain("6");
    });

    test("single value", () => {
      const result = validateCron("5");
      expect(result).not.toBeNull();
      expect(result).toContain("1");
    });
  });

  describe("invalid expressions - invalid characters", () => {
    test("letters in field", () => {
      const result = validateCron("abc * * * *");
      expect(result).not.toBeNull();
      expect(result).toContain("無効な文字");
    });

    test("special characters", () => {
      const result = validateCron("0 9 * * @");
      expect(result).not.toBeNull();
      expect(result).toContain("無効な文字");
    });

    test("question mark", () => {
      const result = validateCron("0 9 ? * *");
      expect(result).not.toBeNull();
    });

    test("hash symbol", () => {
      const result = validateCron("0 9 * * 1#2");
      expect(result).not.toBeNull();
    });

    test("L character", () => {
      const result = validateCron("0 9 L * *");
      expect(result).not.toBeNull();
    });

    test("W character", () => {
      const result = validateCron("0 9 15W * *");
      expect(result).not.toBeNull();
    });
  });

  describe("edge cases", () => {
    test("empty string returns null (valid)", () => {
      expect(validateCron("")).toBeNull();
    });

    test("whitespace-only returns null (valid)", () => {
      expect(validateCron("   ")).toBeNull();
    });

    test("identifies which field has invalid chars", () => {
      const result = validateCron("0 9 * abc *");
      expect(result).not.toBeNull();
      expect(result).toContain("月");
    });

    test("invalid char in minute field", () => {
      const result = validateCron("a 9 * * *");
      expect(result).not.toBeNull();
      expect(result).toContain("分");
    });

    test("invalid char in hour field", () => {
      const result = validateCron("0 x * * *");
      expect(result).not.toBeNull();
      expect(result).toContain("時");
    });

    test("invalid char in day field", () => {
      const result = validateCron("0 9 L * *");
      expect(result).not.toBeNull();
      expect(result).toContain("日");
    });

    test("invalid char in day-of-week field", () => {
      const result = validateCron("0 9 * * MON");
      expect(result).not.toBeNull();
      expect(result).toContain("曜日");
    });
  });
});
