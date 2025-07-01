// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

/**
 * @title DSCEngine
 * @author Satya Pradhan
 * The systen is designed to be minimal as possible, and ahve the tokens manitain a 1 oken == $1 peg.
 * This StableCoin similar to DAI if DAI had no governacne, no fees and was backed by WETH and WBTC.
 *
 * Our DSC sysyten should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all DSC.
 * @notice This contract is the core of the DSC system. It handles all the logic for mining and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very loosly based on MakerDAO (DAI) system.
 */
contract DSCEngine {
    function depositeCollateralAndMintDsc() external {}

    function despositeCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    // $100 ETH -> $40 ETH
    // $50 DSC
    // imagine the user deposits $100 amount of ETH and minted $50 DSC but then the price of ETH that they have deposited tanks to -> $40, then we are under collateralized as $40 < $50, so the user should get liquidated. They should not be allowed to hold the position of $50 anymore.
    // so ideally a threshold is set to kick? user/ liquidate users if their desposited collateral is close the amount of DSC they hold
    // The liquidate() function in our contarct helps other users call the function to remove peoples position to save the protocol.

    function liquidate() external {}

    // The getHealthFactor() function lets user view peoples Heath Factor
    /*
    Health Factor: 
        Imagine the user deposits $100 worth of ETH and mints $50 worth of DSC
        so if the threshold amount is set to 150% then at any point of time the users deposited ETH value should be >= 150% the minted DSC.
        In this case if the user has minted $50 worth of DSC then the collaterized ETH they have should be of value >= $75. or they will get liquidated. 
        so the getHealthFactor gets us the Heath Index which shows if the user is heatlty in the system or no.
        ** If the user deposited ETH value >= threshold % of their minted DSC, they are healthy, otherwise they are unhealthy. And if they are unhealthy then any user can liquidate the unhealthy user to save the system/ make profit. Liquidate here means that other user will pay the system the DSC and get all the ETH the under collaterized user has in return.

        example:
            ->user deposited $100 amount of ETH
            ->and minted $50 DSC
            -> threshold in the system is set to 150%, so here threshold is for the user is $75 DSC
            -> rn the user's ETH value is > $100 so they are healthy
            -> user's collateralized ETH thats id of $100 tanks to $74!!!! NOW THE USER IS UNDER COLLATERALIZED
            -> other user sees it and pays the $50 DSC can gets the $74 ETH from the under collateralized user. makes profit of $24? yes?
    */
    function getHealthFactor() external view {}
}
