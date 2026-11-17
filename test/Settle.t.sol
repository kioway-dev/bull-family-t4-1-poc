// SPDX-License-Identifier: MIT
// Bull Family — direct-settle (EIP-712 seller consent) fork tests, Robinhood Chain 4663.
// Forks mainnet at the pinned block; actors are throwaways funded with vm.deal on
// the fork only. No real funds move anywhere.
// Run: forge test --match-contract SettleForkTest -vv
pragma solidity ^0.8.0;

import "./SettleTxs.sol";

interface Vm2 {
    function prank(address) external;
    function deal(address, uint256) external;
    function warp(uint256) external;
    function createFork(string calldata, uint256) external returns (uint256);
    function selectFork(uint256) external;
    function store(address, bytes32, bytes32) external;
    function load(address, bytes32) external returns (bytes32);
}

Vm2 constant vm2 = Vm2(address(uint160(uint256(keccak256("hevm cheat code")))));

contract SettleForkTest {
    address constant ESCROW = 0xd961cA37e339E14e0D3478383a252E218fe7aa4a;
    address constant BURNER = 0x1B3b7abb6553a1bbc9B285E6ab3F2012e88e4d5f;
    address constant BULL = 0x30768B5482e5dd8a2487cE0BE61E01fA03Af37ff;
    address constant BUYER = 0x44C3291a37804173d1de8219D67110B964Ac5302;
    address constant SELLER = 0xEaF052B8Cb85251E60B43Ab6986dfA16fF6A3105;
    address constant OTHER = 0x1111111111111111111111111111111111111111;

    bytes4 constant SEL_CREATE = 0xaaf5e2be;
    bytes4 constant SEL_FUND_PAYMENT = 0x20bb1ab7;
    bytes4 constant SEL_FUND_TOKENS = 0xfff1939c;

    event LogStr(string key, uint256 val);
    event LogAddr(string key, address val);

    function setUp() public {
        uint256 forkId = vm2.createFork("https://rpc.mainnet.chain.robinhood.com", 116262502);
        vm2.selectFork(forkId);
        vm2.deal(address(this), 300 ether);
        vm2.deal(BUYER, 300 ether);
    }

    struct Deal {
        address buyer;
        address seller;
        address sellToken;
        uint256 sellAmount;
        address payToken;
        uint256 payAmount;
        uint64 deadline;
        bool buyerFunded;
        bool sellerFunded;
        uint8 status;
        address sellerPayout;
        address buyerReceive;
        uint16 feeBps;
    }

    function _deal(uint256 id) internal view returns (Deal memory d) {
        (bool ok, bytes memory ret) = ESCROW.staticcall(abi.encodeWithSelector(bytes4(0x03988f84), id));
        require(ok, "deals() failed");
        d = abi.decode(ret, (Deal));
    }

    function _create(bytes memory data, address from) internal returns (bool) {
        vm2.prank(from);
        (bool ok,) = ESCROW.call{value: 0}(data);
        return ok;
    }

    // ---- S1: happy path: createDeal stores exactly the consented terms ----
    function testCreateDealHappyPath() public {
        require(_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "createDeal must succeed");
        Deal memory d = _deal(3);
        require(d.buyer == BUYER, "buyer mismatch");
        require(d.seller == SELLER, "seller mismatch");
        require(d.sellToken == BULL, "sellToken mismatch");
        require(d.sellAmount == 1000 ether, "sellAmount mismatch");
        require(d.payToken == address(0), "payToken must be ETH");
        require(d.payAmount == 0.01 ether, "payAmount mismatch");
        require(d.deadline == 1794970758, "deadline mismatch");
        require(!d.buyerFunded && !d.sellerFunded, "nothing funded yet");
        require(d.status == 1, "status must be 1 (open)");
        require(d.sellerPayout == SELLER, "sellerPayout zero resolves to seller");
        require(d.buyerReceive == BUYER, "buyerReceive zero resolves to buyer");
        require(d.feeBps == 250, "feeBps must be 250");
    }

    // ---- S2: same consent cannot open a second deal (replay) ----
    function testConsentReplayReverts() public {
        require(_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "first createDeal must succeed");
        require(!_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "replay of the same consent MUST revert");
    }

    // ---- S3: consent expired (past validUntil) ----
    function testExpiredConsentReverts() public {
        vm2.warp(SettleTxs.VALID_UNTIL + 1);
        require(!_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "createDeal past validUntil MUST revert");
    }

    // ---- S4: fee quote expired ----
    function testExpiredFeeQuoteReverts() public {
        vm2.warp(SettleTxs.QUOTE_EXPIRES + 1);
        require(!_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "createDeal past fee-quote expiry MUST revert");
    }

    // ---- S5: single-word tampers of the consented terms all revert ----
    function testTamperedTermsRevert() public {
        require(!_create(SettleTxs.TAMPER_PAYAMOUNT_DATA, BUYER), "lower payAmount MUST revert");
        require(!_create(SettleTxs.TAMPER_SELLAMOUNT_DATA, BUYER), "higher sellAmount MUST revert");
        require(!_create(SettleTxs.TAMPER_PAYOUT_DATA, BUYER), "redirected sellerPayout MUST revert");
        require(!_create(SettleTxs.TAMPER_RECEIVE_DATA, BUYER), "redirected buyerReceive MUST revert");
        require(!_create(SettleTxs.TAMPER_DEADLINE_DATA, BUYER), "changed deadline MUST revert");
        require(!_create(SettleTxs.TAMPER_VALIDUNTIL_DATA, BUYER), "changed validUntil MUST revert");
        require(!_create(SettleTxs.TAMPER_FEEBPS_DATA, BUYER), "changed feeBps MUST revert");
        require(!_create(SettleTxs.TAMPER_FEEEXPIRY_DATA, BUYER), "expired fee quote MUST revert");
        require(!_create(SettleTxs.TAMPER_SELLER_DATA, BUYER), "changed seller MUST revert");
    }

    // ---- S6: a different buyer cannot use the seller's consent ----
    function testWrongBuyerReverts() public {
        require(!_create(SettleTxs.CREATE_DEAL_DATA, OTHER), "createDeal from a non-buyer MUST revert");
    }

    // ---- S7: full settlement end-to-end ----
    function testFullSettlement() public {
        require(_create(SettleTxs.CREATE_DEAL_DATA, BUYER), "createDeal must succeed");
        // give the seller 1000 BULL on the fork (find the balances slot by trial)
        _fundSellerBull(1000 ether);
        // buyer funds 0.01 ETH
        vm2.prank(BUYER);
        (bool okPay,) = ESCROW.call{value: 0.01 ether}(abi.encodeWithSelector(SEL_FUND_PAYMENT, uint256(3)));
        require(okPay, "buyer fundPayment must succeed");
        Deal memory d1 = _deal(3);
        require(d1.buyerFunded && !d1.sellerFunded, "buyer funded, seller not yet");
        require(d1.status == 1, "still open after first funding");
        // seller approves + funds tokens
        vm2.prank(SELLER);
        (bool okAppr,) = BULL.call(abi.encodeWithSelector(bytes4(0x095ea7b3), ESCROW, 1000 ether));
        require(okAppr, "seller approve must succeed");
        uint256 sellerEthBefore = SELLER.balance;
        uint256 buyerBullBefore = _bullBalance(BUYER);
        vm2.prank(SELLER);
        (bool okFund,) = ESCROW.call(abi.encodeWithSelector(SEL_FUND_TOKENS, uint256(3)));
        require(okFund, "seller fundTokens must succeed (swap settles here)");
        Deal memory d2 = _deal(3);
        require(d2.buyerFunded && d2.sellerFunded, "both funded");
        require(d2.status == 2, "status must be 2 (settled)");
        require(_bullBalance(BUYER) - buyerBullBefore == 1000 ether, "buyer must receive 1000 BULL");
        uint256 sellerGot = SELLER.balance - sellerEthBefore;
        emit LogStr("seller_received_wei", sellerGot);
        require(sellerGot == 0.00975 ether, "seller must receive payAmount minus 2.5% fee");
        require(ESCROW.balance == 0, "escrow must hold no ETH after settlement");
    }

    function _bullBalance(address who) internal view returns (uint256) {
        (bool ok, bytes memory ret) = BULL.staticcall(abi.encodeWithSelector(bytes4(0x70a08231), who));
        require(ok, "balanceOf failed");
        return abi.decode(ret, (uint256));
    }

    function _fundSellerBull(uint256 amount) internal {
        // Try balance-mapping slots 0..5: store amount, check balanceOf.
        for (uint256 s = 0; s < 6; s++) {
            bytes32 slot = keccak256(abi.encode(SELLER, s));
            vm2.store(BULL, slot, bytes32(amount));
            if (_bullBalance(SELLER) == amount) {
                emit LogStr("bull_balance_slot", s);
                return;
            }
            vm2.store(BULL, slot, bytes32(0));
        }
        revert("could not find BULL balance slot");
    }
}
