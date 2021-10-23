// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./interfaces/curve.sol";
import "./interfaces/yearn.sol";
import {IUniswapV2Router02} from "./interfaces/uniswap.sol";
import {BaseStrategy} from "@yearnvaults/contracts/BaseStrategy.sol";

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

abstract contract StrategyCurveBase is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.

    // curve infrastructure contracts
    ICurveStrategyProxy public proxy; // Below we set it to Yearn's Updated v4 StrategyProxy
    address public gauge; // Curve gauge contract, most are tokenized, held by Yearn's voter

    // keepCRV stuff
    uint256 public keepCRV = 1000; // the percentage of CRV we re-lock for boost (in basis points)
    uint256 internal constant FEE_DENOMINATOR = 10000; // this means all of our fee values are in basis points
    address public constant voter = 0xF147b8125d2ef93FB6965Db97D6746952a133934; // Yearn's veCRV voter

    // swap stuff
    address internal constant sushiswap =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // default to sushiswap, more CRV liquidity there
    address[] public crvPath;

    IERC20 internal constant crv =
        IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 internal constant weth =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

    string internal stratName; // set our strategy name here

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) public BaseStrategy(_vault) {}

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return stratName;
    }

    function stakedBalance() public view returns (uint256) {
        return proxy.balanceOf(gauge);
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(stakedBalance());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these should stay the same across different wants.

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        // Send all of our LP tokens to the proxy and deposit to the gauge if we have any
        uint256 _toInvest = balanceOfWant();
        if (_toInvest > 0) {
            want.safeTransfer(address(proxy), _toInvest);
            proxy.deposit(gauge, address(want));
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _wantBal = balanceOfWant();
        if (_amountNeeded > _wantBal) {
            // check if we have enough free funds to cover the withdrawal
            uint256 _stakedBal = stakedBalance();
            if (_stakedBal > 0) {
                proxy.withdraw(
                    gauge,
                    address(want),
                    Math.min(_stakedBal, _amountNeeded.sub(_wantBal))
                );
            }
            uint256 _withdrawnBal = balanceOfWant();
            _liquidatedAmount = Math.min(_amountNeeded, _withdrawnBal);
            _loss = _amountNeeded.sub(_liquidatedAmount);
        } else {
            // we have enough balance to cover the liquidation available
            return (_amountNeeded, 0);
        }
    }

    // fire sale, get rid of it all!
    function liquidateAllPositions() internal override returns (uint256) {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            // don't bother withdrawing zero
            proxy.withdraw(gauge, address(want), _stakedBal);
        }
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            proxy.withdraw(gauge, address(want), _stakedBal);
        }
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    // Use to update Yearn's StrategyProxy contract as needed in case of upgrades.
    function setProxy(address _proxy) external onlyGovernance {
        proxy = ICurveStrategyProxy(_proxy);
    }

    // Set the amount of CRV to be locked in Yearn's veCRV voter from each harvest. Default is 10%.
    function setKeepCRV(uint256 _keepCRV) external onlyAuthorized {
        require(_keepCRV <= 10_000);
        keepCRV = _keepCRV;
    }

    // This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }
}

contract StrategyCurve3CrvRewardsClonable is StrategyCurveBase {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // Curve stuff
    address public curve; // This is our pool specific to this vault. Use it with zap contract to specify our correct pool.
    ICurveFi internal constant zapContract =
        ICurveFi(0xA79828DF1850E8a3A3064576f380D90aECDD3359); // this is used for depositing to all 3Crv metapools

    uint256 public maxGasPrice; // this is the max gas price we want our keepers to pay for harvests/tends in gwei

    // we use these to deposit to our curve pool
    uint256 public optimal; // this is the optimal token to deposit back to our curve pool. 0 DAI, 1 USDC, 2 USDT
    IERC20 internal constant usdt =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant usdc =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant dai =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // rewards token info. we can have more than 1 reward token but this is rare, so we don't include this in the template
    IERC20 public rewardsToken;
    bool public hasRewards;
    address[] public rewardsPath;

    // check for cloning
    bool internal isOriginal = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        address _curvePool,
        address _gauge,
        bool _hasRewards,
        address _rewardsToken,
        string memory _name
    ) public StrategyCurveBase(_vault) {
        _initializeStrat(_curvePool, _gauge, _hasRewards, _rewardsToken, _name);
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // we use this to clone our original strategy to other vaults
    function cloneCurve3CrvRewards(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _curvePool,
        address _gauge,
        bool _hasRewards,
        address _rewardsToken,
        string memory _name
    ) external returns (address newStrategy) {
        require(isOriginal);
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStrategy := create(0, clone_code, 0x37)
        }

        StrategyCurve3CrvRewardsClonable(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _curvePool,
            _gauge,
            _hasRewards,
            _rewardsToken,
            _name
        );

        emit Cloned(newStrategy);
    }

    // this will only be called by the clone function above
    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _curvePool,
        address _gauge,
        bool _hasRewards,
        address _rewardsToken,
        string memory _name
    ) public {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_curvePool, _gauge, _hasRewards, _rewardsToken, _name);
    }

    // this is called by our original strategy, as well as any clones
    function _initializeStrat(
        address _curvePool,
        address _gauge,
        bool _hasRewards,
        address _rewardsToken,
        string memory _name
    ) internal {
        // make sure that we haven't initialized this before
        require(address(curve) == address(0)); // already initialized.

        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 7 days; // 7 days in seconds
        debtThreshold = 5 * 1e18; // we shouldn't ever have debt, but set a bit of a buffer
        profitFactor = 1_000_000; // in this strategy, profitFactor is only used for telling keep3rs when to move funds from vault to strategy
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012; // health.ychad.eth

        // need to set our proxy again when cloning since it's not a constant
        proxy = ICurveStrategyProxy(0xA420A63BbEFfbda3B147d0585F1852C358e2C152);

        // these are our standard approvals. want = Curve LP token
        want.approve(address(proxy), type(uint256).max);
        crv.approve(sushiswap, type(uint256).max);

        // set our keepCRV
        keepCRV = 1000;

        // setup our rewards if we have them
        if (_hasRewards) {
            rewardsToken = IERC20(_rewardsToken);
            rewardsToken.approve(sushiswap, type(uint256).max);
            rewardsPath = [address(rewardsToken), address(weth), address(dai)];
            hasRewards = true;
        }

        // this is the pool specific to this vault, but we only use it as an address
        curve = address(_curvePool);

        // set our curve gauge contract
        gauge = address(_gauge);

        // set our strategy's name
        stratName = _name;

        // these are our approvals and path specific to this contract
        dai.approve(address(zapContract), type(uint256).max);
        usdt.safeApprove(address(zapContract), type(uint256).max); // USDT requires safeApprove(), funky token
        usdc.approve(address(zapContract), type(uint256).max);

        // start off with dai
        crvPath = [address(crv), address(weth), address(dai)];

        // set our max gas price
        maxGasPrice = 100 * 1e9;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */
    // these will likely change across different wants.

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // if we have anything in the gauge, then harvest CRV from the gauge
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            proxy.harvest(gauge);
            uint256 _crvBalance = crv.balanceOf(address(this));
            // if we claimed any CRV, then sell it
            if (_crvBalance > 0) {
                // keep some of our CRV to increase our boost
                uint256 _sendToVoter =
                    _crvBalance.mul(keepCRV).div(FEE_DENOMINATOR);
                if (keepCRV > 0) {
                    crv.safeTransfer(voter, _sendToVoter);
                }
                uint256 _crvRemainder = _crvBalance.sub(_sendToVoter);

                // sell the rest of our CRV
                if (_crvRemainder > 0) {
                    _sell(_crvRemainder);
                }

                if (hasRewards) {
                    proxy.claimRewards(gauge, address(rewardsToken));
                    uint256 _rewardsBalance =
                        rewardsToken.balanceOf(address(this));
                    if (_rewardsBalance > 0) {
                        _sellRewards(_rewardsBalance);
                    }
                }

                // deposit our balance to Curve if we have any
                if (optimal == 0) {
                    uint256 _daiBalance = dai.balanceOf(address(this));
                    if (_daiBalance > 0) {
                        zapContract.add_liquidity(
                            curve,
                            [0, _daiBalance, 0, 0],
                            0
                        );
                    }
                } else if (optimal == 1) {
                    uint256 _usdcBalance = usdc.balanceOf(address(this));
                    if (_usdcBalance > 0) {
                        zapContract.add_liquidity(
                            curve,
                            [0, 0, _usdcBalance, 0],
                            0
                        );
                    }
                } else {
                    uint256 _usdtBalance = usdt.balanceOf(address(this));
                    if (_usdtBalance > 0) {
                        zapContract.add_liquidity(
                            curve,
                            [0, 0, 0, _usdtBalance],
                            0
                        );
                    }
                }
            }
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        if (_debtOutstanding > 0) {
            if (_stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                proxy.withdraw(
                    gauge,
                    address(want),
                    Math.min(_stakedBal, _debtOutstanding)
                );
            }
            uint256 _withdrawnBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
        }

        // serious loss should never happen, but if it does (for instance, if Curve is hacked), let's record it accurately
        uint256 assets = estimatedTotalAssets();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        // if assets are greater than debt, things are working great!
        if (assets > debt) {
            _profit = assets.sub(debt);
            uint256 _wantBal = balanceOfWant();
            if (_profit.add(_debtPayment) > _wantBal) {
                // this should only be hit following donations to strategy
                liquidateAllPositions();
            }
        }
        // if assets are less than debt, we are in trouble
        else {
            _loss = debt.sub(assets);
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    // Sells our harvested CRV into the selected output.
    function _sell(uint256 _amount) internal {
        IUniswapV2Router02(sushiswap).swapExactTokensForTokens(
            _amount,
            uint256(0),
            crvPath,
            address(this),
            block.timestamp
        );
    }

    // Sells our harvested reward token into the selected output.
    function _sellRewards(uint256 _amount) internal {
        IUniswapV2Router02(sushiswap).swapExactTokensForTokens(
            _amount,
            uint256(0),
            rewardsPath,
            address(this),
            block.timestamp
        );
    }

    /* ========== KEEP3RS ========== */

    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        // trigger if we want to manually harvest
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        // check if the base fee gas price is higher than we allow
        if (readBaseFee() > maxGasPrice) {
            return false;
        }

        return super.harvestTrigger(callCostinEth);
    }

    // convert our keeper's eth cost into want
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {
        uint256 callCostInWant;
        if (_ethAmount > 0) {
            address[] memory ethPath = new address[](2);
            ethPath[0] = address(weth);
            ethPath[1] = address(dai);

            uint256[] memory _callCostInDaiTuple =
                IUniswapV2Router02(sushiswap).getAmountsOut(
                    _ethAmount,
                    ethPath
                );

            uint256 _callCostInDai =
                _callCostInDaiTuple[_callCostInDaiTuple.length - 1];
            callCostInWant = zapContract.calc_token_amount(
                curve,
                [0, _callCostInDai, 0, 0],
                true
            );
        }
        return callCostInWant;
    }

    // check the current baseFee
    function readBaseFee() internal view returns (uint256 baseFee) {
        IBaseFee _baseFeeOracle =
            IBaseFee(0xf8d0Ec04e94296773cE20eFbeeA82e76220cD549);
        return _baseFeeOracle.basefee_global();
    }

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    // Use to add or update rewards
    function updateRewards(address _rewardsToken) external onlyGovernance {
        // reset allowance to zero for our previous token if we had one
        if (address(rewardsToken) != address(0)) {
            rewardsToken.approve(sushiswap, uint256(0));
        }
        // update with our new token, use dai as default
        rewardsToken = IERC20(_rewardsToken);
        rewardsToken.approve(sushiswap, type(uint256).max);
        rewardsPath = [address(rewardsToken), address(weth), address(dai)];
        hasRewards = true;
    }

    // Use to turn off extra rewards claiming
    function turnOffRewards() external onlyGovernance {
        hasRewards = false;
        if (address(rewardsToken) != address(0)) {
            rewardsToken.approve(sushiswap, uint256(0));
        }
        rewardsToken = IERC20(address(0));
    }

    // Set optimal token to sell harvested funds for depositing to Curve.
    // Default is DAI, but can be set to USDC or USDT as needed by strategist or governance.
    function setOptimal(uint256 _optimal) external onlyAuthorized {
        if (_optimal == 0) {
            crvPath[2] = address(dai);
            if (hasRewards) {
                rewardsPath[2] = address(dai);
            }
            optimal = 0;
        } else if (_optimal == 1) {
            crvPath[2] = address(usdc);
            if (hasRewards) {
                rewardsPath[2] = address(usdc);
            }
            optimal = 1;
        } else if (_optimal == 2) {
            crvPath[2] = address(usdt);
            if (hasRewards) {
                rewardsPath[2] = address(usdt);
            }
            optimal = 2;
        } else {
            revert("incorrect token");
        }
    }

    // set the maximum gas price we want to pay for a harvest/tend in gwei
    function setGasPrice(uint256 _maxGasPrice) external onlyAuthorized {
        maxGasPrice = _maxGasPrice.mul(1e9);
    }
}
