/* global artifacts */
require('dotenv').config()
const NerdBridge = artifacts.require('NerdBridge')
const SampleERC20 = artifacts.require('SampleERC20')
const { time } = require('@openzeppelin/test-helpers');
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })
let approver = process.env.APPROVER_ADDRESS
const fs  = require('fs');

module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {
    let chainId = deployer.network_id
    let nerdContractAddress = "0x32C868F6318D6334B2250F323D914Bc2239E4EeE";
    var storage = {};
    if (chainId != 1) {
      //deploy mock
      const sample = await deployer.deploy(SampleERC20, "N3RD-SAMPLE", "N3RDS", accounts[0])
      console.log('sample nerd\'s address ', sample.address)
      nerdContractAddress = sample.address
    }
    const nerdBridge = await deployer.deploy(NerdBridge, approver, nerdContractAddress)
    console.log('nerdBridge\'s address ', nerdBridge.address)
    if (chainId != 1) {
      await nerdBridge.setAllowedChains([97, 42], true)
    } else {
      await nerdBridge.setAllowedChains([56, 1], true)
    }
    storage.address = nerdBridge.address
    storage.nerdaddress = nerdContractAddress
    fs.writeFileSync(`deployments/NerdBridge.${chainId}.address.json`,JSON.stringify(storage), 'utf-8');
  })
}
