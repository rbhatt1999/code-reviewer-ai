/**
 * Custom Jest environment that extends jsdom with Node 20's built-in Fetch API
 * globals. MSW v2 (msw/node) requires Request/Response/Headers/fetch to be
 * defined in the global scope at module-evaluation time.
 */
const { TestEnvironment } = require('jest-environment-jsdom');

class FetchJsdomEnvironment extends TestEnvironment {
  async setup() {
    await super.setup();

    // Copy Node 20 built-in Fetch API and Streams API into the jsdom global scope.
    // MSW v2 interceptors need these at module-evaluation time.
    const nodeGlobals = {
      Request: globalThis.Request,
      Response: globalThis.Response,
      Headers: globalThis.Headers,
      fetch: globalThis.fetch,
      FormData: globalThis.FormData,
      ReadableStream: globalThis.ReadableStream,
      WritableStream: globalThis.WritableStream,
      TransformStream: globalThis.TransformStream,
      CompressionStream: globalThis.CompressionStream,
      DecompressionStream: globalThis.DecompressionStream,
    };
    for (const [key, value] of Object.entries(nodeGlobals)) {
      if (value !== undefined && typeof this.global[key] === 'undefined') {
        this.global[key] = value;
      }
    }

    // BroadcastChannel polyfill
    if (typeof this.global.BroadcastChannel === 'undefined') {
      this.global.BroadcastChannel = class BroadcastChannel {
        constructor(name) { this.name = name; }
        postMessage() {}
        close() {}
        addEventListener() {}
        removeEventListener() {}
        dispatchEvent() { return true; }
      };
    }
  }
}

module.exports = FetchJsdomEnvironment;
