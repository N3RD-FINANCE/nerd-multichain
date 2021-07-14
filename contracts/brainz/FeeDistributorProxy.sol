pragma solidity 0.6.12;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IBrainzVault.sol";
import "../interfaces/INoFeeSimple.sol";
import "../interfaces/IBasicBrainz.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IUpdateReward {
    function updatePendingRewards() external;

    function transferDevFee() external;
}

contract FeeDistributorProxy is Ownable, IBrainzVault {
    using SafeMath for uint256;
    IUpdateReward public vault;
    IUpdateReward public stakingPool;
    IERC20 public brainz;
    uint256 public stakingPercentage;
    uint256 public rewardUpdatePeriod = 2 hours;
    uint256 public lastUpdate = 0;

    constructor() public {
        lastUpdate = block.timestamp.sub(rewardUpdatePeriod);
    }

    function setBrainz(address _brainz) external onlyOwner {
        brainz = IERC20(_brainz);
    }

    function setStaking(address _staking) external onlyOwner {
        stakingPool = IUpdateReward(_staking);
    }

    function setVault(address _vault) external onlyOwner {
        vault = IUpdateReward(_vault);
    }

    function setStakingPercentage(uint256 _staking) external onlyOwner {
        stakingPercentage = _staking;
    }

    function setRewardUpdatePeriod(uint256 _period) external onlyOwner {
        rewardUpdatePeriod = _period;
    }

    function updatePendingRewards() external override {
        stakingPool.transferDevFee();
        if (block.timestamp >= lastUpdate.add(rewardUpdatePeriod)) {
            doUpdatePendingRewards();
        }
    }

    function doUpdatePendingRewards() public {
        uint256 balance = brainz.balanceOf(address(this));
        uint256 stakingRewards = balance.mul(stakingPercentage).div(100);
        uint256 vaultRewards = balance.sub(stakingRewards);

        brainz.transfer(address(vault), vaultRewards);
        vault.updatePendingRewards();

        brainz.transfer(address(stakingPool), stakingRewards);
        stakingPool.updatePendingRewards();
        lastUpdate = block.timestamp;
    }

    function depositFor(
        address _depositFor,
        uint256 _pid,
        uint256 _amount
    ) external override {}

    function poolInfo(uint256 _pid)
        external
        override
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            bool,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (address(0), 0, 0, 0, false, 0, 0, 0, 0);
    }
}
