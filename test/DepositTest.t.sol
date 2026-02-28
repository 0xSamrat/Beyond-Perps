// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PerpRouter} from "../src/core/PerpRouter.sol";
import {AccountManager} from "../src/core/AccountManager.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPerpRouter} from "../src/interfaces/IPerpRouter.sol";

contract DepositTest is Test {
    // Mainnet addresses
    address constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    PerpRouter public router;
    AccountManager public accountManager;
    
    address public operator;
    uint256 public operatorKey;
    
    address public depositor;
    uint256 public depositorKey;
    
    // Type hashes
    string constant DEPOSIT_INTENT_TYPE = "DepositIntent(uint256 nonce,uint256 deadline)";
    bytes32 constant DEPOSIT_INTENT_TYPEHASH = keccak256(bytes(DEPOSIT_INTENT_TYPE));
    
    string constant DEPOSIT_PERMIT2_WITNESS_TYPE = 
        "DepositIntent witness)"
        "DepositIntent(uint256 nonce,uint256 deadline)"
        "TokenPermissions(address token,uint256 amount)";
    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("https://eth-mainnet.g.alchemy.com/v2/1tIakfFgf_rg5Cf2G0-Bh");
        
        // Setup accounts
        operatorKey = 0xa10d44b7ecc35c119c9ea915b6a955426b349c1d3042fcaaede8efa6f65d7d97;
        operator = vm.addr(operatorKey);
        
        // Use a fresh EOA that has no code on mainnet
        depositorKey = 0x9a98fa99ec75cc4af91c81419ee77e06f6df5c5644e1a5d702c560a18c8bde64;
        depositor = vm.addr(depositorKey);
        
        // Deploy contracts
        vm.startPrank(operator);
        
        accountManager = new AccountManager(operator, operator);
        router = new PerpRouter(PERMIT2, USDC, operator, operator);
        
        // Configure
        router.setAccountManager(address(accountManager));
        accountManager.setPerpRouter(address(router));
        
        vm.stopPrank();
        
        // Deal USDC to depositor
        deal(USDC, depositor, 100_000e6);
        
        // Approve Permit2 from depositor
        vm.prank(depositor);
        IERC20(USDC).approve(PERMIT2, type(uint256).max);
        
        console2.log("Router:", address(router));
        console2.log("AccountManager:", address(accountManager));
        console2.log("Operator:", operator);
        console2.log("Depositor:", depositor);
        console2.log("Depositor USDC:", IERC20(USDC).balanceOf(depositor));
    }
    
    function testDepositWithPermit2() public {
        uint256 amount = 10_000e6;
        uint256 deadline = block.timestamp + 3600;
        uint256 permitNonce = 12345;
        uint256 intentNonce = 12346;
        
        // Build permit and intent
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({
                token: USDC,
                amount: amount
            }),
            nonce: permitNonce,
            deadline: deadline
        });
        
        IPerpRouter.DepositIntent memory intent = IPerpRouter.DepositIntent({
            nonce: intentNonce,
            deadline: deadline
        });
        
        // Compute witness hash (what PerpRouter does internally)
        bytes32 witness = keccak256(abi.encode(
            DEPOSIT_INTENT_TYPEHASH,
            intent.nonce,
            intent.deadline
        ));
        
        console2.log("Witness hash:", vm.toString(witness));
        
        // Sign the permit with witness
        bytes memory signature = _signPermitWithWitness(
            depositorKey,
            permit,
            witness,
            address(router)
        );
        
        console2.log("Signature length:", signature.length);
        console2.log("Signature:", vm.toString(signature));
        
        // Build deposit struct
        IPerpRouter.Deposit memory deposit = IPerpRouter.Deposit({
            depositor: depositor,
            permit: permit,
            intent: intent,
            signature: signature
        });
        
        // Execute as operator
        vm.prank(operator);
        
        IPerpRouter.Deposit[] memory deposits = new IPerpRouter.Deposit[](1);
        deposits[0] = deposit;
        
        router.depositBatch(deposits);
        
        // Check balance
        uint256 collateral = accountManager.getCollateral(depositor);
        console2.log("Depositor collateral after:", collateral);
        
        assertEq(collateral, amount, "Collateral should equal deposit amount");
    }
    
    function _signPermitWithWitness(
        uint256 privateKey,
        ISignatureTransfer.PermitTransferFrom memory permit,
        bytes32 witness,
        address spender
    ) internal view returns (bytes memory) {
        // Get Permit2 domain separator
        bytes32 domainSeparator = ISignatureTransfer(PERMIT2).DOMAIN_SEPARATOR();
        
        // Build the full type hash
        bytes32 typeHash = keccak256(abi.encodePacked(
            "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,",
            DEPOSIT_PERMIT2_WITNESS_TYPE
        ));
        
        console2.log("Type hash:", vm.toString(typeHash));
        
        // Hash token permissions
        bytes32 tokenPermissionsHash = keccak256(abi.encode(
            keccak256("TokenPermissions(address token,uint256 amount)"),
            permit.permitted.token,
            permit.permitted.amount
        ));
        
        console2.log("Token permissions hash:", vm.toString(tokenPermissionsHash));
        
        // Build struct hash
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            tokenPermissionsHash,
            spender,
            permit.nonce,
            permit.deadline,
            witness
        ));
        
        console2.log("Struct hash:", vm.toString(structHash));
        
        // Build digest
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));
        
        console2.log("Digest:", vm.toString(digest));
        
        // Sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        
        return abi.encodePacked(r, s, v);
    }
}
