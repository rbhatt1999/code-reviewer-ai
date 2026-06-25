// MSW v2 server for Playwright / E2E tests (Increment 3+).
// Not imported by Jest unit tests — those use jest.mock('@api/...') directly
// because MSW v2's transitive ESM-only dependencies (rettime, until-async)
// cannot run in jest-environment-jsdom without a complex transform pipeline.
import { setupServer } from 'msw/node';
import { handlers } from './handlers';

export const server = setupServer(...handlers);
