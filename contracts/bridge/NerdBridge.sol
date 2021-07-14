pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./TransferHelper.sol";
import "../utils/ReentrancyGuard.sol";

contract NerdBridge is Ownable {
    using SafeMath for uint256;
    
    address public validator;
    address public nerd;    
    // key: payback_id
    mapping (bytes32 => bool) public executedMap;
    mapping (uint256 => bool) public allowedChainIds;
    
    event Transit(address indexed from, uint256 indexed destChainId, uint amount);
    event Withdraw(bytes32 message, address indexed to, uint amount, uint256 chainId, uint256 index);
    
    constructor(address _validator, address _nerdContract) public {
        validator = _validator;
        nerd = _nerdContract;
        allowedChainIds[56] = true; //BSC
        allowedChainIds[321] = true; //KCS
    }

    modifier onlyAllowedChainId(uint256 _chainId) {
        require(allowedChainIds[_chainId], "NerdBridge: unsupported chain");
        _;
    } 
    function setAllowedChains(uint256[] memory _chains, bool _val) external onlyOwner {
        for(uint256 i = 0; i < _chains.length; i++) {
            allowedChainIds[_chains[i]] = _val;
        }
    }
    
    function changeValidator(address _newValidator) external onlyOwner {
        require(_newValidator != address(0), "NerdBridge::changeValidator:_newValidator must not be zero");
        validator = _newValidator;
    }
    
    function transitForAnyChain(uint _amount, uint256 _destChainId) external onlyAllowedChainId(_destChainId) {
        require(_amount > 0, "NerdBridge::transitForAnyChain INVALID_AMOUNT");
        TransferHelper.safeTransferFrom(nerd, msg.sender, address(this), _amount);
        emit Transit(msg.sender, _destChainId, _amount);
    }
    
    function withdrawFromAny(address _recipient, uint _chainId, uint _amount, uint256 _index, bytes32 _r, bytes32 _s, uint8 _v) external nonReentrant onlyAllowedChainId(_chainId) {
        bytes32 message = keccak256(abi.encodePacked(_chainId, _amount, _index, _recipient));
        require(executedMap[message] == false, "NerdBridge::withdrawFromAny ALREADY_EXECUTED");
        executedMap[message] = true;
        
        require(_amount > 0, "NerdBridge::withdrawFromAny NOTHING_TO_WITHDRAW");
        
        require(_verify(message, _r, _s, _v), "NerdBridge::withdrawFromAny INVALID_SIGNATURE");
        
        TransferHelper.safeTransfer(nerd, _recipient, _amount);
        
        emit Withdraw(message, _recipient, _amount, _chainId, _index);
    }
    
    function _verify(bytes32 _message, bytes32 _r, bytes32 _s, uint8 _v) public view returns (bool) {
        bytes32 hash = _toEthBytes32SignedMessageHash(_message);
        address signer = _recoverAddress(hash, _r, _s, _v);
        return signer == validator;
    }
    
    function _toEthBytes32SignedMessageHash (bytes32 _msg) pure public returns (bytes32 signHash)
    {
        signHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _msg));
    }
    
    function _recoverAddress(bytes32 _hash, bytes32 _r, bytes32 _s, uint8 _v) pure internal returns (address addr)
    {
        addr = ecrecover(_hash, _v, _r, _s);
    }
}