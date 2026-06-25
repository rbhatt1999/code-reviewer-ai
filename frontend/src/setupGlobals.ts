// This file runs as setupFiles (before test framework) to ensure Node 20
// TextEncoder/TextDecoder globals are available in the jsdom environment.
import { TextEncoder, TextDecoder } from 'util';

Object.assign(global, { TextEncoder, TextDecoder });
