export interface ParsedArgs {
  positionals: string[];
  flags: Set<string>;
  options: Map<string, string>;
}

const BOOLEAN_FLAGS = new Set([
  "json", "wait", "yes", "help", "output",
  "catch-up", "no-catch-up", "notify", "no-notify", "disabled",
]);

const SHORT_FLAGS: Record<string, string> = {
  h: "help",
  y: "yes",
};

const SHORT_OPTIONS: Record<string, string> = {
  n: "limit",
};

export function parseArgs(argv: string[]): ParsedArgs {
  const positionals: string[] = [];
  const flags = new Set<string>();
  const options = new Map<string, string>();

  let i = 0;
  while (i < argv.length) {
    const arg = argv[i]!;
    if (arg === "--") {
      positionals.push(...argv.slice(i + 1));
      break;
    }
    if (arg.startsWith("--")) {
      const key = arg.slice(2);
      if (BOOLEAN_FLAGS.has(key)) {
        flags.add(key);
      } else {
        const next = argv[i + 1];
        if (next !== undefined) {
          options.set(key, next);
          i++;
        }
      }
      i++;
      continue;
    }
    if (arg.startsWith("-") && arg.length === 2) {
      const ch = arg[1]!;
      const longFlag = SHORT_FLAGS[ch];
      if (longFlag) {
        flags.add(longFlag);
      } else {
        const optName = SHORT_OPTIONS[ch] ?? ch;
        const next = argv[i + 1];
        if (next !== undefined) {
          options.set(optName, next);
          i++;
        }
      }
      i++;
      continue;
    }
    positionals.push(arg);
    i++;
  }

  return { positionals, flags, options };
}
