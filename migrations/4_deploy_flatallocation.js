/* global artifacts */
const LaunchPad = artifacts.require('LaunchPad')
const FlatAllocation = artifacts.require('FlatAllocation')
const { time } = require('@openzeppelin/test-helpers');
const SampleERC20 = artifacts.require('SampleERC20')
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })
const config = require('../scripts/config')

module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {    
    const flatAllocation = await deployer.deploy(FlatAllocation)
	console.log('flatAllocation\'s address ', flatAllocation.address)
  });
}