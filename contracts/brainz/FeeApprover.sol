pragma solidity 0.6.12;
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IFeeApprover.sol";
import "../interfaces/IBrainzVault.sol";
import "../interfaces/IBasicBrainz.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FeeApprover is Ownable {
    using SafeMath for uint256;

    constructor() public {
        feePercentX100 = 0;
        paused = false;
    }

    uint8 public feePercentX100; // max 255 = 25.5% artificial clamp
    bool paused;
    mapping(address => bool) public noFeeList;

    function setPaused(bool _pause) public onlyOwner {
        paused = _pause;
    }

    function setFeeMultiplier(uint8 _feeMultiplier) public onlyOwner {
        feePercentX100 = _feeMultiplier;
    }

    //need to edit: brainz, vault, router, staking, distributor proxy, dev
    function editNoFeeList(address[] memory _addresses, bool noFee) public onlyOwner {
        for(uint256 i = 0; i < _addresses.length; i++) {
            _editNoFeeList(_addresses[i], noFee);
        }
    }

    function _editNoFeeList(address _address, bool noFee) internal {
        noFeeList[_address] = noFee;
    }

    function calculateAmountsAfterFee(
        address sender,
        address recipient, // unusued maybe use din future
        uint256 amount
    )
        public
        returns (
            uint256 transferToAmount,
            uint256 transferToFeeDistributorAmount
        )
    {
        require(paused == false, "FEE APPROVER: Transfers Paused");

        if (noFeeList[sender] || noFeeList[recipient]) {
            // Dont have a fee when vault is sending, or infinite loop
            transferToFeeDistributorAmount = 0;
            transferToAmount = amount;
        } else {
            transferToFeeDistributorAmount = amount.mul(feePercentX100).div(1000);
            transferToAmount = amount.sub(transferToFeeDistributorAmount);
        }
    }
}
