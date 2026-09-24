module.exports = {
  preset: '@react-native/jest-preset',
  moduleNameMapper: {
    '^@brightcove/web-sdk/ui/styles$': '<rootDir>/__mocks__/styleMock.js',
    '^@brightcove/web-sdk/.*/styles$': '<rootDir>/__mocks__/styleMock.js',
    '\\.(css|less|scss)$': '<rootDir>/__mocks__/styleMock.js',
  },
};
