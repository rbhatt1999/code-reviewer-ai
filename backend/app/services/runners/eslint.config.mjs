// Bundled ESLint v9 flat config for CodeReviewer.AI.
// Used via `eslint --config <path-to-this-file> --no-config-lookup`.
// No npm deps: only built-in ESLint core rules are enabled.
// TypeScript files are linted with JS-only rules (TS plugin is out of scope for Inc 2).
export default [
  {
    files: ['**/*.js', '**/*.mjs', '**/*.cjs', '**/*.ts', '**/*.tsx'],
    rules: {
      'no-unused-vars': 'warn',
      'no-undef': 'error',
      'eqeqeq': 'error',
      'no-console': 'warn',
      'no-var': 'warn',
      'prefer-const': 'warn',
      'no-empty': 'warn',
      'no-duplicate-case': 'error',
      'no-unreachable': 'warn',
    },
  },
];
