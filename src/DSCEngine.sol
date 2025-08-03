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
import {OracleLib} from "./libraries/OracleLib.sol";

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
    error DSCEnigne__HealthFactorOkay();
    error DSCEnigne__HealthFactorNotImproved();

    ///////////////////
    // types //
    ///////////////////

    using OracleLib for AggregatorV3Interface;

    ///////////////////
    // State Variables //
    ///////////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // this means a 10% bonus

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    // this mapping maps the token address to the their pricefeeds so whenever someone wants to deposit collateral they will be able to deposit the ONLY the tokens that are set here
    // we will set these address in our constructor

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc; // Address of the dsc

    ///////////////////
    // Events //
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed reedemedFrom, address redeemedTo, address indexed token, uint256 amount);

    ///////////////////
    // Modifiers //
    ///////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedTokens(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

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
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
        // NOTE: DecentralizedStableCoin(dscAddress) means it is type casting, it is casting the "dscAddress" to type DecentralizedStableCoin
    }

    ///////////////////
    // External Functions //
    ///////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDscToMint The amount of decentraclized stablecoin to mint
     * @notice this function will deposit your collateral and mint DSC in
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI (check, effet, interact)
     * @param tokenCollateralAddress The address of the token that is to deposit as collateral
     * @param amountCollateral The which is to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    /**
     *
     * @param tokenCollateralAddress the token address of deposited collateral
     * @param amountCollateral the amount of collateral want to redeem
     * @param amountDscToBurn the amount of DSC user wants to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks health factor
    }

    // In order to redeem collateral:
    // 1. Health factor must be over 1 AFTER collateral pulled
    // DRY: don't repeat yourself

    // CEI: check, effects interaction
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    // raw redeemCollateral is troublesome
    // $100 ETH -> $20 DSC
    // 100 (break)
    // 1. burn DSC
    // 2. redeem ETH
    // SO FOR THAT we will create a burnDSC function so we can first burn then redeem DSC

    /**
     * @notice follows CEI
     * @param amountDscToMint The amount to DSC the user wants to mint
     * @notice They must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
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

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit..
    }

    // $100 ETH -> $40 ETH
    // $50 DSC
    // imagine the user deposits $100 amount of ETH and minted $50 DSC but then the price of ETH that they have deposited tanks to -> $40, then we are under collateralized as $40 < $50, so the user should get liquidated. They should not be allowed to hold the position of $50 anymore.
    // so ideally a threshold is set to kick? user/ liquidate users if their desposited collateral is close the amount of DSC they hold
    // The liquidate() function in our contarct helps other users call the function to remove peoples position to save the protocol.

    // $75 backing $50 backing and pays off the $50 DSC
    // If someone is almost undercollateralized, we will pay you to liquidate them!

    /**
     *
     * @param tokenCollateralAddress The erc20 collateral address to liquidate from the user
     * @param user the user who has broken the health factor. Their _healthFactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The Amount of DSC the user wants to burn to improve the users health factor
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 1005 or less collateralized, then we wouldn't be able to incentive the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *
     * Follows CEI: Checks, Effectis, Interactions
     */
    function liquidate(address tokenCollateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
    {
        // need to check health factor of the users
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEnigne__HealthFactorOkay();
        }

        // We want to burn their DSC "debt"
        // ANd take their collateral
        // Bad User: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC == ??? ETH ? How much eth is that??
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);

        // And give them 10% bonus
        // So we are giving the liquidator $110 of WETH for 100 DSC
        // We should impliment a feature in the event the protocol is insolvent
        // And sweep extra amount into a treasury

        // 0.05 ETH * .1 = 0.005. Getting 0.055
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(tokenCollateralAddress, totalCollateralToRedeem, user, msg.sender);
        // we need to burn the DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEnigne__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

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
    /**
     * @notice Returns the health factor of the caller
     * @return healthFactor The health factor of the caller
     */
    function getHealthFactor() external view returns (uint256 healthFactor) {
        healthFactor = _healthFactor(msg.sender);
    }

    /**
     * @notice Returns the amount of a specific collateral token deposited by a user
     * @param user The address of the user
     * @param token The address of the collateral token
     * @return The amount of collateral deposited
     */
    function getUserCollateral(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     * @notice Returns the amount of DSC minted by a user
     * @param user The address of the user
     * @return The amount of DSC minted
     */
    function getUserDscMinted(address user) external view returns (uint256) {
        return s_DscMinted[user];
    }

    /**
     * @notice Returns the list of allowed collateral tokens
     */
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    ////////////////////////////////////////
    // Private & Internal View Functions //
    ////////////////////////////////////////

    /**
     * @notice Returns all price feed addresses for the allowed collateral tokens
     */
    function getAllCollateralPriceFeeds() external view returns (address[] memory priceFeeds) {
        uint256 len = s_collateralTokens.length;
        priceFeeds = new address[](len);
        for (uint256 i = 0; i < len; i++) {
            priceFeeds[i] = s_priceFeeds[s_collateralTokens[i]];
        }
    }

    /**
     * @notice Returns all collateral balances for a user (parallel to getCollateralTokens)
     */
    function getAllUserCollateral(address user) external view returns (uint256[] memory balances) {
        uint256 len = s_collateralTokens.length;
        balances = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            balances[i] = s_collateralDeposited[user][s_collateralTokens[i]];
        }
    }

    /**
     * @notice Returns all DSC minted by all users (for test/analysis purposes)
     */
    function getAllDscMinted(address[] calldata users) external view returns (uint256[] memory minted) {
        uint256 len = users.length;
        minted = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            minted[i] = s_DscMinted[users[i]];
        }
    }

    /**
     * @notice Returns true if the token is allowed as collateral
     */
    function isAllowedCollateral(address token) external view returns (bool) {
        return s_priceFeeds[token] != address(0);
    }

    /**
     *
     * @dev Low-Level Internal function, do not call unless the function calling it is checking for health factor being broken
     */
    function _burnDsc(uint256 amountDscToBunr, address onBehakfOf, address dscFrom) private {
        s_DscMinted[onBehakfOf] -= amountDscToBunr;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBunr);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBunr);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * @notice Returns how close to liquidation a user is
     * @param user the user
     * if a user get below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
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

    function _calculateHeathFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * 1e18) / totalDscMinted;
    }

    ////////////////////////////////////////
    // Public & External View Functions //
    ////////////////////////////////////////
    /**
     * @notice Returns the collateral balance of a user for a given token
     */
    function getCollateralBalanceOfUser(address token, address user) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
    /**
     * @notice Returns the price feed address for a given collateral token
     * @param token The address of the collateral token
     * @return The address of the price feed
     */

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // Price of ETH (token)
        // $/ETH ETH ??
        // $2000 / ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // ($10e18 * 1e18) / ($2000e8 * 1e10)
        // 0.00500000000000000

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        // loop through each collateral token, get the amount they have deposited, and map it to the pice, to get the USD value
        // uint256 totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // 1 ETH = $1000
        // The returned vlaue from CL will be 1000 * 1e8
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }
}
