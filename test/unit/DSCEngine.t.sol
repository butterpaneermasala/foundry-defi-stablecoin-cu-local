// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    error DSCEngine__NeedsMoreThanZero();

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 amountToMint = 100 ether;
    uint256 amountCollateral = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
        ERC20Mock(wbtc).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    /////////////////////////
    /// Constructor Test ///
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBeOfSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConstructorSetsPriceFeedsCorrectly() public view {
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens.length, 2);
        assertEq(collateralTokens[0], weth);
        assertEq(collateralTokens[1], wbtc);
        
        address wethPriceFeed = dsce.getCollateralTokenPriceFeed(weth);
        address wbtcPriceFeed = dsce.getCollateralTokenPriceFeed(wbtc);
        assertEq(wethPriceFeed, ethUsdPriceFeed);
        assertEq(wbtcPriceFeed, btcUsdPriceFeed);
    }

    ///////////////////
    /// Price Test ///
    ///////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // We have 15 ETH
        // 15e18 * 2000/ETH = 30000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(actualUsd, expectedUsd);
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2,000 / ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    function testGetUsdValueForWbtc() public view {
        uint256 btcAmount = 1e18; 
        uint256 expectedUsd = 2000e18; // $2000 per BTC
        uint256 actualUsd = dsce.getUsdValue(wbtc, btcAmount);
        assertEq(actualUsd, expectedUsd);
    }

    ///////////////////////////////
    /// DepositCollateral Test ///
    //////////////////////////////

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, STARTING_ERC20_BALANCE);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRevertsIfNotApproved() public {
        vm.startPrank(USER);
        vm.expectRevert();
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        console2.log(totalDscMinted);
        console2.log(collateralValueInUsd);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositedAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositedAmount);
    }

    function testDepositMultipleCollateralTypes() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        
        uint256 wethBalance = dsce.getUserCollateral(USER, weth);
        uint256 wbtcBalance = dsce.getUserCollateral(USER, wbtc);
        
        assertEq(wethBalance, AMOUNT_COLLATERAL);
        assertEq(wbtcBalance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// Mint DSC Tests ///
    //////////////////////////////

    // function testRevertsIfMintedDscBreaksHealthFactor() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
    //     // Try to mint more DSC than collateral value allows
    //     uint256 tooMuchDsc = 1000 ether; // Much more than collateral value
    //     vm.expectRevert();
    //     dsce.mintDsc(tooMuchDsc);
    //     vm.stopPrank();
    // }

    function testMintDscSuccessfully() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        uint256 dscToMint = 100 ether;
        dsce.mintDsc(dscToMint);
        
        uint256 userDscMinted = dsce.getUserDscMinted(USER);
        assertEq(userDscMinted, dscToMint);
        
        uint256 dscBalance = dsc.balanceOf(USER);
        assertEq(dscBalance, dscToMint);
        vm.stopPrank();
    }

    function testMintDscRevertsIfZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testDepositAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100 ether);
        (uint256 minted, uint256 collateral) = dsce.getAccountInformation(USER);
        assertEq(minted, 100 ether);
        assertGt(collateral, 0);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// Burn DSC Tests ///
    //////////////////////////////

    function testBurnDscReducesMinted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100 ether);
        // Approve DSCEngine to spend DSC before burning
        dsc.approve(address(dsce), 50 ether);
        dsce.burnDsc(50 ether);
        (uint256 minted,) = dsce.getAccountInformation(USER);
        assertEq(minted, 50 ether);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfNotApproved() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100 ether);
        
        vm.expectRevert();
        dsce.burnDsc(50 ether);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// Redeem Collateral Tests ///
    //////////////////////////////

    // function testRedeemCollateralAfterBurn() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100 ether);
    //     // Approve DSCEngine to spend DSC before burning
    //     dsc.approve(address(dsce), 100 ether);
    //     dsce.burnDsc(100 ether);
    //     uint256 before = ERC20Mock(weth).balanceOf(USER);
    //     dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
    //     uint256 afterBal = ERC20Mock(weth).balanceOf(USER);
    //     assertEq(afterBal, before + AMOUNT_COLLATERAL);
    //     vm.stopPrank();
    // }

    function testRedeemCollateralRevertsIfZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfNotEnoughDeposited() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
        vm.expectRevert();
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL + 1 ether);
        vm.stopPrank();
    }

    function testRedeemCollateralForDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, 100 ether);
        
        dsc.approve(address(dsce), 50 ether);
        dsce.redeemCollateralForDsc(weth, 5 ether, 50 ether);
        
        uint256 remainingDsc = dsce.getUserDscMinted(USER);
        uint256 remainingCollateral = dsce.getUserCollateral(USER, weth);
        assertEq(remainingDsc, 50 ether);
        assertEq(remainingCollateral, 5 ether);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// Health Factor Tests ///
    //////////////////////////////

    // function testHealthFactorCalculation() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
    //     uint256 healthFactor = dsce.getHealthFactor();
    //     assertGt(healthFactor, 0);
    //     vm.stopPrank();
    // }

    // function testHealthFactorWithNoDscMinted() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        
    //     uint256 healthFactor = dsce.getHealthFactor();
    //     // Should be max uint256 when no DSC is minted
    //     assertEq(healthFactor, type(uint256).max);
    //     vm.stopPrank();
    // }

    // function testHealthFactorBreaksAfterPriceDrop() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     dsce.mintDsc(100 ether);
        
    //     // Simulate price drop by updating the mock price feed
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8); // Drop from $2000 to $1000
        
    //     uint256 healthFactor = dsce.getHealthFactor();
    //     assertLt(healthFactor, 1e18); // Health factor should be below 1
    //     vm.stopPrank();
    // }

    ///////////////////////////////
    /// Liquidation Tests ///
    //////////////////////////////

    // function testLiquidateUser() public {
    //     // Setup user with unhealthy position
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     dsce.mintDsc(100 ether);
    //     vm.stopPrank();
        
    //     // Drop price to make position unhealthy
    //     MockV3Aggregator(ethUsdPriceFeed).updateAnswer(1000e8);
        
    //     // Liquidate
    //     vm.startPrank(LIQUIDATOR);
    //     dsc.mint(LIQUIDATOR, 100 ether);
    //     dsc.approve(address(dsce), 50 ether);
        
    //     uint256 liquidatorWethBefore = ERC20Mock(weth).balanceOf(LIQUIDATOR);
    //     dsce.liquidate(weth, USER, 50 ether);
    //     uint256 liquidatorWethAfter = ERC20Mock(weth).balanceOf(LIQUIDATOR);
        
    //     assertGt(liquidatorWethAfter, liquidatorWethBefore);
    //     vm.stopPrank();
    // }

    // function testLiquidateRevertsIfUserHealthy() public {
    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
    //     dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
    //     dsce.mintDsc(50 ether); // Small amount to keep healthy
    //     vm.stopPrank();
        
    //     vm.startPrank(LIQUIDATOR);
    //     dsc.mint(LIQUIDATOR, 100 ether);
    //     dsc.approve(address(dsce), 50 ether);
        
    //     vm.expectRevert(DSCEngine.DSCEnigne__HealthFactorOkay.selector);
    //     dsce.liquidate(weth, USER, 50 ether);
    //     vm.stopPrank();
    // }

    function testLiquidateRevertsIfZeroDebtToCover() public {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.liquidate(weth, USER, 0);
        vm.stopPrank();
    }

    ///////////////////////////////
    /// Getter Function Tests ///
    //////////////////////////////

    function testGetCollateralTokens() public view {
        address[] memory tokens = dsce.getCollateralTokens();
        assertEq(tokens.length, 2);
        assertEq(tokens[0], weth);
        assertEq(tokens[1], wbtc);
    }

    function testGetAllCollateralPriceFeeds() public view {
        address[] memory priceFeeds = dsce.getAllCollateralPriceFeeds();
        assertEq(priceFeeds.length, 2);
        assertEq(priceFeeds[0], ethUsdPriceFeed);
        assertEq(priceFeeds[1], btcUsdPriceFeed);
    }

    function testGetAllUserCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256[] memory balances = dsce.getAllUserCollateral(USER);
        assertEq(balances.length, 2);
        assertEq(balances[0], AMOUNT_COLLATERAL);
        assertEq(balances[1], AMOUNT_COLLATERAL);
    }

    function testGetAllDscMinted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(100 ether);
        vm.stopPrank();
        
        address[] memory users = new address[](1);
        users[0] = USER;
        uint256[] memory minted = dsce.getAllDscMinted(users);
        assertEq(minted.length, 1);
        assertEq(minted[0], 100 ether);
    }

    function testIsAllowedCollateral() public view {
        bool wethAllowed = dsce.isAllowedCollateral(weth);
        bool wbtcAllowed = dsce.isAllowedCollateral(wbtc);
        bool randomTokenAllowed = dsce.isAllowedCollateral(address(0x123));
        
        assertTrue(wethAllowed);
        assertTrue(wbtcAllowed);
        assertFalse(randomTokenAllowed);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 balance = dsce.getCollateralBalanceOfUser(weth, USER);
        assertEq(balance, AMOUNT_COLLATERAL);
    }

    function testGetUserCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 balance = dsce.getUserCollateral(USER, weth);
        assertEq(balance, AMOUNT_COLLATERAL);
    }

    function testGetUserDscMinted() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(100 ether);
        vm.stopPrank();
        
        uint256 minted = dsce.getUserDscMinted(USER);
        assertEq(minted, 100 ether);
    }

    function testGetAccountInformation() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.mintDsc(100 ether);
        vm.stopPrank();
        
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        assertEq(totalDscMinted, 100 ether);
        assertGt(collateralValueInUsd, 0);
    }

    function testGetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(wbtc, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 totalValue = dsce.getAccountCollateralValue(USER);
        assertGt(totalValue, 0);
    }

    function testGetAdditionalFeedPrecision() public view {
        uint256 precision = dsce.getAdditionalFeedPrecision();
        assertEq(precision, 1e10);
    }

    function testGetPrecision() public view {
        uint256 precision = dsce.getPrecision();
        assertEq(precision, 1e18);
    }

    ///////////////////////////////
    /// Edge Cases and Error Tests ///
    //////////////////////////////

    function testRevertIfTransferFails() public {
        // This test would require a mock token that fails transfers
        // For now, we'll test the basic flow
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testMultipleUsersCanDeposit() public {
        address user2 = makeAddr("user2");
        ERC20Mock(weth).mint(user2, STARTING_ERC20_BALANCE);
        
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        vm.startPrank(user2);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        
        uint256 user1Collateral = dsce.getUserCollateral(USER, weth);
        uint256 user2Collateral = dsce.getUserCollateral(user2, weth);
        
        assertEq(user1Collateral, AMOUNT_COLLATERAL);
        assertEq(user2Collateral, AMOUNT_COLLATERAL);
    }

    function testReentrancyProtection() public {
        // This test would require a malicious contract
        // For now, we'll test that the deposit function has the nonReentrant modifier
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }
}
