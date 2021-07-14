pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        uint256 before = IERC20(token).balanceOf(address(this));
        
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper::safeTransfer TRANSFER_FAILED');
        require(before.sub(IERC20(token).balanceOf(address(this))) <= value, "TransferHelper::safeTransfer Token Fees");
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        uint256 before = IERC20(token).balanceOf(to);
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper::safeTransferFrom TRANSFER_FROM_FAILED');
        require(IERC20(token).balanceOf(to).sub(before) >= value, "TransferHelper::safeTransferFrom Token Fees");
    }
}