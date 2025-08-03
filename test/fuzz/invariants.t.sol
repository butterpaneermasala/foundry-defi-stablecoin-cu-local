// SPDX-License-Indentifier: MIT

// Have our invarinants aka properties that hold true all the time

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view function should never revert <- evergreen invariant

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {console2} from "forge-std/console2.sol";
import {Handler} from "./Handler.t.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Invariant is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }
    // function setUp() external {
    //     deployer = new DeployDSC();
    //     (dsc, dsce, config) = deployer.run();
    //     (,,weth, wbtc, ) = config.activeNetworkConfig();
    //     targetContract(address(dsce));
    // }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        // get the value of all the collateral in the protocol
        // compare it to all debt (dsc)
        //
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);
        console2.log(wethValue);
        console2.log(wethValue);
        console2.log(totalSupply);
        console2.log("Times Mint Called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_ProtocolTotalSupplyLessThanCollateralValue() external view returns (bool) {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("totalSupply: ", totalSupply);
        console.log("wethValue: ", wethValue);
        console.log("wbtcValue: ", wbtcValue);
        console.log("Times Mint Called: ", handler.timesMintIsCalled());
        assert(totalSupply <= wethValue + wbtcValue);
    }
}
