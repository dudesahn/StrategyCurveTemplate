// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/Math.sol";

import { I2crvGauge as ICurveGauge } from "../interfaces/I2crvGauge.sol";
import { I2crvPool as ICurvePool } from "../interfaces/I2crvPool.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";
import {
  BaseStrategy,
  StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

abstract contract StrategyCurveBase is BaseStrategy {
  using Address for address;

  /* ========== STATE VARIABLES ========== */
  // these should stay the same across different wants (`2CRV` LP tokens, `crv3crypto` LP tokens, etc.).

  ICurveGauge public immutable gauge;

  ICurvePool public immutable curve;

  address internal immutable wethAddress;

  // Uniswap V3 router
  ISwapRouter public immutable router;

  IERC20 public crv;
  IERC20 public weth;

  bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us
  uint256 public creditThreshold; // amount of credit in underlying tokens that will automatically trigger a harvest

  string internal stratName; // set our strategy name here

  /* ========== CONSTRUCTOR ========== */

  constructor(
    address _vaultAddress,
    address _healthCheckAddress,
    address _gaugeAddress,
    address _poolAddress,
    address _wethAddress,
    address _crvAddress,
    address _routerAddress
  ) public BaseStrategy(_vaultAddress) {
    // Curve contracts
    gauge = ICurveGauge(_gaugeAddress);
    curve = ICurvePool(_poolAddress);
    crv = IERC20(_crvAddress);

    // Uniswap V3 router
    router = ISwapRouter(_routerAddress);

    // Wrapped ETH
    wethAddress = _wethAddress;

    // You can set these parameters on deployment to whatever you want
    maxReportDelay = 2 days; // 2 days in seconds

    // Arbitrum healthcheck contract address
    healthCheck = _healthCheckAddress;

    // Our standard approvals. want = Curve LP token
    want.safeApprove(_gaugeAddress, type(uint256).max);
    crv.safeApprove(_routerAddress, type(uint256).max);
  }

  /* ========== VIEWS ========== */

  function name() external view override returns (string memory) {
    return stratName;
  }

  function stakedBalance() public view returns (uint256) {
    return gauge.balanceOf(address(this));
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
    // Send all of our LP tokens to deposit to the gauge if we have any
    uint256 _toInvest = balanceOfWant();
    if (_toInvest > 0) {
      gauge.deposit(_toInvest);
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
        gauge.withdraw(Math.min(_stakedBal, _amountNeeded.sub(_wantBal)));
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
      gauge.withdraw(_stakedBal);
    }
    return balanceOfWant();
  }

  function prepareMigration(address _newStrategy) internal override {
    uint256 _stakedBal = stakedBalance();
    if (_stakedBal > 0) {
      gauge.withdraw(_stakedBal);
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

  // Credit threshold is in want token, and will trigger a harvest if credit is large enough.
  function setCreditThreshold(uint256 _creditThreshold)
    external
    onlyEmergencyAuthorized
  {
    creditThreshold = _creditThreshold;
  }

  // This allows us to manually harvest with our keeper as needed
  function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
    external
    onlyEmergencyAuthorized
  {
    forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
  }

  /* ========== KEEP3RS ========== */

  /// @param callCostInWei Cost of the contract call to harvest(). Used to determine if the profit (if any) is
  ///   sufficiently large to justify the call to harvest()
  function harvestTrigger(uint256 callCostInWei)
    public
    view
    override
    returns (bool)
  {
    // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
    if (!isActive()) {
      return false;
    }

    StrategyParams memory params = vault.strategies(address(this));
    // harvest no matter what once we reach our maxDelay
    if (block.timestamp.sub(params.lastReport) > maxReportDelay) {
      return true;
    }

    // harvest our credit if it's above our threshold
    if (vault.creditAvailable() > creditThreshold) {
      return true;
    }

    // trigger if we want to manually harvest
    if (forceHarvestTriggerOnce) {
      return true;
    }

    // otherwise, we don't harvest
    return false;
  }

  // convert our keeper's eth cost into want, we don't need this anymore since we don't use baseStrategy harvestTrigger
  function ethToWant(uint256 _ethAmount)
    public
    view
    override
    returns (uint256)
  {
    return _ethAmount;
  }
}
