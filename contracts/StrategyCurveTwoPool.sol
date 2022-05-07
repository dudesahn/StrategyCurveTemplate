// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// Import required libraries
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/Math.sol";
import { StrategyCurveBase } from "./StrategyCurveBase.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol";

contract StrategyCurveTwoPool is StrategyCurveBase {
  /* ========== STATE VARIABLES ========== */
  // `targetTokenAddress` is the token we buy with CRV rewards and the token we then
  // deposit into the curve pool -- USDT or USDC
  address public targetTokenAddress;

  IERC20 internal usdt;
  IERC20 internal usdc;

  uint24 public crvToWethSwapFee;
  uint24 public wethToTargetSwapFee;

  /* ============= CONSTRUCTOR =========== */
  constructor(
    address _vault,
    string memory _name,
    address _usdtAddress,
    address _usdcAddress,
    address _healthCheckAddress,
    address _gaugeAddress,
    address _poolAddress,
    address _wethAddress,
    address _crvAddress,
    address _routerAddress
  )
    public
    StrategyCurveBase(
      _vault,
      _healthCheckAddress,
      _gaugeAddress,
      _poolAddress,
      _wethAddress,
      _crvAddress,
      _routerAddress
    )
  {
    // Set our strategy's name
    stratName = _name;

    usdt = IERC20(_usdtAddress);
    usdc = IERC20(_usdcAddress);

    // Required strategic-specific approvals
    usdt.safeApprove(_poolAddress, type(uint256).max);
    usdc.safeApprove(_poolAddress, type(uint256).max);

    // Start off with USDT
    targetTokenAddress = _usdtAddress;

    // Uniswap V3 pool fees
    crvToWethSwapFee = 3000;
    wethToTargetSwapFee = 500;
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
    // harvest our rewards from the gauge
    gauge.claim_rewards();

    uint256 crvBalance = crv.balanceOf(address(this));

    // if we claimed any CRV, then sell it
    if (crvBalance > 0) {
      _sell(crvBalance);
      uint256 usdtBalance = usdt.balanceOf(address(this));
      uint256 usdcBalance = usdc.balanceOf(address(this));
      curve.add_liquidity([usdcBalance, usdtBalance], 0);
    }

    // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
    if (_debtOutstanding > 0) {
      uint256 stakedBal = stakedBalance(); // Balance of LP tokens in the curve gauge
      if (stakedBal > 0) {
        // don't bother withdrawing if we don't have staked funds
        gauge.withdraw(Math.min(stakedBal, _debtOutstanding));
      }
      uint256 _withdrawnBal = balanceOfWant();
      _debtPayment = Math.min(_debtOutstanding, _withdrawnBal);
    }

    // serious loss should never happen, but if it does (for instance, if Curve is hacked), let's record it accurately
    uint256 assets = estimatedTotalAssets();
    uint256 debt = vault.strategies(address(this)).totalDebt;

    // if assets are greater than debt, we have a profit
    if (assets > debt) {
      _profit = assets.sub(debt);
      uint256 _wantBal = balanceOfWant();
      if (_profit.add(_debtPayment) > _wantBal) {
        // this should only be hit following donations to strategy
        liquidateAllPositions();
      }
    }
    // if assets are less than debt, we have a loss
    else {
      _loss = debt.sub(assets);
    }

    // we're done harvesting, so reset our trigger if we used it
    forceHarvestTriggerOnce = false;
  }

  event DebugAddress(uint256 step, address data);
  event DebugUint24(uint256 step, uint24 data);
  event DebugUint256(uint256 step, uint256 data);
  event DebugBytes(uint256 step, bytes data);

  // TODO: REMOVE!
  function sell(uint256 _amount) external {
      _sell(_amount);
  }

  // Sell our CRV in Uniswap V3 for our `targetToken`, USDT or USDC
  function _sell(uint256 _amount) internal {
    emit DebugAddress(0, address(crv));
    emit DebugAddress(1, wethAddress);
    emit DebugAddress(2, targetTokenAddress);
    emit DebugUint24(3, crvToWethSwapFee);
    emit DebugUint24(4, wethToTargetSwapFee);

    // gets multi-hop path for uniswap v3 swaps
    bytes memory path =
      abi.encodePacked(
        address(crv),
        crvToWethSwapFee,
        wethAddress,
        wethToTargetSwapFee,
        targetTokenAddress
      );

    emit DebugBytes(5, path);
    emit DebugAddress(6, address(this));
    emit DebugUint256(7, _amount);

    router.exactInput(
      ISwapRouter.ExactInputParams(
        path, // multi-hop path
        address(this),
        _amount,
        0 // amountOutMinimum
      )
    );
  }

  /* ========== SETTERS ========== */

  // These functions are useful for setting parameters of the strategy that may need to be adjusted.
  // Set optimal token to sell harvested funds for depositing to Curve.
  // Default is USDC, but can be set to USDT as needed by strategist or governance.
  function settargetToken(uint256 _optimal) external onlyEmergencyAuthorized {
    if (_optimal == 0) {
      targetTokenAddress = address(usdt);
    } else if (_optimal == 1) {
      targetTokenAddress = address(usdc);
    } else {
      revert("incorrect token");
    }
  }

  function setSwapFees(uint24 _crvToWethSwapFee, uint24 _wethToTargetSwapFee)
    external
    onlyVaultManagers
  {
    // Likely to be run when/if we change the target token
    crvToWethSwapFee = _crvToWethSwapFee;
    wethToTargetSwapFee = _wethToTargetSwapFee;
  }
}
