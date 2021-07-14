require("dotenv").config();
const HDWalletProvider = require('@truffle/hdwallet-provider')
const utils = require('web3-utils')

module.exports = {
  networks: {
    development: {
      protocol: "http",
      host: "localhost",
      port: 8545,
      gas: 6500000,
      gasPrice: 5e9,
      network_id: "*",
    },
    kovan: {
      provider: () => new HDWalletProvider(process.env.PRIVATE_KEY, `https://kovan.infura.io/v3/${process.env.INFURA_APIKEY}`),
      network_id: 42,
      gas: 4600000,
      gasPrice: utils.toWei('1', 'gwei'),
    },
    mainnet: {
      provider: () => new HDWalletProvider(process.env.PRIVATE_KEY, `https://mainnet.infura.io/v3/${process.env.INFURA_APIKEY}`),
      network_id: 1,
      gas: 999999,
      gasPrice: 130000000000,
    },
    bsc: {
      provider: () => new HDWalletProvider(process.env.PRIVATE_KEY, 'https://bsc-dataseed.binance.org/'),
      network_id: 56,
      gas: 6000000,
      gasPrice: utils.toWei('10', 'gwei'),
      // confirmations: 0,
      // timeoutBlocks: 200,
      skipDryRun: true
    },
    bsctestnet: {
      provider: () => new HDWalletProvider(process.env.PRIVATE_KEY, 'https://data-seed-prebsc-2-s2.binance.org:8545/'),
      network_id: 97,
      gas: 6000000,
      gasPrice: utils.toWei('30', 'gwei'),
      // confirmations: 0,
      // timeoutBlocks: 200,
      skipDryRun: true
    },
  },
  compilers: {
    solc: {
      version: "0.6.12",
      docker: false,
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        },
        evmVersion: "istanbul",
      },
    },
  }
}
