module.exports = api => {
  const disableStaticViewConfigsCodegen = api.caller(
    caller => caller?.platform === 'web' || caller?.name === 'babel-jest',
  );
  return {
    presets: [['module:@react-native/babel-preset', { disableStaticViewConfigsCodegen }]],
  };
};
