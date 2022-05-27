from warnings import warn
from brownie import chain


def test_gauge_is_properly_setup(gauge, geist):

    assert (
        gauge.reward_count() == 1
    ), "We only currently expect 1 third-party reward token (i.e. GEIST)"

    reward_tokens = []

    for i in range(gauge.reward_count()):
        reward_tokens.append(gauge.reward_tokens(i))

    assert geist.address in reward_tokens

    WEEK = 86400 * 7

    weeksNum = chain.time() // WEEK

    # Pull current inflation_rate and verify it's not 0; i.e., the
    # reward APY is greater than 0%.
    # if gauge.inflation_rate(weeksNum) > 0:
    #     warn("This gauge is not currently rewarding any CRV")

    assert (
        gauge.inflation_rate(weeksNum) > 0
    ), "This gauge is not currently rewarding any CRV"
