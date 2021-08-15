pragma solidity 0.6.12;

interface IBridgeEvent {
    event Transit(
        address indexed from,
        uint256 indexed sourceChainId,
        uint256 indexed destChainId,
        uint256 amount,
        uint256 index
    );

    event Withdraw(
        bytes32 indexed transitId,
        address indexed to,
        uint256 amount,
        uint256 chainId,
        uint256 index,
        bytes32 message
    );
}