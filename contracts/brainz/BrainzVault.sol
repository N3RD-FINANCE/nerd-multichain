pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IBasicBrainz.sol";
import "../uniswapv2/interfaces/IUniswapV2Pair.sol";

// Have fun reading it. Hopefully it's bug-free. God bless.

contract TimeLockLPToken {
    using SafeMath for uint256;
    using Address for address;

    uint256 public constant LP_LOCKED_PERIOD_WEEKS = 4; //4 weeks,
    uint256 public constant LP_RELEASE_TRUNK = 1 weeks; //releasable every week,
    uint256 public constant LP_INITIAL_LOCKED_PERIOD = 14 days;

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
        IERC20 token; // Address of  token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Brainz to distribute per block.
        uint256 accBrainzPerShare; // Accumulated Brainz per share, times 1e18. See below.
        uint256 lockedPeriod; // liquidity locked period
        mapping(address => mapping(address => uint256)) allowance;
        bool emergencyWithdrawable;
        uint256 rewardsInThisEpoch;
        uint256 cumulativeRewardsSinceStart;
        uint256 startBlock;
        // For easy graphing historical epoch rewards
        mapping(uint256 => uint256) epochRewards;
        uint256 epochCalculationStartBlock;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes  tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // The Brainz TOKEN!
    IBasicBrainz public brainz;

    function getLpReleaseStart(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        return userInfo[_pid][_user].depositTime.add(LP_INITIAL_LOCKED_PERIOD);
    }

    function computeReleasableLP(uint256 _pid, address _addr)
        public
        view
        returns (uint256)
    {
        uint256 lpReleaseStart = getLpReleaseStart(_pid, _addr);
        if (block.timestamp < lpReleaseStart) {
            return 0;
        }

        uint256 amountLP = userInfo[_pid][_addr].referenceAmount;
        if (amountLP == 0) return 0;

        uint256 totalReleasableTilNow = 0;

        if (block.timestamp > lpReleaseStart.add(poolInfo[_pid].lockedPeriod)) {
            totalReleasableTilNow = amountLP;
        } else {
            uint256 weeksTilNow = weeksSinceLPReleaseTilNow(_pid, _addr);

            totalReleasableTilNow = weeksTilNow
                .mul(LP_RELEASE_TRUNK)
                .mul(amountLP)
                .div(poolInfo[_pid].lockedPeriod);
        }
        if (totalReleasableTilNow > amountLP) {
            totalReleasableTilNow = amountLP;
        }
        uint256 alreadyReleased = amountLP.sub(userInfo[_pid][_addr].amount);
        if (totalReleasableTilNow > alreadyReleased) {
            return totalReleasableTilNow.sub(alreadyReleased);
        }
        return 0;
    }

    function weeksSinceLPReleaseTilNow(uint256 _pid, address _addr)
        public
        view
        returns (uint256)
    {
        uint256 lpReleaseStart = getLpReleaseStart(_pid, _addr);
        if (lpReleaseStart == 0 || block.timestamp < lpReleaseStart) return 0;
        uint256 timeTillNow = block.timestamp.sub(lpReleaseStart);
        uint256 weeksTilNow = timeTillNow.div(LP_RELEASE_TRUNK);
        weeksTilNow = weeksTilNow.add(1);
        return weeksTilNow;
    }
}

contract BrainzVault is Ownable, TimeLockLPToken {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Dev address.
    address public devaddr;

    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    //// pending rewards awaiting anyone to massUpdate
    uint256 public pendingRewards;

    uint256 public epoch;

    uint256 public constant REWARD_LOCKED_PERIOD = 28 days;
    uint256 public constant REWARD_RELEASE_PERCENTAGE = 40;
    uint256 public contractStartBlock;

    uint256 private BrainzBalance;

    // Sets the dev fee for this contract
    // defaults at 7.24%
    // Note contract owner is meant to be a governance contract allowing Brainz governance consensus
    uint16 DEV_FEE;

    uint256 public pending_DEV_rewards;

    // Returns fees generated since start of this contract
    function averageFeesPerBlockSinceStart(uint256 _pid)
        external
        view
        returns (uint256 averagePerBlock)
    {
        averagePerBlock = poolInfo[_pid]
            .cumulativeRewardsSinceStart
            .add(poolInfo[_pid].rewardsInThisEpoch)
            .add(pendingBrainzForPool(_pid))
            .div(block.number.sub(poolInfo[_pid].startBlock));
    }

    // Returns averge fees in this epoch
    function averageFeesPerBlockEpoch(uint256 _pid)
        external
        view
        returns (uint256 averagePerBlock)
    {
        averagePerBlock = poolInfo[_pid]
            .rewardsInThisEpoch
            .add(pendingBrainzForPool(_pid))
            .div(block.number.sub(poolInfo[_pid].epochCalculationStartBlock));
    }

    function getEpochReward(uint256 _pid, uint256 _epoch)
        public
        view
        returns (uint256)
    {
        return poolInfo[_pid].epochRewards[_epoch];
    }

    //Starts a new calculation epoch
    // Because averge since start will not be accurate
    function startNewEpoch() public {
        for (uint256 _pid = 0; _pid < poolInfo.length; _pid++) {
            require(
                poolInfo[_pid].epochCalculationStartBlock + 50000 <
                    block.number,
                "New epoch not ready yet"
            ); // About a week
            poolInfo[_pid].epochRewards[epoch] = poolInfo[_pid]
                .rewardsInThisEpoch;
            poolInfo[_pid].cumulativeRewardsSinceStart = poolInfo[_pid]
                .cumulativeRewardsSinceStart
                .add(poolInfo[_pid].rewardsInThisEpoch);
            poolInfo[_pid].rewardsInThisEpoch = 0;
            poolInfo[_pid].epochCalculationStartBlock = block.number;
            ++epoch;
        }
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 _pid,
        uint256 value
    );

    constructor(IBasicBrainz _brainz, address _devAddress) public {
        DEV_FEE = 1000; //10%
        brainz = _brainz;
        devaddr = _devAddress;
        contractStartBlock = block.number;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function poolToken(uint256 _pid) external view returns (address) {
        return address(poolInfo[_pid].token);
    }

    function isMultipleOfWeek(uint256 _period) public pure returns (bool) {
        uint256 numWeeks = _period.div(LP_RELEASE_TRUNK);
        return (_period == numWeeks.mul(LP_RELEASE_TRUNK));
    }

    // Add a new token pool. Can only be called by the owner.
    // Note contract owner is meant to be a governance contract allowing Brainz governance consensus
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate
    ) public onlyOwner {
        require(address(_token) != address(brainz), "!Brainz token");
        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "Error pool already added");
        }

        totalAllocPoint = totalAllocPoint.add(_allocPoint);

        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                accBrainzPerShare: 0,
                lockedPeriod: LP_LOCKED_PERIOD_WEEKS.mul(LP_RELEASE_TRUNK),
                emergencyWithdrawable: false,
                rewardsInThisEpoch: 0,
                cumulativeRewardsSinceStart: 0,
                startBlock: block.number,
                epochCalculationStartBlock: block.number
            })
        );
    }

    function getDepositTime(uint256 _pid, address _addr)
        public
        view
        returns (uint256)
    {
        return userInfo[_pid][_addr].depositTime;
    }

    // Update the given pool's Brainz allocation point. Can only be called by the owner.
    // Note contract owner is meant to be a governance contract allowing Brainz governance consensus

    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }

        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function setEmergencyWithdrawable(uint256 _pid, bool _withdrawable)
        public
        onlyOwner
    {
        poolInfo[_pid].emergencyWithdrawable = _withdrawable;
    }

    function setDevFee(uint16 _DEV_FEE) public onlyOwner {
        require(_DEV_FEE <= 1000, "Dev fee clamped at 10%");
        DEV_FEE = _DEV_FEE;
    }

    function pendingBrainzForPool(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 tokenSupply = pool.token.balanceOf(address(this));

        if (tokenSupply == 0) return 0;

        uint256 rewardWhole = pendingRewards // Multiplies pending rewards by allocation point of this pool and then total allocation
            .mul(pool.allocPoint) // getting the percent of total pending rewards this pool should get
            .div(totalAllocPoint); // we can do this because pools are only mass updated
        uint256 rewardFee = rewardWhole.mul(DEV_FEE).div(10000);
        return rewardWhole.sub(rewardFee);
    }

    // View function to see pending Brainz on frontend.
    function pendingBrainz(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accBrainzPerShare = pool.accBrainzPerShare;
        uint256 amount = user.amount;

        uint256 tokenSupply = pool.token.balanceOf(address(this));

        if (tokenSupply == 0) return 0;

        uint256 rewardWhole = pendingRewards // Multiplies pending rewards by allocation point of this pool and then total allocation
            .mul(pool.allocPoint) // getting the percent of total pending rewards this pool should get
            .div(totalAllocPoint); // we can do this because pools are only mass updated
        uint256 rewardFee = rewardWhole.mul(DEV_FEE).div(10000);
        uint256 rewardToDistribute = rewardWhole.sub(rewardFee);
        uint256 inc = rewardToDistribute.mul(1e18).div(tokenSupply);
        accBrainzPerShare = accBrainzPerShare.add(inc);

        return amount.mul(accBrainzPerShare).div(1e18).sub(user.rewardDebt);
    }

    function getLockedReward(uint256 _pid, address _user)
        public
        view
        returns (uint256)
    {
        return userInfo[_pid][_user].rewardLocked;
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        uint256 allRewards;
        for (uint256 pid = 0; pid < length; ++pid) {
            allRewards = allRewards.add(updatePool(pid));
        }

        pendingRewards = pendingRewards.sub(allRewards);
    }

    // ----
    // Function that adds pending rewards, called by the Brainz token.
    // ----
    function updatePendingRewards() public {
        uint256 newRewards = brainz.balanceOf(address(this)).sub(BrainzBalance);

        if (newRewards > 0) {
            BrainzBalance = brainz.balanceOf(address(this)); // If there is no change the balance didn't change
            pendingRewards = pendingRewards.add(newRewards);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid)
        internal
        returns (uint256 brainzRewardWhole)
    {
        PoolInfo storage pool = poolInfo[_pid];

        uint256 tokenSupply = pool.token.balanceOf(address(this));

        if (tokenSupply == 0) {
            // avoids division by 0 errors
            return 0;
        }
        brainzRewardWhole = pendingRewards // Multiplies pending rewards by allocation point of this pool and then total allocation
            .mul(pool.allocPoint) // getting the percent of total pending rewards this pool should get
            .div(totalAllocPoint); // we can do this because pools are only mass updated

        uint256 rewardFee = brainzRewardWhole.mul(DEV_FEE).div(10000);
        uint256 rewardToDistribute = brainzRewardWhole.sub(rewardFee);

        uint256 inc = rewardToDistribute.mul(1e18).div(tokenSupply);
        pending_DEV_rewards = pending_DEV_rewards.add(rewardFee);

        pool.accBrainzPerShare = pool.accBrainzPerShare.add(inc);
        pool.rewardsInThisEpoch = pool.rewardsInThisEpoch.add(
            rewardToDistribute
        );
    }

    function withdrawReward(uint256 _pid) public {
        withdraw(_pid, 0);
    }

    // Deposit  tokens to BrainzVault for Brainz allocation.
    function deposit(uint256 _pid, uint256 _originAmount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, msg.sender);

        uint256 _amount = _originAmount;

        //Transfer in the amounts from user
        // save gas
        if (_amount > 0) {
            pool.token.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            updateDepositTime(_pid, msg.sender, _amount);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(pool.accBrainzPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function updateDepositTime(
        uint256 _pid,
        address _addr,
        uint256 _depositAmount
    ) internal {
        UserInfo storage user = userInfo[_pid][_addr];
        if (user.amount == 0) {
            user.depositTime = block.timestamp;
            user.referenceAmount = _depositAmount;
        } else {
            uint256 lockedPeriod = poolInfo[_pid].lockedPeriod;
            uint256 tobeReleased = computeReleasableLP(_pid, _addr);
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
    function depositFor(
        address _depositFor,
        uint256 _pid,
        uint256 _originAmount
    ) public {
        // requires no allowances
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_depositFor];

        massUpdatePools();

        // Transfer pending tokens
        // to user
        updateAndPayOutPending(_pid, _depositFor); // Update the balances of person that amount is being deposited for
        uint256 _amount = _originAmount;

        if (_amount > 0) {
            pool.token.safeTransferFrom(
                address(msg.sender),
                address(this),
                _amount
            );
            updateDepositTime(_pid, _depositFor, _amount);
            user.amount = user.amount.add(_amount); // This is depositedFor address
        }

        user.rewardDebt = user.amount.mul(pool.accBrainzPerShare).div(1e18); /// This is deposited for address
        emit Deposit(_depositFor, _pid, _amount);
    }

    // Test coverage
    // [x] Does allowance update correctly?
    function setAllowanceForPoolToken(
        address spender,
        uint256 _pid,
        uint256 value
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        pool.allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, _pid, value);
    }

    function quitPool(uint256 _pid) public {
        require(
            block.timestamp > getLpReleaseStart(_pid, msg.sender),
            "cannot withdraw all lp tokens before"
        );

        uint256 withdrawnableAmount = computeReleasableLP(_pid, msg.sender);
        withdraw(_pid, withdrawnableAmount);
    }

    // Test coverage
    // [x] Does allowance decrease?
    // [x] Do oyu need allowance
    // [x] Withdraws to correct address
    function withdrawFrom(
        address owner,
        uint256 _pid,
        uint256 _amount
    ) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            pool.allowance[owner][msg.sender] >= _amount,
            "withdraw: insufficient allowance"
        );
        pool.allowance[owner][msg.sender] = pool.allowance[owner][msg.sender]
            .sub(_amount);
        _withdraw(_pid, _amount, owner, msg.sender);
    }

    // Withdraw  tokens from BrainzVault.
    function withdraw(uint256 _pid, uint256 _amount) public {
        _withdraw(_pid, _amount, msg.sender, msg.sender);
    }

    // Low level withdraw function
    function _withdraw(
        uint256 _pid,
        uint256 _amount,
        address from,
        address to
    ) internal {
        PoolInfo storage pool = poolInfo[_pid];
        //require(pool.withdrawable, "Withdrawing from this pool is disabled");
        UserInfo storage user = userInfo[_pid][from];

        uint256 withdrawnableAmount = computeReleasableLP(_pid, from);
        require(withdrawnableAmount >= _amount, "withdraw: not good");

        massUpdatePools();
        updateAndPayOutPending(_pid, from); // Update balances of from this is not withdrawal but claiming Brainz farmed

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);

            pool.token.safeTransfer(address(to), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accBrainzPerShare).div(1e18);

        emit Withdraw(to, _pid, _amount);
    }

    function updateAndPayOutPending(uint256 _pid, address from) internal {
        UserInfo storage user = userInfo[_pid][from];
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

        uint256 pending = pendingBrainz(_pid, from);
        uint256 paid = pending.mul(REWARD_RELEASE_PERCENTAGE).div(100);
        uint256 _lockedReward = pending.sub(paid);
        if (_lockedReward > 0) {
            user.rewardLocked = user.rewardLocked.add(_lockedReward);
        }

        if (paid > 0) {
            safeBrainzTransfer(from, paid);
        }
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        require(
            pool.emergencyWithdrawable,
            "Withdrawing from this pool is disabled"
        );
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.token.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    function safeBrainzTransfer(address _to, uint256 _amount) internal {
        uint256 BrainzBal = brainz.balanceOf(address(this));

        if (_amount > BrainzBal) {
            brainz.transfer(_to, BrainzBal);
            BrainzBalance = brainz.balanceOf(address(this));
        } else {
            brainz.transfer(_to, _amount);
            BrainzBalance = brainz.balanceOf(address(this));
        }
        transferDevFee();
    }

    function transferDevFee() public {
        if (pending_DEV_rewards == 0) return;

        uint256 BrainzBal = brainz.balanceOf(address(this));
        if (pending_DEV_rewards > BrainzBal) {
            brainz.transfer(devaddr, BrainzBal);
            BrainzBalance = brainz.balanceOf(address(this));
        } else {
            brainz.transfer(devaddr, pending_DEV_rewards);
            BrainzBalance = brainz.balanceOf(address(this));
        }

        pending_DEV_rewards = 0;
    }

    function setDevFeeReciever(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    function getLiquidityInfo(uint256 _pid)
        public
        view
        returns (
            uint256 lpSupply,
            uint256 brainzAmount,
            uint256 totalBrainzAmount,
            uint256 tokenAmount,
            uint256 totalTokenAmount,
            uint256 lockedLP,
            uint256 totalLockedLP
        )
    {
        IERC20 lpToken = poolInfo[_pid].token;
        IERC20 brainzToken = IERC20(address(brainz));
        IUniswapV2Pair pair = IUniswapV2Pair(address(lpToken));
        address otherTokenAddress = (pair.token0() == address(brainz))
            ? pair.token1()
            : pair.token0();
        IERC20 otherToken = IERC20(otherTokenAddress);

        lpSupply = lpToken.totalSupply();
        if (lpSupply > 0) {
            uint256 lpBrainzBalance = brainzToken.balanceOf(address(lpToken));
            uint256 lpOtherBalance = otherToken.balanceOf(address(lpToken));

            lockedLP = lpToken.balanceOf(address(this));

            totalLockedLP = lockedLP;

            brainzAmount = lockedLP.mul(lpBrainzBalance).div(lpSupply);
            totalBrainzAmount = totalLockedLP.mul(lpBrainzBalance).div(lpSupply);

            tokenAmount = lockedLP.mul(lpOtherBalance).div(lpSupply);
            totalTokenAmount = totalLockedLP.mul(lpOtherBalance).div(lpSupply);
        }
    }
}