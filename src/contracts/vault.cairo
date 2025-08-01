#[starknet::contract]
pub mod Vault {
    use core::num::traits::Zero;
    use littlefinger::interfaces::ivault::IVault;
    use littlefinger::structs::vault_structs::{Transaction, TransactionType, VaultStatus};
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin::upgrades::UpgradeableComponent;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };
    use starknet::{
        ContractAddress, get_block_timestamp, get_caller_address, get_contract_address, get_tx_info,
    };
    // use openzeppelin::upgrades::interface::IUpgradeable;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[storage]
    struct Storage {
        permitted_addresses: Map<ContractAddress, bool>,
        available_funds: u256,
        total_bonus: u256,
        transaction_history: Map<
            u64, Transaction,
        >, // No 1. Transaction x, no 2, transaction y etc for history, and it begins with 1
        transactions_count: u64,
        vault_status: VaultStatus,
        token: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        DepositSuccessful: DepositSuccessful,
        WithdrawalSuccessful: WithdrawalSuccessful,
        VaultFrozen: VaultFrozen,
        VaultResumed: VaultResumed,
        TransactionRecorded: TransactionRecorded,
        BonusAllocation: BonusAllocation,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        // TODO:
    // Add an event here that gets emitted if the money goes below a certain threshold
    // Threshold Will be decided.
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct DepositSuccessful {
        caller: ContractAddress,
        token: ContractAddress,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct WithdrawalSuccessful {
        caller: ContractAddress,
        token: ContractAddress,
        amount: u256,
        timestamp: u64,
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct VaultFrozen {
        caller: ContractAddress,
        timestamp: u64,
    }

    #[derive(Copy, Drop, starknet::Event)]
    pub struct VaultResumed {
        caller: ContractAddress,
        timestamp: u64,
    }

    #[derive(Drop, starknet::Event)]
    pub struct TransactionRecorded {
        transaction_type: TransactionType,
        caller: ContractAddress,
        transaction_details: Transaction,
        token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct BonusAllocation {
        amount: u256,
        timestamp: u64,
    }

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;

    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    // TODO:
    // Add to this constructor, a way to add addresses and store them as permitted addresses here
    #[constructor]
    fn constructor(
        ref self: ContractState,
        token: ContractAddress, // available_funds: u256,
        // bonus_allocation: u256,
        owner: ContractAddress,
    ) {
        self.token.write(token);
        self.total_bonus.write(0);
        self.permitted_addresses.entry(owner).write(true);

        self._sync_available_funds();
    }

    // TODO:
    // From the ivault, add functions in the interfaces for subtracting from and adding to bonus
    // IMPLEMENT HERE

    // TODO:
    // Implement a storage variable, that will be in the constructor, for the token address to be
    // supplied at deployment For now, we want a single-token implementation

    #[abi(embed_v0)]
    pub impl VaultImpl of IVault<ContractState> {
        fn deposit_funds(ref self: ContractState, amount: u256, address: ContractAddress) {
            assert(amount.is_non_zero(), 'Invalid Amount');
            assert(address.is_non_zero(), 'Invalid Address');
            let caller = get_caller_address();
            let permitted = self.permitted_addresses.entry(caller).read();
            assert(permitted, 'Direct Caller not permitted');
            assert(self.permitted_addresses.entry(address).read(), 'Deep Caller Not Permitted');
            let current_vault_status = self.vault_status.read();
            assert(
                current_vault_status != VaultStatus::VAULTFROZEN, 'Vault Frozen for Transactions',
            );

            self._sync_available_funds();

            let timestamp = get_block_timestamp();
            let this_contract = get_contract_address();
            let token = self.token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token };

            token_dispatcher.transfer_from(address, this_contract, amount);

            self._record_transaction(token, amount, TransactionType::DEPOSIT, address);

            self._sync_available_funds();

            self.emit(DepositSuccessful { caller: address, token, timestamp, amount })
        }

        fn withdraw_funds(ref self: ContractState, amount: u256, address: ContractAddress) {
            assert(amount.is_non_zero(), 'Invalid Amount');
            assert(address.is_non_zero(), 'Invalid Address');
            let caller = get_caller_address();
            let permitted = self.permitted_addresses.entry(caller).read();
            assert(permitted, 'Direct Caller not permitted');
            assert(self.permitted_addresses.entry(address).read(), 'Deep Caller Not Permitted');

            let current_vault_status = self.vault_status.read();
            assert(
                current_vault_status != VaultStatus::VAULTFROZEN, 'Vault Frozen for Transactions',
            );

            self._sync_available_funds();

            let timestamp = get_block_timestamp();

            let token = self.token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token };
            let vault_balance = token_dispatcher.balance_of(get_contract_address());
            assert(amount <= vault_balance, 'Insufficient Balance');

            token_dispatcher.transfer(address, amount);
            self._record_transaction(token, amount, TransactionType::WITHDRAWAL, address);

            self._sync_available_funds();

            self.emit(WithdrawalSuccessful { caller: address, token, amount, timestamp })
        }

        fn add_to_bonus_allocation(
            ref self: ContractState, amount: u256, address: ContractAddress,
        ) {
            assert(amount.is_non_zero(), 'Invalid Amount');
            assert(address.is_non_zero(), 'Invalid Address');
            let caller = get_caller_address();
            let permitted = self.permitted_addresses.entry(caller).read();
            assert(permitted, 'Direct Caller not permitted');
            assert(self.permitted_addresses.entry(address).read(), 'Deep Caller Not Permitted');

            self._sync_available_funds();

            self.total_bonus.write(self.total_bonus.read() + amount);
            self
                ._record_transaction(
                    self.token.read(), amount, TransactionType::BONUS_ALLOCATION, address,
                );
        }

        fn emergency_freeze(ref self: ContractState) {
            let caller = get_caller_address();
            let permitted = self.permitted_addresses.entry(caller).read();
            assert(permitted, 'Caller not permitted');
            assert(self.vault_status.read() != VaultStatus::VAULTFROZEN, 'Vault Already Frozen');

            self.vault_status.write(VaultStatus::VAULTFROZEN);
        }

        fn unfreeze_vault(ref self: ContractState) {
            let caller = get_caller_address();
            let permitted = self.permitted_addresses.entry(caller).read();
            assert(permitted, 'Caller not permitted');
            assert(self.vault_status.read() != VaultStatus::VAULTRESUMED, 'Vault Not Frozen');

            self.vault_status.write(VaultStatus::VAULTRESUMED);
        }
        // fn bulk_transfer(ref self: ContractState, recipients: Span<ContractAddress>) {}
        fn get_balance(self: @ContractState) -> u256 {
            // let caller = get_caller_address();
            // assert(self.permitted_addresses.entry(caller).read(), 'Caller Not Permitted');
            let token_address = self.token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let vault_address = get_contract_address();
            let balance = token_dispatcher.balance_of(vault_address);
            balance
        }

        fn get_available_funds(self: @ContractState) -> u256 {
            self.available_funds.read()
        }

        fn get_bonus_allocation(self: @ContractState) -> u256 {
            // let caller = get_caller_address();
            // assert(self.permitted_addresses.entry(caller).read(), 'Caller Not Permitted');
            self.total_bonus.read()
        }

        fn pay_member(ref self: ContractState, recipient: ContractAddress, amount: u256) {
            assert(recipient.is_non_zero(), 'Invalid Address');
            assert(amount.is_non_zero(), 'Invalid Amount');
            let caller = get_caller_address();
            assert(self.permitted_addresses.entry(caller).read(), 'Caller Not Permitted');

            self._sync_available_funds();

            let token_address = self.token.read();
            let token = IERC20Dispatcher { contract_address: token_address };
            let token_balance = token.balance_of(get_contract_address());
            assert(amount <= token_balance, 'Amount Overflow');
            let transfer = token.transfer(recipient, amount);
            assert(transfer, 'Transfer failed');
            self._record_transaction(token_address, amount, TransactionType::PAYMENT, caller);

            self._sync_available_funds();
        }

        fn get_vault_status(self: @ContractState) -> VaultStatus {
            self.vault_status.read()
        }

        fn get_transaction_history(self: @ContractState) -> Array<Transaction> {
            let mut transaction_history = array![];

            for i in 1..self.transactions_count.read() + 1 {
                let current_transaction = self.transaction_history.entry(i).read();
                transaction_history.append(current_transaction);
            }

            transaction_history
        }

        fn allow_org_core_address(ref self: ContractState, org_address: ContractAddress) {
            assert(org_address.is_non_zero(), 'Invalid Address');
            self.permitted_addresses.entry(org_address).write(true);
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalTrait {
        fn _add_transaction(ref self: ContractState, transaction: Transaction) {
            let caller = get_caller_address();
            assert(self.permitted_addresses.entry(caller).read(), 'Caller not permitted');
            let current_transaction_count = self.transactions_count.read();
            self.transaction_history.entry(current_transaction_count + 1).write(transaction);
            self.transactions_count.write(current_transaction_count + 1);
        }

        fn _record_transaction(
            ref self: ContractState,
            token_address: ContractAddress,
            amount: u256,
            transaction_type: TransactionType,
            caller: ContractAddress,
        ) {
            let actual_caller = get_caller_address();
            assert(self.permitted_addresses.entry(actual_caller).read(), 'Caller Not Permitted');
            let timestamp = get_block_timestamp();
            let tx_info = get_tx_info();
            let transaction = Transaction {
                transaction_type,
                token: token_address,
                amount,
                timestamp,
                tx_hash: tx_info.transaction_hash,
                caller,
            };
            self._add_transaction(transaction);
            self
                .emit(
                    TransactionRecorded {
                        transaction_type,
                        caller: actual_caller,
                        transaction_details: transaction,
                        token: token_address,
                    },
                );
        }

        fn _sync_available_funds(ref self: ContractState) {
            let token_address = self.token.read();
            let token_dispatcher = IERC20Dispatcher { contract_address: token_address };
            let vault_address = get_contract_address();
            let actual_balance = token_dispatcher.balance_of(vault_address);
            self.available_funds.write(actual_balance);
        }
    }
}
