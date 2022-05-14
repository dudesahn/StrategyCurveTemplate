from brownie import interface


def getSnapshot(vault, strategy):
    # gets a snapshot of the accounting and key params of the vault and strategy
    print(f"\033[93m{'='*75}\033[0m")
    getVaultSnapshot(vault, strategy)
    getStrategySnapshot(strategy)
    print(f"\033[93m{'='*75}\033[0m")


def getStrategySnapshot(strategy):
    target = interface.ERC20(strategy.targetTokenAddress())
    want = interface.ERC20(strategy.want())
    crv = interface.ERC20(strategy.crv())
    gauge = interface.ICurveGauge(strategy.gauge())
    gaugeToken = interface.ERC20(strategy.gauge())
    vault = interface.VaultAPI(strategy.vault())

    print("#######################################################")
    print(f"Strategy: {strategy.name()} ########################")
    print("#######################################################\n")

    print(
        f"""
                   Vault: {vault.name()} ({vault.symbol()})
   Strategy Total Assets: {strategy.estimatedTotalAssets()} ({want.symbol()}) 
       Strategy Balances:
                        Want: {strategy.balanceOfWant()} ({want.symbol()})
                Target Token: {target.balanceOf(strategy)} ({target.symbol()})
                         CRV: {crv.balanceOf(strategy)} ({crv.symbol()})
               Claimable CRV: {gauge.claimable_reward.call(strategy, crv,{"from": 
strategy})} ({crv.symbol()})
                 Gauge Token: {strategy.stakedBalance()} ({gaugeToken.symbol()})
       Gauge CRV Balance: {crv.balanceOf(gaugeToken)} ({crv.symbol()})
        Credit Threshold: {strategy.creditThreshold()}
          Debt Threshold: {strategy.debtThreshold()}
        Delegated Assets: {strategy.delegatedAssets()}
  Strategy Profit Factor: {strategy.profitFactor()}
        \n"""
    )


def getVaultSnapshot(vault, strategy):

    want = interface.ERC20(strategy.want())
    rewardsAddress = strategy.rewards()

    print("#######################################################")
    print(f"Vault:  {vault.name()} ({vault.symbol()}) ##########################")
    print("#######################################################\n")

    print(
        f"""
             Total Assets: {vault.totalAssets()} ({want.symbol()})
               Free Funds: {(vault.pricePerShare() * vault.totalSupply() / 10 ** 18):.0f}
   Borrowed by Strategies: {vault.totalDebt()} ({want.symbol()})
         Credit Available: {vault.creditAvailable()} ({want.symbol()})
         Debt Outstanding: {vault.debtOutstanding()} ({want.symbol()})
               Debt Ratio: {vault.debtRatio()}\n
          Expected Return: {vault.expectedReturn()}
       Time-locked Profit: {vault.lockedProfit()}
Locked Profit Degradation: {vault.lockedProfitDegradation()}
     Total Fees Collected: 
                        Yearn: {vault.balanceOf(rewardsAddress)} ({vault.symbol()})
                     Strategy: {vault.balanceOf(strategy)} ({vault.symbol()})
           \n
            Deposit Limit: {vault.depositLimit()}
  Deposit Limit Available: {vault.availableDepositLimit()}\n
             Total Supply: {vault.totalSupply()}
     Max Available Shares: {vault.maxAvailableShares()}
          Price per Share: {vault.pricePerShare()}
  Last Report (timestamp): {vault.lastReport()}\n
           Management Fee: {vault.managementFee()}
          Performance Fee: {vault.performanceFee()}
                 Balances:
                         Want: {want.balanceOf(vault)} ({want.symbol()})
                 Vault Shares: {vault.balanceOf(vault)} ({vault.symbol()})
        \n"""
    )
