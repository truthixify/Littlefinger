use littlefinger::structs::member_structs::MemberInvite;
use starknet::{ClassHash, ContractAddress};

#[starknet::interface]
pub trait IFactory<T> {
    // fn deploy_vault(
    //     ref self: T,
    //     // class_hash: felt252, //unwrap it into class has using into, and it will be removed
    //     once I declare the vault available_funds: u256,
    //     starting_bonus_allocation: u256,
    //     token: ContractAddress,
    //     salt: felt252,
    // ) -> ContractAddress;
    // // Initialize organization
    // // Initialize member
    // // If custom owner is not supplied at deployment, deployer is used as owner, and becomes the
    // first admin fn deploy_org_core(
    //     ref self: T,
    //     // class_hash: felt252,
    //     // Needed to initialize the organization component
    //     owner: Option<ContractAddress>,
    //     name: ByteArray,
    //     ipfs_url: ByteArray,
    //     vault_address: ContractAddress,
    //     // Needed to initialize the member component
    //     first_admin_fname: felt252,
    //     first_admin_lname: felt252,
    //     first_admin_alias: felt252,
    //     salt: felt252,
    // ) -> ContractAddress;
    fn setup_org(
        ref self: T,
        // class_hash: felt252, //unwrap it into class has using into, and it will be removed once I
        // declare the vault
        token: ContractAddress,
        salt: felt252,
        // class_hash: felt252,
        // Needed to initialize the organization component
        owner: ContractAddress,
        name: ByteArray,
        ipfs_url: ByteArray,
        // vault_address: ContractAddress,
        // Needed to initialize the member component
        first_admin_fname: felt252,
        first_admin_lname: felt252,
        first_admin_alias: felt252,
        organization_type: u8,
        // salt: felt252,
    ) -> (ContractAddress, ContractAddress);
    fn get_deployed_vaults(self: @T) -> Array<ContractAddress>;
    fn get_deployed_org_cores(self: @T) -> Array<ContractAddress>;
    fn get_vault_org_pairs(
        self: @T, caller: ContractAddress,
    ) -> Array<(ContractAddress, ContractAddress)>;
    fn get_member_orgs(self: @T, caller: ContractAddress) -> Array<ContractAddress>;
    fn update_vault_hash(ref self: T, vault_hash: ClassHash);
    fn update_core_hash(ref self: T, core_hash: ClassHash);
    fn update_member_of(ref self: T, member: ContractAddress, org_core: ContractAddress);
    fn create_invite(
        ref self: T,
        invitee: ContractAddress,
        invite_details: MemberInvite,
        core_org: ContractAddress,
    );
    fn accpet_invite(ref self: T, invitee: ContractAddress);
    fn get_invite_details(self: @T, invitee: ContractAddress) -> MemberInvite;
    // fn get_vault_org_pairs(self: @T) -> Array<(ContractAddress, ContractAddress)>;

    // in the future, you can upgrade a deployed org core from here
// fn initialize_upgrade(ref self: T, vaults: Array<ContractAddress>, cores:
// Array<ContractAddress>);
// this function would pick the updated class hash from the storage, if the class hash has been
// updated at present, it can only pick the latest...
// in the future, it can pick a specific class hash version
}
