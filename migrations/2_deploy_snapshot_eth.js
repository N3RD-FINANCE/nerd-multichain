/* global artifacts */
const Snapshot = artifacts.require('Snapshot')
const { time } = require('@openzeppelin/test-helpers');
const BN = require('bignumber.js');
BN.config({ DECIMAL_PLACES: 0 })
BN.config({ ROUNDING_MODE: BN.ROUND_DOWN })

module.exports = function (deployer, network, accounts) {
  return deployer.then(async () => {
    const snapshot = await deployer.deploy(Snapshot)
    console.log('snapshot\'s address ', snapshot.address)
    
    // const whitelist = await deployer.deploy(WhiteList)
    // console.log('WhiteList\'s address ', whitelist.address)

    // const linearAllocation = await deployer.deploy(LinearAllocation)
    // await linearAllocation.setWhiteListContract(whitelist.address)
    // console.log('linearAllocation\'s address ', linearAllocation.address)

    //adding some example token sale
    //adding completed
    // const token1 = await deployer.deploy(SampleERC20, accounts[0])
    // await launchpad.setAllowedToken(token1.address, true)
    // let currentTime = await time.latest()
    // await launchpad.createTokenSaleWithAllocation(
    //   token1.address,
    //   accounts[0],
    //   '1000000000000000000000000',
    //   new BN(currentTime).plus(1).toFixed(0),
    //   new BN(currentTime).plus(2).toFixed(0),
    //   '2000000000',
    //   '100000',
    //   linearAllocation.address
    // )

    // //adding on-going
    // const token2 = await deployer.deploy(SampleERC20, accounts[0])
    // await launchpad.setAllowedToken(token2.address, true)
    // currentTime = await time.latest()
    // await launchpad.createTokenSaleWithAllocation(
    //   token2.address,
    //   accounts[0],
    //   '1000000000000000000000000',
    //   new BN(currentTime).plus(1).toFixed(0),
    //   new BN(currentTime).plus(1000000).toFixed(0),
    //   '2000000000',
    //   '100000',
    //   linearAllocation.address
    // )

    // //add upcoming
    // const token3 = await deployer.deploy(SampleERC20, accounts[0])
    // await launchpad.setAllowedToken(token3.address, true)
    // currentTime = await time.latest()
    // await launchpad.createTokenSaleWithAllocation(
    //   token3.address,
    //   accounts[0],
    //   '1000000000000000000000000',
    //   new BN(currentTime).plus(1000).toFixed(0),
    //   new BN(currentTime).plus(10000000).toFixed(0),
    //   '2000000000',
    //   '100000',
    //   linearAllocation.address
    // )
  })
}
