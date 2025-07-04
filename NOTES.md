1. What term describes the value that can be captured by blockchain operators through strategic inclusion, exclusion, or reordering of transactions?

ans: Maximal Extractable Value (MEV)

why/what?:
    -> In simple terms Maximal Extractable Value (MEV) is the extra profit made by controlling the order of transaction on a blockchain.
    -> reordering, inseting, and censoring transactions within a block.
    ->  Reorder them (put the most profitable ones first),

        Insert your own (front-run someone), or

        Censor others (keep them out if they interfere with your strategy).
    -> types of MEV:
        Front-running: Insert a transaction before a known profitable one (e.g., DEX trade).

        Back-running: Insert a transaction after a profitable one (e.g., liquidity arbitrage).

        Sandwich attacks: Place one transaction before and one after a user's trade to profit from price slippage.

        Liquidation sniping: Beat others to profitable liquidation opportunities on lending protocols.

        Time-bandit attacks (on PoW): Reorganize previous blocks to capture MEV.

    MORE: https://chatgpt.com/share/6864b510-5758-8004-997e-1c31276cb0ab

2. What is a common metric used by platforms like DeFi Llama to measure the size and popularity of DeFi protocols?

ans : Total Value Locked (TVL)

explanation: The amount of assets currently deposited in a DeFi protocol

3. Which advanced testing technique checks if fundamental properties and rules of a smart contract system hold true across various interactions and state changes?

ans: Invariant testing

what is Invariant testing? :
    Invariant => Conditions
    An Invariant is something that should never break

4. In the context of stablecoin collateral, what is the key difference between exogenous and endogenous types?

10. When designing functions that interact with external contracts, why is it generally safer to update the calling contract's internal state *before* making the external call?

4. If a protocol uses a `LIQUIDATION_THRESHOLD` constant set to 50 alongside a `LIQUIDATION_PRECISION` of 100, what minimum over-collateralization ratio does this imply for a user's position to be considered safe (Health Factor >= 1)?


