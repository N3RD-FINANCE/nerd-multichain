// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./BasicERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IFeeApprover.sol";
import "../interfaces/IBrainzVault.sol";
import "../interfaces/IBasicBrainz.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract BasicBrainz is Ownable, BasicERC20 {
    using SafeMath for uint256;
    using Address for address;

    address public override transferCheckerAddress;
    address public override feeDistributor;

    function setShouldTransferChecker(address _transferCheckerAddress)
        public
        onlyOwner
    {
        transferCheckerAddress = _transferCheckerAddress;
    }

    function setFeeDistributor(address _feeDistributor) public onlyOwner {
        feeDistributor = _feeDistributor;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(
            amount,
            "ERC20: transfer amount exceeds balance"
        );

        (
            uint256 transferToAmount,
            uint256 transferToFeeDistributorAmount
        ) = IFeeApprover(transferCheckerAddress).calculateAmountsAfterFee(
            sender,
            recipient,
            amount
        );

        require(
            transferToAmount.add(transferToFeeDistributorAmount) == amount,
            "Math broken, does gravity still work?"
        );

        _balances[recipient] = _balances[recipient].add(transferToAmount);
        emit Transfer(sender, recipient, transferToAmount);

        //transferToFeeDistributorAmount is total rewards fees received for genesis pool (this contract) and farming pool
        if (
            transferToFeeDistributorAmount > 0 && feeDistributor != address(0)
        ) {
            _balances[feeDistributor] = _balances[feeDistributor].add(
                transferToFeeDistributorAmount
            );
            emit Transfer(
                sender,
                feeDistributor,
                transferToFeeDistributorAmount
            );
            IBrainzVault(feeDistributor).updatePendingRewards();
        }
    }
}
