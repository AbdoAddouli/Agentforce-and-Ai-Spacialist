/**
 * Jest config.
 *
 * Salesforce Apex tests run on the platform via `sf apex run test`, not in Jest.
 * Jest is used here for the STATIC study-site checks in scripts/ so that a broken
 * curriculum/answers pairing fails CI instead of failing silently in the browser.
 */
module.exports = {
  testEnvironment: 'node',
  testMatch: ['<rootDir>/scripts/**/*.test.mjs'],
  verbose: true
};
