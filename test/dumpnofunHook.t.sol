// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {dumpnofunHook, SimpleERC20Token, TokenParams} from "../src/dumpnofunHook.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

contract dumpnofunHookTest is Test, Deployers {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    dumpnofunHook myHook;

    function setUp() public {
    // Deploy v4-core
    deployFreshManagerAndRouters();

    // Deploy, mint tokens, and approve all periphery contracts for two tokens
    deployMintAndApprove2Currencies();

    address hookAddress = address(
        uint160(
            Hooks.BEFORE_INITIALIZE_FLAG
        )
    );
    deployCodeTo("dumpnofunHook", abi.encode(manager), hookAddress);
    myHook = dumpnofunHook(hookAddress);
    }


    function testTokenCreation() public {
        SimpleERC20Token token = new SimpleERC20Token("GatorCoin", "GC", 6, 1000);

        assertTrue(token.totalSupply() == 1000000000, "Token incorrect supply.");
        assertTrue(keccak256(abi.encodePacked(token.symbol())) == keccak256(abi.encodePacked("GC")), "Token incorrect symbol.");

    }

    function testPoolCreation() public {
        PoolKey memory key = myHook.deployPool(TokenParams("GatorCoin", "GC", 6, 1000));

        console.log("The address is:", Currency.unwrap(key.currency0));
        
        // Assert that the pool is initialized
        assertTrue(Currency.unwrap(key.currency0) == address(0), "Pool does not have ETH as first asset.");
        
        // This isn't a real test... how do I check if the pool is initialized without running a real function e.g., swap??
    }

    function testRevert() public {
        Currency USDC = Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        Currency ETH = Currency.wrap(address(0));
        PoolKey memory key = PoolKey(ETH, USDC, 3000, 60, myHook);
        vm.expectRevert();
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
    }

}
