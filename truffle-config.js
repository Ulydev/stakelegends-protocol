require('dotenv').config();

const HDWalletProvider = require('truffle-hdwallet-provider');
const infuraProjectId = process.env.INFURA_PROJECT_ID;

module.exports = {
    plugins: [
        'truffle-plugin-verify'
    ],
    api_keys: {
        etherscan: process.env.INFURA_PROJECT_ID
    },
    networks: {
        ropsten: {
            provider: () => new HDWalletProvider(process.env.DEV_MNEMONIC, "https://ropsten.infura.io/v3/" + infuraProjectId),
            network_id: "3",       // Ropsten's id
        },
    },
}