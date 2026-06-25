import type { Config } from 'jest';

const config: Config = {
  testEnvironment: '<rootDir>/jest.environment.cjs',
  roots: ['<rootDir>/src'],
  testMatch: ['**/?(*.)+(spec|test).ts?(x)'],
  transform: {
    '^.+\\.(ts|tsx|js|jsx)$': ['babel-jest', { configFile: './babel.config.cjs' }],
  },
  moduleNameMapper: {
    '^@/(.*)$': '<rootDir>/src/$1',
    '^@api/(.*)$': '<rootDir>/src/api/$1',
    '^@features/(.*)$': '<rootDir>/src/features/$1',
    '^@components/(.*)$': '<rootDir>/src/components/$1',
    '^@hooks/(.*)$': '<rootDir>/src/hooks/$1',
    '^@stores/(.*)$': '<rootDir>/src/stores/$1',
    '^@types/(.*)$': '<rootDir>/src/types/$1',
    '^@cable/(.*)$': '<rootDir>/src/cable/$1',
    '\\.(css|scss|sass)$': 'identity-obj-proxy',
    '\\.(png|jpe?g|gif|svg|webp)$': '<rootDir>/src/__mocks__/fileMock.ts',
  },
  setupFiles: ['<rootDir>/src/setupGlobals.ts'],
  setupFilesAfterEnv: ['<rootDir>/src/setupTests.ts'],
  collectCoverageFrom: [
    'src/**/*.{ts,tsx}',
    '!src/**/*.d.ts',
    '!src/main.tsx',
    '!src/__mocks__/**',
  ],
  coverageThreshold: {
    global: { branches: 70, functions: 80, lines: 80, statements: 80 },
  },
  clearMocks: true,
  restoreMocks: true,
  testTimeout: 10000,
};

export default config;
