/* global artifacts */
const LaunchPad = artifacts.require('LaunchPad')
const LinearAllocation = artifacts.require('LinearAllocation')
const { time } = require('@openzeppelin/test-helpers');
const SampleERC20 = artifacts.require('SampleERC20')
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })

module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {
    const token = await deployer.deploy(SampleERC20, "Launchpad Test 3", "LPT3", accounts[0])
    console.log('token\'s address ', token.address)
  })
}