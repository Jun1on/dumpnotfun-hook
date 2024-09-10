pragma solidity ^0.8.0;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {Test} from "forge-std/Test.sol";

import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {PoolManager} from "v4-core/PoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {LPFeeLibrary} from "v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

contract dumpnofunHook is BaseHook {
    using CurrencyLibrary for Currency;

    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    bytes constant ZERO_BYTES = new bytes(0);
    IPoolManager manager;

    // Initialize BaseHook parent contract in the constructor
    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        manager = _poolManager;
    }

    // Required override function for BaseHook to let the PoolManager know which hooks are implemented
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: true,
                afterInitialize: false,
                beforeAddLiquidity: false,
                beforeRemoveLiquidity: false,
                afterAddLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata
    ) external pure override returns (bytes4) {
        console.log("Entered Before Initialize");
        revert();
    }

    function deployPool(
        TokenParams calldata params
    ) external returns (PoolKey memory) {
        SimpleERC20Token token = new SimpleERC20Token(
            params.name,
            params.symbol,
            params.decimals,
            params.totalSupply
        );
        //      Currency USDC = Currency.wrap(address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48));
        Currency ETH = Currency.wrap(address(0));
        PoolKey memory key = PoolKey(
            ETH,
            Currency.wrap(address(token)),
            3000,
            60,
            this
        );
        manager.initialize(key, SQRT_PRICE_1_1, ZERO_BYTES);
        return key;
    }
}

struct TokenParams {
    string name; // Token name
    string symbol; // Token symbol
    uint8 decimals; // Token decimal places
    uint256 totalSupply; // Total supply of the token
}

contract SimpleERC20Token {
    string public name; // Token name
    string public symbol; // Token symbol
    uint8 public decimals; // Token decimal places
    uint256 public totalSupply; // Total supply of the token

    mapping(address => uint256) private balances; // Mapping of address to balance
    mapping(address => mapping(address => uint256)) private allowances; // Allowance mapping

    // Events as per the ERC-20 standard
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    // Constructor to set the token details and mint initial supply to the deployer
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _initialSupply * 10 ** uint256(decimals); // Set total supply with decimals
        balances[msg.sender] = totalSupply; // Assign the entire supply to the deployer
        emit Transfer(address(0), msg.sender, totalSupply); // Emit transfer event from zero address to deployer
    }

    // Function to check the balance of an address
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    // Function to transfer tokens to another address
    function transfer(address to, uint256 amount) public returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            balances[msg.sender] >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        balances[msg.sender] -= amount; // Deduct from sender
        balances[to] += amount; // Add to recipient

        emit Transfer(msg.sender, to, amount); // Emit Transfer event
        return true;
    }

    // Function to approve another address to spend tokens on behalf of the caller
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances[msg.sender][spender] = amount; // Set allowance

        emit Approval(msg.sender, spender, amount); // Emit Approval event
        return true;
    }

    // Function to check the allowance of a spender on behalf of an owner
    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return allowances[owner][spender];
    }

    // Function to transfer tokens on behalf of another address (using allowance)
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(
            balances[from] >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        require(
            allowances[from][msg.sender] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );

        balances[from] -= amount; // Deduct from the owner
        balances[to] += amount; // Add to the recipient
        allowances[from][msg.sender] -= amount; // Reduce the allowance

        emit Transfer(from, to, amount); // Emit Transfer event
        return true;
    }
}
