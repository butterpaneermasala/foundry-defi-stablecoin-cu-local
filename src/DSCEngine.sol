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

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    // errors //
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEnigne_BreaksHealthFactor(uint256);
    error DSCEngine__DscNotMinted();

    ///////////////////
    // State Variables //
    ///////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;



    mapping(address token => address priceFeed) private s_priceFeed; // tokenToPriceFeed
    // this mapping maps the token address to the their pricefeeds so whenever someone wants to deposit collateral they will be able to deposit the ONLY the tokens that are set here
    // we will set these address in our constructor

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc; // Address of the dsc

    ///////////////////
    // Events //
    ///////////////////
    event CollateralDeposited(address, address, uint256);

    ///////////////////
    // Modifiers //
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedTokens(address tokenAddress) {
        if (s_priceFeed[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    function depositeCollateralAndMintDsc() external {}

    ///////////////////
    // Functions //
    ///////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // We will be using USD price feed ofc as our dsc is backed by USD
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength();
        }
        // For example ETH/USD, BTC/USD etc
        for (uint64 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeed[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
        // NOTE: DecentralizedStableCoin(dscAddress) means it is type casting, it is casting the "dscAddress" to type DecentralizedStableCoin
    }

    ///////////////////
    // External Functions //
    ///////////////////

    /**
     * @notice follows CEI (check, effet, interact)
     * @param tokenCollateralAddress The address of the token that is to deposit as collateral
     * @param amountCollateral The which is to deposit
     */
    function despositeCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedTokens(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        // IERC20 is the interface of ERC20 token, it lets u check balanceOf and transfer etc. it returns a boolen indicating if the tranfer was a success or fail
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}
    

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount to DSC the user wants to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) 
        external 
        moreThanZero(amountDscToMint) 
        nonReentrant 
    {
        // To Let the user mint DSC we need to check couple of things first
        // 1. The deposited collateral value > DSC amount they want to mint
        s_DscMinted[msg.sender] += amountDscToMint;
        // If they minted too much, revert => ($150 DSC,$100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__DscNotMinted();
        }
    }

    function burnDsc() external {}

    // $100 ETH -> $40 ETH
    // $50 DSC
    // imagine the user deposits $100 amount of ETH and minted $50 DSC but then the price of ETH that they have deposited tanks to -> $40, then we are under collateralized as $40 < $50, so the user should get liquidated. They should not be allowed to hold the position of $50 anymore.
    // so ideally a threshold is set to kick? user/ liquidate users if their desposited collateral is close the amount of DSC they hold
    // The liquidate() function in our contarct helps other users call the function to remove peoples position to save the protocol.

    function liquidate() external {}

    // The getHealthFactor() function lets user view peoples Health Factor
    /*
    Health Factor: 
        Imagine the user deposits $100 worth of ETH and mints $50 worth of DSC
        so if the threshold amount is set to 150% then at any point of time the users deposited ETH value should be >= 150% the minted DSC.
        In this case if the user has minted $50 worth of DSC then the collaterized ETH they have should be of value >= $75. or they will get liquidated. 
        so the getHealthFactor gets us the Health Index which shows if the user is healthy in the system or no.
        ** If the user deposited ETH value >= threshold % of their minted DSC, they are healthy, otherwise they are unhealthy. And if they are unhealthy then any user can liquidate the unhealthy user to save the system/ make profit. Liquidate here means that other user will pay the system the DSC and get all the ETH the under collateralized user has in return.

        example:
            ->user deposited $100 amount of ETH
            ->and minted $50 DSC
            -> threshold in the system is set to 150%, so here threshold is for the user is $75 DSC
            -> rn the user's ETH value is > $100 so they are healthy
            -> user's collateralized ETH thats id of $100 tanks to $74!!!! NOW THE USER IS UNDER COLLATERALIZED
            -> other user sees it and pays the $50 DSC can gets the $74 ETH from the under collateralized user. makes profit of $24? yes?
    */
    function getHealthFactor() external view {}

    ////////////////////////////////////////
    // Private & Internal View Functions //
    ////////////////////////////////////////

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidation a user is
     * @param user the user
     * if a user get below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns(uint256) {
        // totak DSC minted
        // total collateral VAULE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION / totalDscMinted); // if this is less than 1 then the user can get liquidated
    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. Cheack health factor (do they have enough collateral ??)
        // 2. Revert if they dont have a good health factor

        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEnigne_BreaksHealthFactor(userHealthFactor);
        }
    }

    ////////////////////////////////////////
    // Public & External View Functions //
    ////////////////////////////////////////

    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to the pice, to get the USD value
        // uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);

        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeed[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        // 1 ETH = $1000
        // The returned vlaue from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
