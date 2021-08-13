/* global artifacts */
const Brainz = artifacts.require('Brainz')
const FeeApprover = artifacts.require('FeeApprover')
const { time } = require('@openzeppelin/test-helpers');
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })
const fs  = require('fs');

module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {
    const brainz = await Brainz.deployed()
    const feeApprover = await deployer.deploy(FeeApprover)
    console.log('feeApprover\'s address ', feeApprover.address)
    await brainz.setShouldTransferChecker(feeApprover.address)

    var storage = {};
    storage.address = feeApprover.address
    fs.writeFileSync(`deployments/FeeApprover.${deployer.network_id}.address.json`,JSON.stringify(storage), 'utf-8');
  })
}
