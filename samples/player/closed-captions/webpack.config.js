const path = require('path');
const webpack = require('webpack');
const HtmlWebpackPlugin = require('html-webpack-plugin');
const ForkTsCheckerWebpackPlugin = require('fork-ts-checker-webpack-plugin');

const appDirectory = path.resolve(__dirname);

module.exports = (_env, argv) => {
  const isProduction = argv.mode === 'production';

  return {
    entry: path.resolve(appDirectory, 'index.web.js'),
    output: {
      path: path.resolve(appDirectory, 'dist'),
      filename: isProduction ? '[name].[contenthash:8].js' : 'bundle.js',
      clean: true,
    },
    resolve: {
      extensions: [
        '.web.tsx',
        '.web.ts',
        '.web.jsx',
        '.web.js',
        '.tsx',
        '.ts',
        '.jsx',
        '.js',
        '.json',
      ],
      alias: {
        'react-native$': 'react-native-web',
        '@brightcove/web-sdk/ui$': path.resolve(
          appDirectory,
          'node_modules/@brightcove/web-sdk/dist/ui/index.es.js',
        ),
        '@brightcove/web-sdk/integrations/thumbnails$': path.resolve(
          appDirectory,
          'node_modules/@brightcove/web-sdk/dist/integrations/thumbnails/index.es.js',
        ),
        '@brightcove/web-sdk/integrations/imaClientSide$': path.resolve(
          appDirectory,
          'node_modules/@brightcove/web-sdk/dist/integrations/imaClientSide/index.es.js',
        ),
        '@brightcove/web-sdk/integrations/ssai$': path.resolve(
          appDirectory,
          'node_modules/@brightcove/web-sdk/dist/integrations/ssai/index.es.js',
        ),
        '@brightcove/web-sdk/integrations/imaDai$': path.resolve(
          appDirectory,
          'node_modules/@brightcove/web-sdk/dist/integrations/imaDai/index.es.js',
        ),
      },
    },
    module: {
      rules: [
        {
          test: /\.[jt]sx?$/,
          include: [
            path.resolve(appDirectory, 'index.web.js'),
            path.resolve(appDirectory, 'App.tsx'),
            path.resolve(appDirectory, 'src'),
            path.resolve(appDirectory, 'modules/brightcove-player'),
          ],
          use: {
            loader: 'babel-loader',
            options: {
              presets: [
                [
                  'module:@react-native/babel-preset',
                  { disableStaticViewConfigsCodegen: true },
                ],
              ],
            },
          },
        },
        {
          test: /\.css$/,
          use: ['style-loader', 'css-loader'],
        },
      ],
    },
    plugins: [
      // Metro defines __DEV__ on native builds; webpack does not, so any
      // `if (__DEV__)` in sample code (playerConfig's placeholder guard) throws
      // "ReferenceError: __DEV__ is not defined" and the page renders blank.
      // Define it from the build mode, matching Metro's production semantics.
      new webpack.DefinePlugin({
        __DEV__: JSON.stringify(!isProduction),
      }),
      new HtmlWebpackPlugin({
        template: path.resolve(appDirectory, 'web/index.html'),
      }),
      // Validates App.tsx (and this sample's web bridge copy) against the
      // browser-only prop surface: moduleSuffixes in tsconfig.web.json makes
      // tsc resolve `@brightcove/react-native-player` to index.web.tsx instead
      // of the native index.tsx, so a prop this copy's web bridge Omits (a
      // feature the Web SDK cannot do) is a build failure here, not a
      // silently-ignored prop at runtime. babel-loader above only strips
      // TypeScript syntax; this plugin is the only thing in this config that
      // actually type-checks it.
      new ForkTsCheckerWebpackPlugin({
        typescript: { configFile: path.resolve(appDirectory, 'tsconfig.web.json') },
      }),
    ],
    devServer: {
      port: 3000,
      hot: true,
      historyApiFallback: true,
      static: {
        directory: path.resolve(appDirectory, 'web'),
      },
    },
  };
};
