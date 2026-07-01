module.exports = [
    {
        files: ['**/*.js'],
        ignores: ['eslint.config.js'],
        languageOptions: {
            ecmaVersion: 'latest',
            sourceType: 'script',
            globals: {
                window: 'readonly',
                document: 'readonly',
                navigator: 'readonly',
                performance: 'readonly',
                AbortSignal: 'readonly',
                WebGL2RenderingContext: 'readonly'
            }
        },
        rules: {
            'no-unused-vars': 'error',
            'no-var': 'error',
            'prefer-const': 'error',
            eqeqeq: ['error', 'always'],
            'no-with': 'error',
            'no-implied-eval': 'error',
            'no-eval': 'error',
            strict: ['error', 'global'],
            'no-console': 'warn',
            semi: ['error', 'always'],
            quotes: ['warn', 'single', { avoidEscape: true }]
        }
    }
];
