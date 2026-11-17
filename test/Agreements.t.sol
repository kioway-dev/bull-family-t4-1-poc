// SPDX-License-Identifier: MIT
// Bull Family — Agreements contract fork tests (Robinhood Chain 4663).
// Forks mainnet at a pinned block; all actors are throwaway addresses funded
// with vm.deal on the fork only. No real funds move anywhere.
// Run: forge test --fork-url https://rpc.mainnet.chain.robinhood.com -vv
pragma solidity ^0.8.0;

import "./ApiTxs.sol";

interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;
    function deal(address, uint256) external;
    function warp(uint256) external;
    function expectRevert() external;
    function createFork(string calldata, uint256) external returns (uint256);
    function selectFork(uint256) external;
    function load(address, bytes32) external returns (bytes32);
}

Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

struct Cond {
    uint8 kind;
    address target;
    bytes data;
    uint256 value;
}
struct P {
    address payee;
    address asset;
    uint256 amount;
    uint64 expiry;
    bytes32 termsHash;
    Cond[] conditions;
}
struct Q {
    uint256 feeWei;
    uint64 expiry;
    bytes sig;
}

contract MockCall {
    uint256 public v;
    function get() external view returns (uint256) {
        return v;
    }
    function set(uint256 x) external {
        v = x;
    }
}

contract AgreementsForkTest {
    address constant AGR = 0x84C6D5dAf99BC65ed3A1D26Ca88ffa834D143999;
    address constant BURNER = 0x1B3b7abb6553a1bbc9B285E6ab3F2012e88e4d5f;
    address constant ESCROW = 0xd961cA37e339E14e0D3478383a252E218fe7aa4a;
    address constant USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    address constant PAYER = 0x44C3291a37804173d1de8219D67110B964Ac5302;
    address constant PAYEE = 0xcFBD6F0F824e8148B902edC08DED2084EC201E44;
    address constant ARB = 0xDa72D03FAe4661d45826e9c80807CFAc35e15688;
    address constant OTHER = 0x1111111111111111111111111111111111111111;

    bytes4 constant SEL_CREATE = 0x8952f925;
    bytes4 constant SEL_RELEASE = 0x37bdc99b;
    bytes4 constant SEL_REFUND = 0x278ecde1;
    bytes4 constant SEL_ATTEST = 0xa3bb24cc;
    bytes4 constant SEL_VOTE = 0xb384abef;
    bytes4 constant SEL_OBJECT = 0xac30e880;

    MockCall mock;
    uint256 forkId;

    event LogStr(string key, uint256 val);
    event LogAddr(string key, address val);

    function setUp() public {
        // Pinned block 116262502 (timestamp ~17948838xx, before Q1 expiry 1794887453).
        forkId = vm.createFork("https://rpc.mainnet.chain.robinhood.com", 116262502);
        vm.selectFork(forkId);
        mock = new MockCall();
        vm.deal(address(this), 300 ether);
        vm.deal(PAYER, 300 ether);
    }

    // ---- helpers ----
    function _create(bytes memory data, uint256 value, address from) internal returns (uint256 id, bool ok) {
        vm.prank(from);
        (ok,) = AGR.call{value: value}(data);
        if (ok) id = _nextId() - 1;
    }

    function _nextId() internal view returns (uint256) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0x61b8ce8c)));
        require(ok, "nextId failed");
        return abi.decode(ret, (uint256));
    }

    function _agreement(uint256 id)
        internal
        view
        returns (address payer, address payee, address asset, uint256 amount, uint64 expiry, uint8 status, bytes32 termsHash)
    {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0xd5a7420d), id));
        require(ok, "agreement() failed");
        (payer, payee, asset, amount, expiry, status, termsHash) = abi.decode(ret, (address, address, address, uint256, uint64, uint8, bytes32));
    }

    function _conditions(uint256 id) internal view returns (Cond[] memory) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0x3c5da3e1), id));
        require(ok, "conditions() failed");
        return abi.decode(ret, (Cond[]));
    }

    function _met(uint256 id) internal view returns (bool[] memory) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0x7bfa56d0), id));
        require(ok, "met() failed");
        return abi.decode(ret, (bool[]));
    }

    // attested(id, idx) returns a uint256 flag: 0 = not attested, 1 = attested.
    function _attested(uint256 id, uint256 idx) internal view returns (uint256) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0x1845a4af), id, idx));
        require(ok, "attested() failed");
        return abi.decode(ret, (uint256));
    }

    function _votes(uint256 id, uint256 idx) internal view returns (uint256) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(bytes4(0xc6e36a32), id, idx));
        require(ok, "votes() failed");
        return abi.decode(ret, (uint256));
    }

    function _release(uint256 id, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_RELEASE, id));
        return ok;
    }

    function _refund(uint256 id, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_REFUND, id));
        return ok;
    }

    function _attest(uint256 id, uint256 idx, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_ATTEST, id, idx));
        return ok;
    }

    function _vote(uint256 id, uint256 idx, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_VOTE, id, idx));
        return ok;
    }

    function _object(uint256 id, uint256 idx, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_OBJECT, id, idx));
        return ok;
    }

    function _craft(
        address payee,
        uint256 amount,
        uint64 expiry,
        Cond[] memory conds,
        uint256 feeWei,
        uint64 qExpiry,
        bytes memory sig
    ) internal pure returns (bytes memory) {
        P memory p = P({payee: payee, asset: address(0), amount: amount, expiry: expiry, termsHash: bytes32(0), conditions: conds});
        Q memory q = Q({feeWei: feeWei, expiry: qExpiry, sig: sig});
        return abi.encodeWithSelector(SEL_CREATE, p, q);
    }

    function _oneAttestCond() internal pure returns (Cond[] memory c) {
        c = new Cond[](1);
        c[0] = Cond({kind: 1, target: ARB, data: "", value: 0});
    }

    // ---- T1: API encoding fidelity ----
    function testEncodingFidelity() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        (address payer, address payee, address asset, uint256 amount, uint64 expiry, uint8 status, bytes32 termsHash) = _agreement(id);
        require(payer == PAYER, "payer mismatch");
        require(payee == PAYEE, "payee mismatch");
        require(asset == address(0), "asset mismatch");
        require(amount == 0.001 ether, "amount mismatch");
        require(expiry == ApiTxs.CREATE1_P_EXPIRY, "expiry mismatch");
        require(status == 1, "status should be 1 (open)");
        require(termsHash == ApiTxs.CREATE1_TERMSHASH, "termsHash mismatch");
        Cond[] memory cs = _conditions(id);
        require(cs.length == 2, "want 2 conditions");
        require(cs[0].kind == 1 && cs[0].target == ARB && cs[0].value == 0, "attest cond mismatch");
        require(cs[1].kind == 0 && cs[1].target == address(0) && cs[1].value == ApiTxs.CREATE1_TIMEAFTER, "time_after cond mismatch");
        bool[] memory m = _met(id);
        require(m.length == 2 && !m[0] && !m[1], "both unmet at creation");
    }

    // ---- T2: release before conditions reverts ----
    function testReleaseBeforeConditionsReverts() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(!_release(id, OTHER), "release before conditions MUST revert");
    }

    // ---- T3: release after time only (no attest) reverts ----
    function testReleaseAfterTimeOnlyReverts() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        vm.warp(block.timestamp + 3700);
        require(!_release(id, OTHER), "release with attest missing MUST revert");
        require(!_met(id)[0], "attest still unmet");
        require(_met(id)[1], "time_after now met");
    }

    // ---- T4: attest by wrong wallet reverts ----
    function testAttestWrongWalletReverts() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(!_attest(id, 0, PAYEE), "payee attest MUST revert");
        require(!_attest(id, 0, PAYER), "payer attest MUST revert");
        require(!_attest(id, 0, OTHER), "random attest MUST revert");
        require(_attested(id, 0) == 0, "attested flag must stay 0");
    }

    // ---- T5: attest by arbiter + time -> release pays payee ----
    function testAttestThenRelease() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(_attest(id, 0, ARB), "arbiter attest must succeed");
        require(_attested(id, 0) == 1, "attested flag must be 1 after arbiter attests");
        require(!_release(id, OTHER), "release before time MUST revert");
        vm.warp(block.timestamp + 3700);
        uint256 before = PAYEE.balance;
        require(_release(id, OTHER), "release after all true must succeed");
        require(PAYEE.balance - before == 0.001 ether, "payee must receive 0.001 ETH");
        (, , , , , uint8 status, ) = _agreement(id);
        require(status == 2, "status must be 2 (released)");
        require(!_refund(id, PAYER), "refund after release MUST revert");
    }

    // ---- T6: refund before expiry reverts; after expiry refunds payer ----
    function testRefundBeforeExpiryReverts() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(!_refund(id, OTHER), "refund before expiry MUST revert");
        require(!_refund(id, PAYER), "refund by payer before expiry MUST revert");
    }

    function testRefundAfterExpiry() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        vm.warp(ApiTxs.CREATE1_P_EXPIRY + 1);
        uint256 before = PAYER.balance;
        require(_refund(id, OTHER), "refund after expiry must succeed");
        require(PAYER.balance - before == 0.001 ether, "payer must be refunded 0.001 ETH");
        (, , , , , uint8 status, ) = _agreement(id);
        require(status == 3, "status must be 3 (refunded)");
    }

    // ---- T7: payer == payee self-agreement: API accepts it, contract rejects it ----
    function testSelfAgreementCreation() public {
        vm.prank(PAYER);
        (bool ok,) = AGR.call{value: ApiTxs.CREATE_SELF_VALUE}(ApiTxs.CREATE_SELF_DATA);
        require(!ok, "contract MUST reject payer==payee (BadInput)");
    }

    // ---- T8: fee quote replay across different terms: contract must reject ----
    function testFeeQuoteReplayAcrossTerms() public {
        // Fresh quote for a 0.001 ETH agreement, reused for a 100 ETH agreement.
        Cond[] memory conds = _oneAttestCond();
        bytes memory data = _craft(PAYEE, 100 ether, uint64(block.timestamp + 72 hours), conds, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool ok,) = AGR.call{value: 100 ether + ApiTxs.Q1_FEEWEI}(data);
        require(!ok, "replayed fee quote for different terms MUST revert (BadQuote)");
    }

    // ---- T9: tampered feeWei with same sig reverts ----
    function testTamperedFeeWeiReverts() public {
        Cond[] memory conds = _oneAttestCond();
        bytes memory data = _craft(PAYEE, 0.001 ether, uint64(block.timestamp + 72 hours), conds, ApiTxs.Q1_FEEWEI + 1, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool ok,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI + 1}(data);
        require(!ok, "tampered feeWei with original sig MUST revert");
    }

    // ---- T10: no-fee value reverts ----
    function testNoFeeValueReverts() public {
        Cond[] memory conds = _oneAttestCond();
        bytes memory data = _craft(PAYEE, 0.001 ether, uint64(block.timestamp + 72 hours), conds, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool ok,) = AGR.call{value: 0.001 ether}(data);
        require(!ok, "value without fee MUST revert");
    }

    // ---- T11: expired fee quote reverts ----
    function testExpiredQuoteReverts() public {
        vm.warp(ApiTxs.Q1_EXPIRY + 1);
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(!ok, "expired quote MUST revert");
        id;
    }

    // ---- T12: quorum flow + double vote ----
    function testQuorumFlow() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_QUORUM_DATA, ApiTxs.CREATE_QUORUM_VALUE, PAYER);
        require(ok, "create quorum failed");
        require(!_release(id, OTHER), "release with 0 votes MUST revert");
        require(_vote(id, 0, ARB), "arbiter vote must succeed");
        require(_votes(id, 0) == 1, "1 vote recorded");
        require(!_vote(id, 0, ARB), "double vote MUST revert");
        require(_votes(id, 0) == 1, "still 1 vote after double-vote attempt");
        require(!_release(id, OTHER), "release with 1/2 votes MUST revert");
        require(_vote(id, 0, PAYEE), "second vote must succeed");
        require(_votes(id, 0) == 2, "2 votes recorded");
        require(_release(id, OTHER), "release with 2/2 votes must succeed");
    }

    // ---- T13: unless flow (two SEPARATE fee quotes: quotes are single-use) ----
    function testUnlessFlow() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_UNLESS_DATA, ApiTxs.CREATE_UNLESS_VALUE, PAYER);
        require(ok, "create unless failed");
        (uint256 id2, bool ok2) = _create(ApiTxs.CREATE_UNLESS2_DATA, ApiTxs.CREATE_UNLESS2_VALUE, PAYER);
        require(ok2, "create unless #2 failed (separate quote for identical terms)");
        require(!_release(id, OTHER), "release before window MUST revert");
        require(!_object(id, 0, PAYEE), "objection by non-objector MUST revert");
        require(_object(id, 0, ARB), "objection by named objector must succeed");
        vm.warp(block.timestamp + 25 hours);
        require(!_release(id, OTHER), "release after objection MUST revert");
        require(_release(id2, OTHER), "release after window without objection must succeed");
    }

    // ---- T14: deal_settled. v3 deal 1 is OPEN (not settled) on mainnet, so release must revert.
    // A positive case needs a settled v3 deal; see the settle-flow E2E (Settle.t.sol).
    function testDealSettled() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_DEAL_DATA, ApiTxs.CREATE_DEAL_VALUE, PAYER);
        require(ok, "create deal_settled failed");
        require(!_met(id)[0], "deal_settled must be unmet while v3 deal 1 is open");
        require(!_release(id, OTHER), "release with unsettled deal MUST revert");
    }

    // ---- T15/T16: call_gte hold via the keeper's poke() (see T22 for the full finding).
    // The hold clock starts when poke(id, idx) is called while the condition is true.
    bytes4 constant SEL_POKE = 0x8029e7c0;
    bytes4 constant SEL_SINCE = 0x791f219a;

    function _poke(uint256 id, uint256 idx, address from) internal returns (bool) {
        vm.prank(from);
        (bool ok,) = AGR.call(abi.encodeWithSelector(SEL_POKE, id, idx));
        return ok;
    }

    function _since(uint256 id, uint256 idx) internal view returns (uint256) {
        (bool ok, bytes memory ret) = AGR.staticcall(abi.encodeWithSelector(SEL_SINCE, id, idx));
        require(ok, "since() failed");
        return abi.decode(ret, (uint256));
    }

    function testCallGteHold() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_CALLGTE_MOCK_DATA, ApiTxs.CREATE_CALLGTE_MOCK_VALUE, PAYER);
        require(ok, "create call_gte failed");
        require(!_release(id, OTHER), "release with value 0 MUST revert");
        mock.set(100);
        require(!_release(id, OTHER), "release before any poke MUST revert");
        require(_poke(id, 0, OTHER), "poke must succeed");
        require(_since(id, 0) == block.timestamp, "poke records the current time");
        vm.warp(block.timestamp + 599);
        require(!_release(id, OTHER), "release at 599s hold MUST revert");
        vm.warp(block.timestamp + 2);
        require(_release(id, OTHER), "release after 601s hold must succeed");
    }

    function testCallGteHoldResets() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_CALLGTE_MOCK_DATA, ApiTxs.CREATE_CALLGTE_MOCK_VALUE, PAYER);
        require(ok, "create call_gte failed");
        mock.set(100);
        require(_poke(id, 0, OTHER), "poke must succeed");
        uint256 s0 = _since(id, 0);
        vm.warp(block.timestamp + 100);
        require(_poke(id, 0, OTHER), "second poke must succeed");
        require(_since(id, 0) == s0, "second poke must NOT reset the clock");
        vm.warp(block.timestamp + 501);
        require(_release(id, OTHER), "release 601s after the FIRST poke must succeed");
    }

    // ---- T16: fee destination + claim() probe ----
    function testFeeGoesToBurner() public {
        uint256 burnerBefore = BURNER.balance;
        uint256 agrBefore = AGR.balance;
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        id;
        require(BURNER.balance - burnerBefore == ApiTxs.Q1_FEEWEI, "fee must be forwarded to burner on creation");
        require(AGR.balance - agrBefore == 0.001 ether, "agreement must hold exactly the amount");
    }

    function testClaimProbe() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        id;
        vm.prank(OTHER);
        (bool okClaim, bytes memory ret) = AGR.call(abi.encodeWithSelector(bytes4(0x4e71d92d)));
        emit LogStr("claim_by_random_ok", okClaim ? 1 : 0);
        emit LogStr("claim_ret_len", ret.length);
        vm.prank(BURNER);
        (bool okClaim2,) = AGR.call(abi.encodeWithSelector(bytes4(0x4e71d92d)));
        emit LogStr("claim_by_burner_ok", okClaim2 ? 1 : 0);
    }

    // ---- T22 (TOP FINDING): poke() is permissionless and the 10-minute hold is NOT
    // continuous. Docs: a call condition "must stay true for 10 minutes, Bull's keeper
    // records it". On-chain, ANYONE can poke the moment the condition blips true, and
    // release() then only checks (heldSince set >= 600s ago) + (currently true).
    // A condition true for 1 second, false for 10 minutes, true again at release
    // time releases the funds — the documented stay-true rule is not enforced.
    function testPokeIsPermissionlessAndHoldIsNotContinuous() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_CALLGTE_MOCK_DATA, ApiTxs.CREATE_CALLGTE_MOCK_VALUE, PAYER);
        require(ok, "create call_gte failed");
        // poke while false records nothing
        require(_poke(id, 0, OTHER), "poke while false succeeds (no-op)");
        require(_since(id, 0) == 0, "poke while false must record nothing");
        // blip true for an instant; the PAYEE themself pokes (permissionless)
        mock.set(100);
        require(_poke(id, 0, PAYEE), "payee themself can poke (permissionless)");
        require(_since(id, 0) == block.timestamp, "poke records first-true time");
        // condition goes false for the whole 10 minutes
        mock.set(0);
        vm.warp(block.timestamp + 600);
        require(!_release(id, OTHER), "release while currently false MUST revert");
        // ...and true again for a single instant at release time
        mock.set(100);
        uint256 before = PAYEE.balance;
        require(_release(id, OTHER), "release succeeds after two brief true-blips 10 min apart");
        require(PAYEE.balance - before == 0.001 ether, "payee paid in full");
    }

    // ---- T23: release still requires the condition to be true right now ----
    function testReleaseRequiresCurrentTruth() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE_CALLGTE_MOCK_DATA, ApiTxs.CREATE_CALLGTE_MOCK_VALUE, PAYER);
        require(ok, "create call_gte failed");
        mock.set(100);
        require(_poke(id, 0, OTHER), "poke must succeed");
        vm.warp(block.timestamp + 601);
        mock.set(0);
        require(!_release(id, OTHER), "release with condition now false MUST revert");
        require(_met(id)[0] == false, "met flag false while value is 0");
    }
    // fee signature binds the full condition list, so no signed quote for them can exist.
    // (Probed log-only in Probe.t.sol during the hunt; crafted creates revert BadQuote.)
    function testUnknownKinds() public {
        for (uint8 k = 2; k <= 3; k++) {
            Cond[] memory conds = new Cond[](1);
            conds[0] = Cond({kind: k, target: address(mock), data: abi.encodeWithSelector(MockCall.get.selector), value: 100});
            bytes memory data = _craft(PAYEE, 0.001 ether, uint64(block.timestamp + 72 hours), conds, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
            vm.prank(PAYER);
            (bool ok,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI}(data);
            require(!ok, "crafted kind 2/3 create MUST revert (no valid fee quote can exist for it)");
        }
    }

    // ---- T21: fee quote binds EVERY field of p (single-field variations all revert) ----
    function testFeeQuoteBindsEveryField() public {
        Cond[] memory orig = new Cond[](2);
        orig[0] = Cond({kind: 1, target: ARB, data: "", value: 0});
        orig[1] = Cond({kind: 0, target: address(0), data: "", value: ApiTxs.CREATE1_TIMEAFTER});
        // (a) conditions only: swap attest+time for a past time_after
        Cond[] memory condsA = new Cond[](1);
        condsA[0] = Cond({kind: 0, target: address(0), data: "", value: 1700000000});
        bytes memory dataA = _craft(PAYEE, 0.001 ether, uint64(ApiTxs.CREATE1_P_EXPIRY), condsA, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool okA,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI}(dataA);
        require(!okA, "varying conditions only MUST revert");
        // (b) amount only
        bytes memory dataB = _craft(PAYEE, 0.002 ether, uint64(ApiTxs.CREATE1_P_EXPIRY), orig, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool okB,) = AGR.call{value: 0.002 ether + ApiTxs.Q1_FEEWEI}(dataB);
        require(!okB, "varying amount only MUST revert");
        // (c) payee only
        bytes memory dataC = _craft(OTHER, 0.001 ether, uint64(ApiTxs.CREATE1_P_EXPIRY), orig, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool okC,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI}(dataC);
        require(!okC, "varying payee only MUST revert");
        // (d) expiry only
        bytes memory dataD = _craft(PAYEE, 0.001 ether, uint64(ApiTxs.CREATE1_P_EXPIRY) + 3600, orig, ApiTxs.Q1_FEEWEI, uint64(ApiTxs.Q1_EXPIRY), ApiTxs.Q1_SIG);
        vm.prank(PAYER);
        (bool okD,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI}(dataD);
        require(!okD, "varying expiry only MUST revert");
        // (e) termsHash only
        P memory p = P({payee: PAYEE, asset: address(0), amount: 0.001 ether, expiry: uint64(ApiTxs.CREATE1_P_EXPIRY), termsHash: bytes32(uint256(1)), conditions: orig});
        Q memory q = Q({feeWei: ApiTxs.Q1_FEEWEI, expiry: uint64(ApiTxs.Q1_EXPIRY), sig: ApiTxs.Q1_SIG});
        bytes memory dataE = abi.encodeWithSelector(SEL_CREATE, p, q);
        vm.prank(PAYER);
        (bool okE,) = AGR.call{value: 0.001 ether + ApiTxs.Q1_FEEWEI}(dataE);
        require(!okE, "varying termsHash only MUST revert");
        // (f) payer only: same quote submitted by a different wallet
        vm.prank(OTHER);
        (bool okF,) = AGR.call{value: ApiTxs.CREATE1_VALUE}(ApiTxs.CREATE1_DATA);
        require(!okF, "submitting another payer's quote MUST revert");
    }

    // ---- T18: attest twice is idempotent (second call succeeds, flag stays 1) ----
    function testAttestTwice() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(_attest(id, 0, ARB), "first attest must succeed");
        require(_attest(id, 0, ARB), "second attest is idempotent (succeeds, no state change)");
        require(_attested(id, 0) == 1, "attested flag stays 1");
        vm.warp(block.timestamp + 3700);
        require(_release(id, OTHER), "release must still succeed after double attest");
    }

    // ---- T19: release by payer/payee themselves (anyone-can-release) ----
    function testReleaseByAnyone() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        require(_attest(id, 0, ARB), "attest must succeed");
        vm.warp(block.timestamp + 3700);
        require(_release(id, PAYER), "release by payer must succeed (documented anyone-can-release)");
    }

    // ---- T20: refund to payer only, not to caller ----
    function testRefundGoesToPayer() public {
        (uint256 id, bool ok) = _create(ApiTxs.CREATE1_DATA, ApiTxs.CREATE1_VALUE, PAYER);
        require(ok, "create failed");
        vm.warp(ApiTxs.CREATE1_P_EXPIRY + 1);
        uint256 otherBefore = OTHER.balance;
        require(_refund(id, OTHER), "refund by anyone must succeed after expiry");
        require(OTHER.balance == otherBefore, "caller must NOT receive the refund");
        // PAYER started with 300 ether, paid 0.001 + fee to create, got 0.001 back.
        require(PAYER.balance == 300 ether - ApiTxs.Q1_FEEWEI, "payer must be refunded exactly the amount");
    }
}
