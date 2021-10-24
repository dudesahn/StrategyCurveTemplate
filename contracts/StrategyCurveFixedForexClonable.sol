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
import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

// these are the libraries to use with synthetix
import "./interfaces/synthetix.sol";

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

interface IUniV3 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

abstract contract StrategyCurveBase is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */
    // these should stay the same across different wants.

    // curve infrastructure contracts
    ICurveStrategyProxy public proxy; // Below we set it to Yearn's Updated v4 StrategyProxy
    ICurveFi public curve; // Curve Pool, need this for depositing into our curve pool
    address public gauge; // Curve gauge contract, most are tokenized, held by Yearn's voter

    // keepCRV stuff
    uint256 public keepCRV; // the percentage of CRV we re-lock for boost (in basis points)
    uint256 internal constant FEE_DENOMINATOR = 10000; // this means all of our fee values are in bips
    address public constant voter = 0xF147b8125d2ef93FB6965Db97D6746952a133934; // Yearn's veCRV voter

    // swap stuff
    address internal constant sushiswap =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // default to sushiswap, more CRV liquidity there
    address[] public crvPath;

    IERC20 internal constant crv =
        IERC20(0xD533a949740bb3306d119CC777fa900bA034cd52);
    IERC20 internal constant weth =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

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
}

contract StrategyCurveFixedForexClonable is StrategyCurveBase {
    /* ========== STATE VARIABLES ========== */
    // these will likely change across different wants.

    // synthetix stuff
    IReadProxy public sTokenProxy; // this is the proxy for our synthetix token
    IERC20 internal constant sethProxy =
        IERC20(0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb); // this is the proxy for sETH
    IReadProxy internal constant readProxy =
        IReadProxy(0x4E3b31eB0E5CB73641EE1E65E7dCEFe520bA3ef2);

    ISystemStatus internal constant systemStatus =
        ISystemStatus(0x1c86B3CDF2a60Ae3a574f7f71d44E2C50BDdB87E); // this is how we check if our market is closed

    bytes32 public synthCurrencyKey;
    bytes32 internal constant sethCurrencyKey = "sETH";

    bytes32 internal constant TRACKING_CODE = "YEARN"; // this is our referral code for SNX volume incentives
    bytes32 internal constant CONTRACT_SYNTHETIX = "Synthetix";
    bytes32 internal constant CONTRACT_EXCHANGER = "Exchanger";

    // swap stuff
    address internal constant uniswapv3 =
        address(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    bool public sellOnSushi; // determine if we sell partially on sushi or all on Uni v3
    bool internal harvestNow; // this tells us if we're currently harvesting or tending
    uint24 public uniCrvFee; // this is equal to 1%, can change this later if a different path becomes more optimal
    uint256 public lastTendTime; // this is the timestamp that our last tend was called
    uint256 public maxGasPrice; // this is the max gas price we want our keepers to pay for harvests/tends in gwei

    // check for cloning
    bool internal isOriginal = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        address _curvePool,
        address _gauge,
        address _sTokenProxy,
        string memory _name
    ) public StrategyCurveBase(_vault) {
        _initializeStrat(_curvePool, _gauge, _sTokenProxy, _name);
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // we use this to clone our original strategy to other vaults
    function cloneCurveibFF(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _curvePool,
        address _gauge,
        address _sTokenProxy,
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

        StrategyCurveFixedForexClonable(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _curvePool,
            _gauge,
            _sTokenProxy,
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
        address _sTokenProxy,
        string memory _name
    ) public {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_curvePool, _gauge, _sTokenProxy, _name);
    }

    // this is called by our original strategy, as well as any clones
    function _initializeStrat(
        address _curvePool,
        address _gauge,
        address _sTokenProxy,
        string memory _name
    ) internal {
        // You can set these parameters on deployment to whatever you want
        maxReportDelay = 7 days; // 7 days in seconds
        debtThreshold = 5 * 1e18; // we shouldn't ever have debt, but set a bit of a buffer
        profitFactor = 1_000_000; // in this strategy, profitFactor is only used for telling keep3rs when to move funds from vault to strategy
        healthCheck = 0xDDCea799fF1699e98EDF118e0629A974Df7DF012; // health.ychad.eth

        // need to set our proxy again when cloning since it's not a constant
        proxy = ICurveStrategyProxy(0xA420A63BbEFfbda3B147d0585F1852C358e2C152);

        // these are our standard approvals for swaps. want = Curve LP token
        want.approve(address(proxy), type(uint256).max);
        crv.approve(sushiswap, type(uint256).max);
        crv.approve(uniswapv3, type(uint256).max);
        weth.approve(uniswapv3, type(uint256).max);

        // set our keepCRV
        keepCRV = 1000;

        // set our fee for univ3 pool
        uniCrvFee = 10000;

        // this is the pool specific to this vault, used for depositing
        curve = ICurveFi(_curvePool);

        // set our curve gauge contract
        gauge = address(_gauge);

        // set our strategy's name
        stratName = _name;

        // start off using sushi
        sellOnSushi = true;

        // set our token to swap for and deposit with
        sTokenProxy = IReadProxy(_sTokenProxy);

        // these are our approvals and path specific to this contract
        sTokenProxy.approve(address(curve), type(uint256).max);

        // crv token path
        crvPath = [address(crv), address(weth)];

        // set our synth currency key
        synthCurrencyKey = ISynth(IReadProxy(_sTokenProxy).target())
            .currencyKey();

        // set our last tend time to the deployment block
        lastTendTime = block.timestamp;

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
        // turn on our toggle for harvests
        harvestNow = true;

        // deposit our sToken to Curve if we have any and if our trade has finalized
        uint256 _sTokenProxyBalance = sTokenProxy.balanceOf(address(this));
        if (_sTokenProxyBalance > 0 && checkWaitingPeriod()) {
            curve.add_liquidity([0, _sTokenProxyBalance], 0);
        }

        // debtOustanding will only be > 0 in the event of revoking or if we need to rebalance from a withdrawal or lowering the debtRatio
        if (_debtOutstanding > 0) {
            uint256 _stakedBal = stakedBalance();
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
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }
        if (harvestNow) {
            // this is a part of a harvest call
            // Send all of our LP tokens to the proxy and deposit to the gauge if we have any
            uint256 _toInvest = balanceOfWant();
            if (_toInvest > 0) {
                want.safeTransfer(address(proxy), _toInvest);
                proxy.deposit(gauge, address(want));
            }
            // we're done with our harvest, so we turn our toggle back to false
            harvestNow = false;
        } else {
            // this is our tend call
            claimAndSell();

            // update our variable for tracking last tend time
            lastTendTime = block.timestamp;
        }
    }

    // sell from CRV into WETH via sushiswap, then sell WETH for sETH on Uni v3
    function _sellOnSushiFirst(uint256 _amount) internal {
        IUniswapV2Router02(sushiswap).swapExactTokensForTokens(
            _amount,
            uint256(0),
            crvPath,
            address(this),
            block.timestamp
        );

        uint256 _wethBalance = weth.balanceOf(address(this));
        IUniV3(uniswapv3).exactInput(
            IUniV3.ExactInputParams(
                abi.encodePacked(
                    address(weth),
                    uint24(500),
                    address(sethProxy)
                ),
                address(this),
                block.timestamp,
                _wethBalance,
                uint256(1)
            )
        );
    }

    // Sells our CRV for sETH all on uni v3
    function _sellOnUniOnly(uint256 _amount) internal {
        IUniV3(uniswapv3).exactInput(
            IUniV3.ExactInputParams(
                abi.encodePacked(
                    address(crv),
                    uint24(uniCrvFee),
                    address(weth),
                    uint24(500),
                    address(sethProxy)
                ),
                address(this),
                block.timestamp,
                _amount,
                uint256(1)
            )
        );
    }

    function prepareMigration(address _newStrategy) internal override {
        uint256 _stakedBal = stakedBalance();
        if (_stakedBal > 0) {
            proxy.withdraw(gauge, address(want), _stakedBal);
        }
        sethProxy.safeTransfer(
            _newStrategy,
            sethProxy.balanceOf(address(this))
        );
    }

    /* ========== KEEP3RS ========== */

    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        // check if the 5-minute lock has elapsed yet
        if (!checkWaitingPeriod()) {
            return false;
        }

        // check if the base fee gas price is higher than we allow
        if (readBaseFee() > maxGasPrice) {
            return false;
        }

        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        return super.harvestTrigger(callCostinEth);
    }

    function tendTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        // check if the base fee gas price is higher than we allow
        if (readBaseFee() > maxGasPrice) {
            return false;
        }

        // Should trigger if hasn't been called in a while. Running this based on harvest even though this is a tend call since a harvest should run ~5 mins after every tend.
        if (block.timestamp.sub(lastTendTime) >= maxReportDelay) return true;
    }

    // convert our keeper's eth cost into want (not applicable, and synths are a pain to swap for, so we removed it)
    function ethToWant(uint256 _ethAmount)
        public
        view
        override
        returns (uint256)
    {
        return _ethAmount;
    }

    function readBaseFee() internal view returns (uint256 baseFee) {
        IBaseFee _baseFeeOracle =
            IBaseFee(0xf8d0Ec04e94296773cE20eFbeeA82e76220cD549);
        return _baseFeeOracle.basefee_global();
    }

    /* ========== SYNTHETIX ========== */

    // claim and swap our CRV for synths
    function claimAndSell() internal {
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
                if (_sendToVoter > 0) {
                    crv.safeTransfer(voter, _sendToVoter);
                }
                uint256 _crvRemainder = _crvBalance.sub(_sendToVoter);

                // sell the rest of our CRV for sETH
                if (_crvRemainder > 0) {
                    if (sellOnSushi) {
                        _sellOnSushiFirst(_crvRemainder);
                    } else {
                        _sellOnUniOnly(_crvRemainder);
                    }
                }

                // check our output balance of sETH
                uint256 _sEthBalance = sethProxy.balanceOf(address(this));

                // swap our sETH for our underlying synth if the forex markets are open
                if (!isMarketClosed()) {
                    // this check allows us to still tend even if forex markets are closed.
                    exchangeSEthToSynth(_sEthBalance);
                }
            }
        }
    }

    function exchangeSEthToSynth(uint256 amount) internal returns (uint256) {
        // swap amount of sETH for Synth
        if (amount == 0) {
            return 0;
        }

        return
            _synthetix().exchangeWithTracking(
                sethCurrencyKey,
                amount,
                synthCurrencyKey,
                address(this),
                TRACKING_CODE
            );
    }

    function _synthetix() internal view returns (ISynthetix) {
        return ISynthetix(resolver().getAddress(CONTRACT_SYNTHETIX));
    }

    function resolver() internal view returns (IAddressResolver) {
        return IAddressResolver(readProxy.target());
    }

    function _exchanger() internal view returns (IExchanger) {
        return IExchanger(resolver().getAddress(CONTRACT_EXCHANGER));
    }

    function checkWaitingPeriod() internal view returns (bool freeToMove) {
        return
            // check if it's been >5 mins since we traded our sETH for our synth
            _exchanger().maxSecsLeftInWaitingPeriod(
                address(this),
                synthCurrencyKey
            ) == 0;
    }

    function isMarketClosed() public view returns (bool) {
        // set up our arrays to use
        bool[] memory tradingSuspended;
        bytes32[] memory synthArray;

        // use our synth key
        synthArray = new bytes32[](1);
        synthArray[0] = synthCurrencyKey;

        // check if trading is open or not. true = market is closed
        (tradingSuspended, ) = systemStatus.getSynthExchangeSuspensions(
            synthArray
        );
        return tradingSuspended[0];
    }

    /* ========== SETTERS ========== */

    // set the maximum gas price we want to pay for a harvest/tend in gwei
    function setGasPrice(uint256 _maxGasPrice) external onlyAuthorized {
        maxGasPrice = _maxGasPrice.mul(1e9);
    }

    // set the fee pool we'd like to swap through for if we're swapping CRV on UniV3
    function setUniCrvFee(uint24 _fee) external onlyAuthorized {
        uniCrvFee = _fee;
    }

    // set if we want to sell our swap partly on sushi or just uniV3
    function setSellOnSushi(bool _sellOnSushi) external onlyAuthorized {
        sellOnSushi = _sellOnSushi;
    }
}
