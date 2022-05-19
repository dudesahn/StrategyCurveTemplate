from brownie import chain


def test_gauge_is_properly_setup(gauge):

    assert (
        gauge.reward_count() == 0
    ), "Third-party reward tokens not expected for this strategy"

    WEEK = 86400 * 7

    weeksNum = chain.time() // WEEK

    # Pull current inflation_rate and verify it's not 0; i.e., the
    # reward APY is greater than 0%.
    assert (
        gauge.inflation_rate(weeksNum) is not 0
    ), "This gauge is not currently rewarding any CRV"
