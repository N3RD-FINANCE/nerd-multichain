/* global artifacts */
require('dotenv').config()
const Brainz = artifacts.require('Brainz')
const FeeApprover = artifacts.require('FeeApprover')
const { time } = require('@openzeppelin/test-helpers');
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })
const fs  = require('fs');

let approver = process.env.APPROVER_ADDRESS
module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {
    const brainz = await deployer.deploy(Brainz, approver)
    console.log('brainz\'s address ', brainz.address)

    var storage = {};
    storage.address = brainz.address
    fs.writeFileSync(`deployments/Brainz.${deployer.network_id}.address.json`,JSON.stringify(storage), 'utf-8');
  })
}
