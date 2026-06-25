// Replace import.meta.env.VITE_* with process.env.VITE_* so Jest/babel can handle it.
// Vite handles import.meta.env natively; Jest uses this transform instead.
const importMetaEnvPlugin = ({ types: t }) => ({
  visitor: {
    MetaProperty(path) {
      if (
        path.node.meta.name === 'import' &&
        path.node.property.name === 'meta'
      ) {
        // Replace import.meta with a safe object for Jest
        path.replaceWith(
          t.objectExpression([
            t.objectProperty(
              t.identifier('env'),
              t.objectExpression([
                t.objectProperty(
                  t.identifier('VITE_API_BASE_URL'),
                  t.stringLiteral(
                    process.env.VITE_API_BASE_URL || 'http://localhost:3000/api/v1'
                  )
                ),
                t.objectProperty(
                  t.identifier('VITE_WS_BASE_URL'),
                  t.stringLiteral(
                    process.env.VITE_WS_BASE_URL || 'ws://localhost:3000/cable'
                  )
                ),
              ])
            ),
          ])
        );
      }
    },
  },
});

module.exports = {
  presets: [
    ['@babel/preset-env', { targets: { node: 'current' } }],
    ['@babel/preset-react', { runtime: 'automatic' }],
    '@babel/preset-typescript',
  ],
  plugins: [importMetaEnvPlugin],
};
