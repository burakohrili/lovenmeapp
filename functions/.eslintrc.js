module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    ecmaVersion: 2018,
  },
  extends: [
    "eslint:recommended",
  ],
  rules: {
    "quotes": "off",
    "indent": "off",
    "no-trailing-spaces": "off",
    "padded-blocks": "off",
    "eol-last": "off",
  },
};