import { defineConfig, globalIgnores } from 'eslint/config';
import nextVitals from 'eslint-config-next/core-web-vitals';
import nextTypeScript from 'eslint-config-next/typescript';

export default defineConfig([
  ...nextVitals,
  ...nextTypeScript,
  {
    // The React Compiler rules are stricter than this established non-compiled
    // client code. Keep the standard Hooks correctness rules enabled while a
    // dedicated compiler migration is evaluated separately.
    rules: {
      'react-hooks/preserve-manual-memoization': 'off',
      'react-hooks/purity': 'off',
      'react-hooks/set-state-in-effect': 'off',
      'react-hooks/static-components': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_' }],
    },
  },
  globalIgnores([
    '.next/**',
    '.next-dev/**',
    'out/**',
    'build/**',
    'next-env.d.ts',
  ]),
]);
