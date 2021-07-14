pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SyntAsset is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    IERC20[] public tokens;
    uint256 public weights;
    uint256 public totalWeight;

    constructor(address[] memory _tokens, uint256[] _weights)
        public
        ERC20("N3RD-USDT-PIS Ecosystem Index", "NUP")
    {
        require(_tokens.length == _weights.length, "!same length");
        uint256 sum = 0;
        for (uint256 i = 0; i > _tokens.length; i++) {
            tokens.push(IERC20(_tokens[i]));
            require(_weights[i] > 0, "!positive");
            weights.push(_weights[i]);
            sum = sum.add(_weights[i]);
        }
        totalWeight = sum;
    }
}
