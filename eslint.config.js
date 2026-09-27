/*
 * ESLint flat config.
 *
 * Two source trees are linted:
 *   1. Apex sources under force-app/  (eslint-plugin-apex)
 *   2. The static study site under docs/assets/ (plain JS)
 */
module.exports = [
  {
    files: ['force-app/**/*.cls', 'force-app/**/*.trigger'],
    plugins: { apex: require('eslint-plugin-apex') },
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: 'script'
    },
    rules: {
      ...require('@salesforce/eslint-config-apex').rules,
      'no-unused-vars': 'off',
      'apex/no-unused-vars': ['error', { vars: 'all', args: 'none' }],
      'apex/avoid-using-system-debug-in-tests': 'off',
      curly: 'error',
      'no-console': 'error',
      semi: ['error', 'always'],
      'no-trailing-spaces': 'error',
      eqeqeq: ['error', 'smart'],
      'no-var': 'error',
      'prefer-const': 'error'
    }
  },
  {
    files: ['docs/assets/**/*.js', 'scripts/**/*.js', 'scripts/**/*.mjs'],
    languageOptions: {
      ecmaVersion: 2021,
      sourceType: 'script',
      globals: {
        window: 'readonly',
        document: 'readonly',
        localStorage: 'readonly',
        location: 'readonly',
        history: 'readonly',
        fetch: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        requestAnimationFrame: 'readonly',
        navigator: 'readonly',
        ACADEMY: 'readonly',
        EXERCISE_ANSWERS: 'readonly',
        GUIDE: 'readonly',
        process: 'readonly',
        console: 'readonly',
        globalThis: 'readonly'
      }
    },
    rules: {
      'no-unused-vars': 'warn',
      'no-undef': 'error',
      semi: ['error', 'always'],
      quotes: ['error', 'single', { avoidEscape: true }],
      'no-var': 'error',
      'prefer-const': 'error',
      eqeqeq: ['error', 'smart']
    }
  },
  {
    ignores: [
      '**/node_modules/**',
      '.sfdx/**',
      '.sf/**',
      'force-app/main/default/objects/*/listViews/**',
      'force-app/main/default/reports/**/*.report-meta.xml'
    ]
  }
];
