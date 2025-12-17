import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.7.1/index.ts';
import { assertEquals, assertExists } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
    name: "Can register as creator",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Content creator and artist")
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Cannot register twice",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Bio")
            ], creator.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice2"),
                types.ascii("Bio 2")
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(22005); // ERR_ALREADY_REGISTERED
    }
});

Clarinet.test({
    name: "Can send tip to creator",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        const tipper = accounts.get('wallet_2')!;
        
        // Register creator first
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Bio")
            ], creator.address)
        ]);
        
        // Send tip
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'send-tip', [
                types.principal(creator.address),
                types.uint(1000000), // 1 STX
                types.none(),
                types.some(types.ascii("Great content!"))
            ], tipper.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Protocol fee is 2.5%",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        // 2.5% of 100 STX = 2.5 STX
        let fee = chain.callReadOnlyFn(
            'tip-manager',
            'calculate-fee',
            [types.uint(100000000)],
            user.address
        );
        
        assertEquals(fee.result, 'u2500000'); // 2.5 STX
    }
});

Clarinet.test({
    name: "Minimum tip is 0.1 STX",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        const tipper = accounts.get('wallet_2')!;
        
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Bio")
            ], creator.address)
        ]);
        
        // Try to send too small tip
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'send-tip', [
                types.principal(creator.address),
                types.uint(50000), // 0.05 STX - too small
                types.none(),
                types.none()
            ], tipper.address)
        ]);
        
        block.receipts[0].result.expectErr().expectUint(22003); // ERR_INVALID_AMOUNT
    }
});

Clarinet.test({
    name: "Can post content",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Bio")
            ], creator.address)
        ]);
        
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'post-content', [
                types.ascii("video"),
                types.buff(Buffer.alloc(32, 1)),
                types.ascii("My awesome video")
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(1);
    }
});

Clarinet.test({
    name: "Get protocol stats",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const user = accounts.get('wallet_1')!;
        
        let stats = chain.callReadOnlyFn(
            'tip-manager',
            'get-protocol-stats',
            [],
            user.address
        );
        
        const data = stats.result.expectTuple();
        assertEquals(data['total-tips'], types.uint(0));
        assertEquals(data['total-creators'], types.uint(0));
    }
});

Clarinet.test({
    name: "Can withdraw earnings",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const creator = accounts.get('wallet_1')!;
        const tipper = accounts.get('wallet_2')!;
        
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'register-creator', [
                types.ascii("alice"),
                types.ascii("Bio")
            ], creator.address)
        ]);
        
        // Send tip
        chain.mineBlock([
            Tx.contractCall('tip-manager', 'send-tip', [
                types.principal(creator.address),
                types.uint(10000000), // 10 STX
                types.none(),
                types.none()
            ], tipper.address)
        ]);
        
        // Withdraw (10 STX - 2.5% fee = 9.75 STX)
        let block = chain.mineBlock([
            Tx.contractCall('tip-manager', 'withdraw-earnings', [
                types.uint(9750000)
            ], creator.address)
        ]);
        
        block.receipts[0].result.expectOk().expectUint(9750000);
    }
});
