pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBasicBrainz.sol";
import "../interfaces/IFeeApprover.sol";
import "../interfaces/INoFeeSimple.sol";

// Have fun reading it. Hopefully it's bug-free. God bless.

contract TimeLockBrainzPool {
    using SafeMath for uint256;
    using Address for address;

    uint256 public constant BRAINZ_LOCKED_PERIOD_DAYS = 14; //10 weeks,
    uint256 public constant BRAINZ_RELEASE_TRUNK = 1 days; //releasable every week,

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many  tokens the user currently has.
        uint256 referenceAmount; //this amount is used for computing releasable LP amount
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardLocked;
        uint256 releaseTime;
        //
        // We do some fancy math here. Basically, any point in time, the amount of Brainz
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accBrainzPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws  tokens to a pool. Here's what happens:
        //   1. The pool's `accBrainzPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.

        uint256 depositTime; //See explanation below.
        //this is a dynamic value. It changes every time user deposit to the pool
        //1. initial deposit X => deposit time is block time
        //2. deposit more at time deposit2 without amount Y =>
        //  => compute current releasable amount R
        //  => compute diffTime = R*lockedPeriod/(X + Y) => this is the duration users can unlock R with new deposit amount
        //  => updated depositTime = (blocktime - diffTime/2)
    }

    // Info of each pool.
    struct PoolInfo {
        uint256 accBrainzPerShare; // Accumulated Brainz per share, times 1e18. See below.
        uint256 lockedPeriod; // liquidity locked period
        bool emergencyWithdrawable;
        uint256 rewardsInThisEpoch;
        uint256 cumulativeRewardsSinceStart;
        uint256 startBlock;
        // For easy graphing historical epoch rewards
        mapping(uint256 => uint256) epochRewards;
        uint256 epochCalculationStartBlock;
        uint256 totalDeposit;
    }

    // Info of each pool.
    PoolInfo public poolInfo;
    // Info of each user that stakes  tokens.
    mapping(address => UserInfo) public userInfo;

    // The Brainz TOKEN!
    IBasicBrainz public brainz;

    function getBrainzReleaseStart(address _user) public view returns (uint256) {
        return userInfo[_user].depositTime;
    }

    function getRemainingBrainz(address _user) public view returns (uint256) {
        return userInfo[_user].amount;
    }

    function getReferenceAmount(address _user) public view returns (uint256) {
        return userInfo[_user].referenceAmount;
    }

    function computeReleasableBrainz(address _addr)
        public
        view
        returns (uint256)
    {
        uint256 brainzReleaseStart = getBrainzReleaseStart(_addr);
        if (block.timestamp < brainzReleaseStart) {
            return 0;
        }

        uint256 amountBrainz = getReferenceAmount(_addr);
        if (amountBrainz == 0) return 0;

        uint256 totalReleasableTilNow = 0;

        if (block.timestamp > brainzReleaseStart.add(poolInfo.lockedPeriod)) {
            totalReleasableTilNow = amountBrainz;
        } else {
            uint256 daysTilNow = daysSinceBrainzReleaseTilNow(_addr);

            totalReleasableTilNow = daysTilNow
                .mul(BRAINZ_RELEASE_TRUNK)
                .mul(amountBrainz)
                .div(poolInfo.lockedPeriod);
        }
        if (totalReleasableTilNow > amountBrainz) {
            totalReleasableTilNow = amountBrainz;
        }
        uint256 alreadyReleased = amountBrainz.sub(getRemainingBrainz(_addr));
        if (totalReleasableTilNow > alreadyReleased) {
            return totalReleasableTilNow.sub(alreadyReleased);
        }
        return 0;
    }

    function daysSinceBrainzReleaseTilNow(address _addr)
        public
        view
        returns (uint256)
    {
        uint256 brainzReleaseStart = getBrainzReleaseStart(_addr);
        if (brainzReleaseStart == 0 || block.timestamp < brainzReleaseStart)
            return 0;
        uint256 timeTillNow = block.timestamp.sub(brainzReleaseStart);
        uint256 daysTilNow = timeTillNow.div(BRAINZ_RELEASE_TRUNK);
        daysTilNow = daysTilNow.add(1);
        return daysTilNow;
    }
}

contract StakingPool is Ownable, TimeLockBrainzPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Dev address.
    address public devaddr;
    address public tentativeDevAddress;

    //// pending rewards awaiting anyone to massUpdate
    uint256 public pendingRewards;

    uint256 public epoch;

    uint256 public constant REWARD_LOCKED_PERIOD = 28 days;
    uint256 public constant REWARD_RELEASE_PERCENTAGE = 50;
    uint256 public contractStartBlock;

    // Sets the dev fee for this contract
    // defaults at 7.24%
    // Note contract owner is meant to be a governance contract allowing Brainz governance consensus
    uint16 DEV_FEE;

    uint256 public pending_DEV_rewards;
    uint256 public BrainzBalance;
    uint256 public pendingDeposit;

    // Returns fees generated since start of this contract
    function averageFeesPerBlockSinceStart()
        external
        view
        returns (uint256 averagePerBlock)
    {
        averagePerBlock = poolInfo
            .cumulativeRewardsSinceStart
            .add(poolInfo.rewardsInThisEpoch)
            .add(pendingBrainzForPool())
            .div(block.number.sub(poolInfo.startBlock));
    }

    // Returns averge fees in this epoch
    function averageFeesPerBlockEpoch()
        external
        view
        returns (uint256 averagePerBlock)
    {
        averagePerBlock = poolInfo
            .rewardsInThisEpoch
            .add(pendingBrainzForPool())
            .div(block.number.sub(poolInfo.epochCalculationStartBlock));
    }

    function getEpochReward(uint256 _epoch) public view returns (uint256) {
        return poolInfo.epochRewards[_epoch];
    }

    function brainzDeposit() public view returns (uint256) {
        return poolInfo.totalDeposit.add(pendingDeposit);
    }

    //Starts a new calculation epoch
    // Because averge since start will not be accurate
    function startNewEpoch() public {
        require(
            poolInfo.epochCalculationStartBlock + 50000 < block.number,
            "New epoch not ready yet"
        ); // About a week
        poolInfo.epochRewards[epoch] = poolInfo.rewardsInThisEpoch;
        poolInfo.cumulativeRewardsSinceStart = poolInfo
            .cumulativeRewardsSinceStart
            .add(poolInfo.rewardsInThisEpoch);
        poolInfo.rewardsInThisEpoch = 0;
        poolInfo.epochCalculationStartBlock = block.number;
        ++epoch;
    }

    event Deposit(address indexed user, uint256 amount);
    event Restake(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(address _brainz, address _dev) public {
        brainz = IBasicBrainz(_brainz);

        poolInfo.lockedPeriod = BRAINZ_LOCKED_PERIOD_DAYS.mul(BRAINZ_RELEASE_TRUNK);
        DEV_FEE = 724;
        devaddr = _dev;
        tentativeDevAddress = address(0);
        contractStartBlock = block.number;

        poolInfo.emergencyWithdrawable = false;
        poolInfo.accBrainzPerShare = 0;
        poolInfo.rewardsInThisEpoch = 0;
        poolInfo.cumulativeRewardsSinceStart = 0;
        poolInfo.startBlock = block.number;
        poolInfo.epochCalculationStartBlock = block.number;
        poolInfo.totalDeposit = 0;
    }

    function isMultipleOfWeek(uint256 _period) public pure returns (bool) {
        uint256 numWeeks = _period.div(BRAINZ_RELEASE_TRUNK);
        return (_period == numWeeks.mul(BRAINZ_RELEASE_TRUNK));
    }

    function getDepositTime(address _addr) public view returns (uint256) {
        return userInfo[_addr].depositTime;
    }

    function setEmergencyWithdrawable(bool _withdrawable) public onlyOwner {
        poolInfo.emergencyWithdrawable = _withdrawable;
    }

    function setDevFee(uint16 _DEV_FEE) public onlyOwner {
        require(_DEV_FEE <= 1000, "Dev fee clamped at 10%");
        DEV_FEE = _DEV_FEE;
    }

    function pendingBrainzForPool() public view returns (uint256) {
        uint256 tokenSupply = poolInfo.totalDeposit;

        if (tokenSupply == 0) return 0;

        uint256 brainzRewardWhole = pendingRewards;
        uint256 brainzRewardFee = brainzRewardWhole.mul(DEV_FEE).div(10000);
        return brainzRewardWhole.sub(brainzRewardFee);
    }

    function computeDepositAmount(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal returns (uint256) {
        (uint256 _receiveAmount, ) = IFeeApprover(brainz.transferCheckerAddress())
            .calculateAmountsAfterFee(_sender, _recipient, _amount);
        return _receiveAmount;
    }

    // View function to see pending Brainz on frontend.
    function pendingBrainz(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 accBrainzPerShare = poolInfo.accBrainzPerShare;
        uint256 amount = user.amount;

        uint256 tokenSupply = poolInfo.totalDeposit;

        if (tokenSupply == 0) return 0;

        uint256 brainzRewardFee = pendingRewards.mul(DEV_FEE).div(10000);
        uint256 brainzRewardToDistribute = pendingRewards.sub(brainzRewardFee);
        uint256 inc = brainzRewardToDistribute.mul(1e18).div(tokenSupply);
        accBrainzPerShare = accBrainzPerShare.add(inc);

        return amount.mul(accBrainzPerShare).div(1e18).sub(user.rewardDebt);
    }

    function getLockedReward(address _user) public view returns (uint256) {
        return userInfo[_user].rewardLocked;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 allRewards = updatePool();
        pendingRewards = pendingRewards.sub(allRewards);
    }

    // ----
    // Function that adds pending rewards, called by the Brainz token.
    // ----
    function updatePendingRewards() public {
        uint256 newRewards = brainz.balanceOf(address(this)).sub(BrainzBalance).sub(
            brainzDeposit()
        );

        if (newRewards > 0) {
            BrainzBalance = brainz.balanceOf(address(this)).sub(brainzDeposit()); // If there is no change the balance didn't change
            pendingRewards = pendingRewards.add(newRewards);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() internal returns (uint256 brainzRewardWhole) {
        uint256 tokenSupply = poolInfo.totalDeposit;
        if (tokenSupply == 0) {
            // avoids division by 0 errors
            return 0;
        }
        brainzRewardWhole = pendingRewards;

        uint256 brainzRewardFee = brainzRewardWhole.mul(DEV_FEE).div(10000);
        uint256 brainzRewardToDistribute = brainzRewardWhole.sub(brainzRewardFee);

        uint256 inc = brainzRewardToDistribute.mul(1e18).div(tokenSupply);
        pending_DEV_rewards = pending_DEV_rewards.add(brainzRewardFee);

        poolInfo.accBrainzPerShare = poolInfo.accBrainzPerShare.add(inc);
        poolInfo.rewardsInThisEpoch = poolInfo.rewardsInThisEpoch.add(
            brainzRewardToDistribute
        );
    }

    function withdrawBrainz() public {
        withdraw(0);
    }

    function claimAndRestake() public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0);
        massUpdatePools();

        if (user.releaseTime == 0) {
            user.releaseTime = block.timestamp.add(REWARD_LOCKED_PERIOD);
        }
        uint256 _rewards = 0;
        if (block.timestamp > user.releaseTime) {
            //compute withdrawnable amount
            uint256 lockedAmount = user.rewardLocked;
            user.rewardLocked = 0;
            user.releaseTime = block.timestamp.add(REWARD_LOCKED_PERIOD);
            _rewards = _rewards.add(lockedAmount);
        }

        uint256 pending = pendingBrainz(msg.sender);
        uint256 paid = pending.mul(REWARD_RELEASE_PERCENTAGE).div(100);
        uint256 _lockedReward = pending.sub(paid);
        if (_lockedReward > 0) {
            user.rewardLocked = user.rewardLocked.add(_lockedReward);
        }

        _rewards = _rewards.add(paid);

        uint256 lockedPeriod = poolInfo.lockedPeriod;
        uint256 tobeReleased = computeReleasableBrainz(msg.sender);
        uint256 amountAfterDeposit = user.amount.add(_rewards);
        uint256 diffTime = tobeReleased.mul(lockedPeriod).div(
            amountAfterDeposit
        );
        user.depositTime = block.timestamp.sub(diffTime.div(2));
        //reset referenceAmount to start a new lock-release period
        user.referenceAmount = amountAfterDeposit;

        user.amount = user.amount.add(_rewards);
        user.rewardDebt = user.amount.mul(poolInfo.accBrainzPerShare).div(1e18);
        poolInfo.totalDeposit = poolInfo.totalDeposit.add(_rewards);

        transferDevFee();
        emit Restake(msg.sender, _rewards);
    }

    // Deposit  tokens to BrainzVault for Brainz allocation.
    function deposit(uint256 _originAmount) public {
        UserInfo storage user = userInfo[msg.sender];

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(msg.sender);

        pendingDeposit = computeDepositAmount(
            msg.sender,
            address(this),
            _originAmount
        );
        uint256 _actualDepositReceive = pendingDeposit;
        //Transfer in the amounts from user
        // save gas
        if (_actualDepositReceive > 0) {
            brainz.transferFrom(
                address(msg.sender),
                address(this),
                _originAmount
            );
            pendingDeposit = 0;
            updateDepositTime(msg.sender, _actualDepositReceive);
            user.amount = user.amount.add(_actualDepositReceive);
        }
        //massUpdatePools();
        user.rewardDebt = user.amount.mul(poolInfo.accBrainzPerShare).div(1e18);
        poolInfo.totalDeposit = poolInfo.totalDeposit.add(
            _actualDepositReceive
        );
        emit Deposit(msg.sender, _actualDepositReceive);
    }

    function updateDepositTime(address _addr, uint256 _depositAmount) internal {
        UserInfo storage user = userInfo[_addr];
        if (user.amount == 0) {
            user.depositTime = block.timestamp;
            user.referenceAmount = _depositAmount;
        } else {
            uint256 lockedPeriod = poolInfo.lockedPeriod;
            uint256 tobeReleased = computeReleasableBrainz(_addr);
            uint256 amountAfterDeposit = user.amount.add(_depositAmount);
            uint256 diffTime = tobeReleased.mul(lockedPeriod).div(
                amountAfterDeposit
            );
            user.depositTime = block.timestamp.sub(diffTime.div(2));
            //reset referenceAmount to start a new lock-release period
            user.referenceAmount = amountAfterDeposit;
        }
    }

    // Test coverage
    // [x] Does user get the deposited amounts?
    // [x] Does user that its deposited for update correcty?
    // [x] Does the depositor get their tokens decreased
    function depositFor(address _depositFor, uint256 _originAmount) public {
        // requires no allowances
        UserInfo storage user = userInfo[_depositFor];

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_depositFor); // Update the balances of person that amount is being deposited for

        pendingDeposit = computeDepositAmount(
            msg.sender,
            address(this),
            _originAmount
        );
        uint256 _actualDepositReceive = pendingDeposit;
        if (_actualDepositReceive > 0) {
            brainz.transferFrom(
                address(msg.sender),
                address(this),
                _originAmount
            );
            pendingDeposit = 0;
            updateDepositTime(_depositFor, _actualDepositReceive);
            user.amount = user.amount.add(_actualDepositReceive); // This is depositedFor address
        }

        user.rewardDebt = user.amount.mul(poolInfo.accBrainzPerShare).div(1e18); /// This is deposited for address
        poolInfo.totalDeposit = poolInfo.totalDeposit.add(
            _actualDepositReceive
        );
        emit Deposit(_depositFor, _actualDepositReceive);
    }

    function quitPool() public {
        require(
            block.timestamp > getBrainzReleaseStart(msg.sender),
            "cannot withdraw all lp tokens before"
        );

        uint256 withdrawnableAmount = computeReleasableBrainz(msg.sender);
        withdraw(withdrawnableAmount);
    }

    // Withdraw  tokens from BrainzVault.
    function withdraw(uint256 _amount) public {
        _withdraw(_amount, msg.sender, msg.sender);
    }

    // Low level withdraw function
    function _withdraw(
        uint256 _amount,
        address from,
        address to
    ) internal {
        //require(pool.withdrawable, "Withdrawing from this pool is disabled");
        UserInfo storage user = userInfo[from];
        require(computeReleasableBrainz(from) >= _amount, "withdraw: not good");

        massUpdatePools();
        updateAndPayOutPending(from); // Update balances of from this is not withdrawal but claiming Brainz farmed

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            poolInfo.totalDeposit = poolInfo.totalDeposit.sub(_amount);
            safeBrainzTransfer(address(to), _amount);
        }
        user.rewardDebt = user.amount.mul(poolInfo.accBrainzPerShare).div(1e18);

        emit Withdraw(to, _amount);
    }

    function updateAndPayOutPending(address from) internal {
        UserInfo storage user = userInfo[from];
        if (user.releaseTime == 0) {
            user.releaseTime = block.timestamp.add(REWARD_LOCKED_PERIOD);
        }
        if (block.timestamp > user.releaseTime) {
            //compute withdrawnable amount
            uint256 lockedAmount = user.rewardLocked;
            user.rewardLocked = 0;
            safeBrainzTransfer(from, lockedAmount);
            user.releaseTime = block.timestamp.add(REWARD_LOCKED_PERIOD);
        }

        uint256 pending = pendingBrainz(from);
        uint256 paid = pending.mul(REWARD_RELEASE_PERCENTAGE).div(100);
        uint256 _lockedReward = pending.sub(paid);
        if (_lockedReward > 0) {
            user.rewardLocked = user.rewardLocked.add(_lockedReward);
        }

        if (paid > 0) {
            safeBrainzTransfer(from, paid);
        }
    }

    function emergencyWithdraw() public {
        require(
            poolInfo.emergencyWithdrawable,
            "Withdrawing from this pool is disabled"
        );
        UserInfo storage user = userInfo[msg.sender];
        poolInfo.totalDeposit = poolInfo.totalDeposit.sub(user.amount);
        uint256 withdrawnAmount = user.amount;
        if (withdrawnAmount > brainz.balanceOf(address(this))) {
            withdrawnAmount = brainz.balanceOf(address(this));
        }
        safeBrainzTransfer(address(msg.sender), withdrawnAmount);
        emit EmergencyWithdraw(msg.sender, withdrawnAmount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeBrainzTransfer(address _to, uint256 _amount) internal {
        uint256 BrainzBal = brainz.balanceOf(address(this));

        if (_amount > BrainzBal) {
            brainz.transfer(_to, BrainzBal);
            BrainzBalance = brainz.balanceOf(address(this)).sub(brainzDeposit());
        } else {
            brainz.transfer(_to, _amount);
            BrainzBalance = brainz.balanceOf(address(this)).sub(brainzDeposit());
        }
        transferDevFee();
    }

    function transferDevFee() public {
        if (pending_DEV_rewards == 0) return;

        uint256 BrainzBal = brainz.balanceOf(address(this));
        if (pending_DEV_rewards > BrainzBal) {
            brainz.transfer(devaddr, BrainzBal);
            BrainzBalance = brainz.balanceOf(address(this)).sub(brainzDeposit());
        } else {
            brainz.transfer(devaddr, pending_DEV_rewards);
            BrainzBalance = brainz.balanceOf(address(this)).sub(brainzDeposit());
        }

        pending_DEV_rewards = 0;
    }

    function setDevFeeReciever(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }
}
