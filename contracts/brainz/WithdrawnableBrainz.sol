pragma solidity 0.6.12;
pragma solidity 0.6.12;
import "./BasicBrainz.sol";
import "../utils/ReentrancyGuard.sol";

contract WithdrawnableBrainz is BasicBrainz, ReentrancyGuard {
    address public validator;

    // key: transit_id
    mapping(bytes32 => bool) public executedMap;
    uint256 public payBackIndex = 0;

    event Payback(
        address indexed from,
        uint256 indexed chainId,
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

    constructor(address _validator) internal {
        validator = _validator;
    }

    function changeValidator(address _wallet) external onlyOwner {
        require(
            _wallet != address(0),
            "WithdrawnableBrainz::changeValidator validator cannot be null"
        );
        validator = _wallet;
    }

    //burn brainz to receive nerd
    function paybackTransit(uint256 _amount) external nonReentrant {
        require(
            _amount > 0,
            "WithdrawnableBrainz::paybackTransit INVALID_AMOUNT"
        );
        _burn(msg.sender, _amount);
        emit Payback(msg.sender, chainId, _amount, payBackIndex);
        payBackIndex++;
    }

    function withdrawTransitToken(
        bytes32 _transitId,
        address _recipient,
        uint256 _amount,
        uint256 _index,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external nonReentrant {
        bytes32 message = keccak256(
            abi.encodePacked(
                _transitId,
                _recipient,
                _amount,
                chainId,
                _index
            )
        );
        
        require(_amount > 0, "NOTHING_TO_WITHDRAW");
        require(!executedMap[message], "ALREADY_EXECUTED");
        require(_verify(message, _r, _s, _v), "INVALID_SIGNATURE");

        executedMap[message] = true;

        _mint(_recipient, _amount.mul(1e9));   //pegged 1:1e9

        emit Withdraw(_transitId, _recipient, _amount, chainId, _index, message);
    }

    function _verify(
        bytes32 _message,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public view returns (bool) {
        bytes32 hash = _toEthBytes32SignedMessageHash(_message);
        address signer = _recoverAddress(hash, _r, _s, _v);
        return signer == validator;
    }

    function _toEthBytes32SignedMessageHash(bytes32 _msg)
        public
        pure
        returns (bytes32 signHash)
    {
        signHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", _msg)
        );
    }

    function _recoverAddress(
        bytes32 _hash,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) internal pure returns (address addr) {
        addr = ecrecover(_hash, _v, _r, _s);
    }
}
