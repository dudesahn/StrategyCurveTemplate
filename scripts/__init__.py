from brownie import network

activeNetwork = network.show_active()

assert "arb" in activeNetwork, f"Strategy meant to be deployed to Arbitrum only."
