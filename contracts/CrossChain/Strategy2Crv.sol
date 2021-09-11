// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "../interfaces/curve.sol";
import "../interfaces/yearn.sol";
import "./StrategyCurveBaseUsingGauge.sol";

contract StrategyCurve2Crv is StrategyCurveBaseUsingGauge {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    address public curve; // This is our pool specific to this vault. Use it with zap contract to specify our correct pool.

    IERC20 public constant crv =
        IERC20(0x1E4F97b9f9F913c46F1632781732927B9019C68b);

    // we use these to deposit to our curve pool
    IERC20 public constant usdc =
        IERC20(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    IERC20 public constant dai =
        IERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E);
    IERC20 public constant wftm =
        IERC20(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);

    address public constant voter = 0x72a34AbafAB09b15E7191822A679f28E067C4a16; // sms

    // rewards token info. we can have more than 1 reward token but this is rare, so we don't include this in the template
    IERC20 public rewardsToken;
    bool public hasRewards;

    // Target trades
    address public rewardsTarget;
    address public crvTarget;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        address _tradeFactory,
        address _curvePool,
        address _gauge,
        bool _hasRewards,
        address _rewardsToken,
        string memory _name
    ) public StrategyCurveBaseUsingGauge(_vault, _tradeFactory) {
          // You can set these parameters on deployment to whatever you want
          maxReportDelay = 7 days; // 7 days in seconds
          debtThreshold = 5 * 1e18; // we shouldn't ever have debt, but set a bit of a buffer
          profitFactor = 10_000; // in this strategy, profitFactor is only used for telling keep3rs when to move funds from vault to strategy
          healthCheck = 0xf13Cd6887C62B5beC145e30c38c4938c5E627fe0; // health.ychad.eth

          // set our keepCRV
          // keepCRV = 0; not needed since we set it to 0

          // setup our rewards if we have them
          if (_hasRewards) {
              hasRewards = true;
              rewardsToken = IERC20(_rewardsToken);
              rewardsTarget = address(dai);
          }

          // this is the pool specific to this vault, but we only use it as an address
          curve = address(_curvePool);

          // set our curve gauge contract
          gauge = IGauge(_gauge);

          // set our strategy's name
          stratName = _name;

          // these are our approvals and path specific to this contract
          dai.approve(address(curve), type(uint256).max);
          usdc.approve(address(curve), type(uint256).max);
          want.approve(address(gauge), type(uint256).max);

          // start off with dai
          crvTarget = address(dai);
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
            gauge.claim_rewards();
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
                    _sell(address(crv), crvTarget, _crvRemainder);
                }

                if (hasRewards) {
                    uint256 _rewardsBalance =
                        rewardsToken.balanceOf(address(this));
                    if (_rewardsBalance > 0) {
                        _sell(address(rewardsToken), rewardsTarget, _rewardsBalance);
                    }
                }
            }
        }

        // If there is dai or usdc add liquidity to get more want
        uint256 _dai = IERC20(dai).balanceOf(address(this));
        uint256 _usdc = IERC20(usdc).balanceOf(address(this));
        if (_dai > 0 || _usdc > 0) {
            ICurveFi(curve).add_liquidity([_dai, _usdc], 0);
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        if (_debtOutstanding > 0) {
            if (_stakedBal > 0) {
                // don't bother withdrawing if we don't have staked funds
                gauge.withdraw(Math.min(_stakedBal, _debtOutstanding));
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
    function _sell(address token, address target, uint256 _amount) internal {
        uint256 _balance = IERC20(token).balanceOf(address(this));
        uint256 _tokenAllowance = _tradeFactoryAllowance(token);
        if (_balance > _tokenAllowance) {
            _createTrade(token, target, _balance - _tokenAllowance, tradeSlippage, block.timestamp + 604800);
        }
    }

    /* ========== KEEP3RS ========== */

    // convert our keeper's eth cost into want
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {
        // Not needed
        return _ethAmount;
    }

    /* ========== SETTERS ========== */

    // These functions are useful for setting parameters of the strategy that may need to be adjusted.

    // Use to add or update rewards
    function updateRewards(address _rewardsToken) external onlyGovernance {
        rewardsToken = IERC20(_rewardsToken);
        // update with our new token, use dai as default
        rewardsTarget = address(dai);
        hasRewards = true;
    }

    // Use to turn off extra rewards claiming
    function turnOffRewards() external onlyGovernance {
        hasRewards = false;
        rewardsToken = IERC20(address(0));
    }
}
