// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// These are the core Yearn libraries
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/Math.sol";

import { ICurveGauge, ICurveGaugeFactory, ICurvePool } from "../interfaces/ICurveTwoPool.sol";
import { ISwapRouter } from "../interfaces/ISwapRouter.sol"; // Uni V3
import { BaseStrategy, StrategyParams } from "@yearnvaults/contracts/BaseStrategy.sol";

// To avoid the "stack too deep" error
struct ContractAddress {
  address vault;
  address healthCheck;
  address usdt;
  address usdc;
  address weth;
  address crv;
  address router;
  address gauge;
  address gaugeFactory;
  address pool;
}

abstract contract StrategyCurveBase is BaseStrategy {
  using Address for address;

  /* ========== STATE VARIABLES ========== */
  // these should stay the same across different wants (`2CRV` LP tokens, `crv3crypto` LP tokens, etc.).

  ICurveGauge public immutable gauge;

  ICurveGaugeFactory public immutable gaugeFactory;

  ICurvePool public immutable curve;

  address public immutable wethAddress;

  // Uniswap V3 router
  ISwapRouter public immutable router;

  IERC20 public crv;

  bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us
  uint256 public creditThreshold; // amount of credit in underlying tokens that will automatically trigger a harvest

  /* ========== CONSTRUCTOR ========== */

  constructor(ContractAddress memory _contractsAddress)
    public
    BaseStrategy(_contractsAddress.vault)
  {
    // Curve contracts
    gauge = ICurveGauge(_contractsAddress.gauge);
    gaugeFactory = ICurveGaugeFactory(_contractsAddress.gaugeFactory);
    curve = ICurvePool(_contractsAddress.pool);
    crv = IERC20(_contractsAddress.crv);

    // Uniswap V3 router
    router = ISwapRouter(_contractsAddress.router);

    // Wrapped ETH - Used for multi-hop swap. No contract instance needed
    wethAddress = _contractsAddress.weth;

    // Arbitrum healthcheck contract address
    healthCheck = _contractsAddress.healthCheck;

    // Our standard approvals. want = Curve LP token
        want.approve(_contractsAddress.gauge, type(uint256).max);
        crv.approve(_contractsAddress.router, type(uint256).max);

    maxReportDelay = 2 days; // 2 days in seconds
  }

  /* ========== VIEWS ========== */

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

  function liquidateAllPositions() internal override returns (uint256) {
    uint256 _stakedBal = stakedBalance();
    if (_stakedBal > 0) {
      // don't bother withdrawing zero
      gauge.withdraw(_stakedBal);
    }
    return balanceOfWant();
  }

    function _claimRewards() internal {
        gaugeFactory.mint(address(gauge));
    }

    function claimRewards() external onlyVaultManagers {
        // Claims any pending CRV
        //
        // Mints claimable CRV from the factory gauge. Reward tokens are sent to `msg.sender`
        // The method claim_rewards() from the old gauge now only applies to third-party tokens.
        // There are no third-party tokens in this strategy.
        _claimRewards();
    }

  function prepareMigration(address _newStrategy) internal override {
        // Withdraw LP tokens from the gauge. The transfer to the new strategy is done
        // by migrate() in BaseStrategy.sol. Note that this function does not claim
        // any pending rewards. To claim and transfer pending rewards to a new
        // strategy, please use claimAndTransferRewards()
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

contract StrategyCurveTwoPool is StrategyCurveBase {
  /* ========== STATE VARIABLES ========== */
  // `targetTokenAddress` is the token we buy with CRV rewards and the token we then
  // deposit into the curve pool -- USDT or USDC
  address public targetTokenAddress;

  IERC20 internal usdt;
  IERC20 internal usdc;

  // Uniswap V3 pool fees
  uint24 public crvToWethSwapFee = 3000;
  uint24 public wethToTargetSwapFee = 500;

  uint24 internal constant maxFee = 10000;

  string internal stratName; // set our strategy name here

  /* ============= CONSTRUCTOR =========== */
  constructor(
    string memory _stratName,
    ContractAddress memory _contractsAddress
  ) public StrategyCurveBase(_contractsAddress) {
    // Set our strategy's name
    stratName = _stratName;

    usdt = IERC20(_contractsAddress.usdt);
    usdc = IERC20(_contractsAddress.usdc);

    // Required strategic-specific approvals
        usdt.approve(_contractsAddress.pool, type(uint256).max);
        usdc.approve(_contractsAddress.pool, type(uint256).max);

        // Start off with USDC
        targetTokenAddress = _contractsAddress.usdc;
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
        // Claim and get a fresh snapshot of the strategy's CRV balance
        _claimRewards();

    uint256 crvBalance = crv.balanceOf(address(this));

        // Sell CRV if we have any
    if (crvBalance > 0) {
      _sell(crvBalance);
      uint256 usdtBalance = usdt.balanceOf(address(this));
      uint256 usdcBalance = usdc.balanceOf(address(this));
      curve.add_liquidity([usdcBalance, usdtBalance], 0);
    }

    // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
    if (_debtOutstanding > 0) {
      uint256 stakedBal = stakedBalance(); // Balance of gauge tokens by depositing curve LP tokens into the curve gauge
      if (stakedBal > 0) {
        // don't bother withdrawing if we don't have staked funds
        gauge.withdraw(Math.min(stakedBal, _debtOutstanding));
      }
      uint256 _withdrawnBal = balanceOfWant(); // Balance of curve LP token
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

  // Sell our CRV in Uniswap V3 for our `targetToken`, USDT or USDC
  function _sell(uint256 _amount) internal {
    // gets multi-hop path for uniswap v3 swaps
    bytes memory path = abi.encodePacked(
      address(crv),
      crvToWethSwapFee,
      wethAddress,
      wethToTargetSwapFee,
      targetTokenAddress
    );

    router.exactInput(
      ISwapRouter.ExactInputParams(
        path, // multi-hop path
        address(this),
        now,
        _amount,
        0 // amountOutMinimum
      )
    );
  }

  /* ========== VIEWS ========== */

  function name() external view override returns (string memory) {
    return stratName;
  }

  /* ========== SETTERS ========== */

  // These functions are useful for setting parameters of the strategy that may need to be adjusted.
  // Set optimal token to sell harvested funds for depositing to Curve.
  // Default is USDC, but can be set to USDT as needed by strategist or governance.
  function setTargetToken(uint256 _target) external onlyVaultManagers {
    require(_target == 0 || _target == 1); // dev: not a valid index => use 0: USDT 1: USDC

    if (_target == 1) {
      targetTokenAddress = address(usdc);
    } else {
      targetTokenAddress = address(usdt);
    }
  }

  function setSwapFees(uint24 _crvToWethSwapFee, uint24 _wethToTargetSwapFee)
    external
    onlyVaultManagers
  {
    require(_crvToWethSwapFee <= maxFee); // dev: fee is too high
    require(_wethToTargetSwapFee <= maxFee); // dev: fee is too high

    // Likely to be run when/if we change the target token
    crvToWethSwapFee = _crvToWethSwapFee;
    wethToTargetSwapFee = _wethToTargetSwapFee;
  }
}
