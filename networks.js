require('dotenv').config();

const HDWalletProvider = require('truffle-hdwallet-provider');
const infuraProjectId = process.env.INFURA_PROJECT_ID;

module.exports = {
  networks: {
    development: {
      protocol: 'http',
      host: 'localhost',
      port: 8545,
      gas: 5000000,
      gasPrice: 5e9,
      networkId: '*',
    },
    ropsten: {
      provider: () => new HDWalletProvider(process.env.DEV_MNEMONIC, "https://ropsten.infura.io/v3/" + infuraProjectId),
      networkId: 3
    },
    mainnet: {
      provider: () => new HDWalletProvider(process.env.DEV_MNEMONIC, "https://mainnet.infura.io/v3/" + infuraProjectId),
      networkId: 1
    },
  },
};